import AVFoundation
import Speech

@MainActor
enum SpeechServiceFactory {
    static func live(locale: Locale = .current) -> any SpeechRecognitionService {
        if #available(iOS 26.0, *) {
            return SpeechAnalyzerRecognitionService(locale: locale)
        }
        return LegacySpeechRecognitionService(locale: locale)
    }
}

@MainActor
private func requestSpeechAndMicrophoneAuthorisation() async -> SpeechAuthorisationStatus {
    let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard speechStatus == .authorized else {
        switch speechStatus {
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notDetermined
        }
    }

    let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
    return microphoneAllowed ? .authorised : .denied
}

@MainActor
private final class LegacySpeechRecognitionService: SpeechRecognitionService {
    private let locale: Locale
    private let audioEngine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var continuation: AsyncThrowingStream<SpeechRecognitionUpdate, Error>.Continuation?

    init(locale: Locale) {
        self.locale = locale
    }

    func requestAuthorisation() async -> SpeechAuthorisationStatus {
        await requestSpeechAndMicrophoneAuthorisation()
    }

    func start() async throws -> AsyncThrowingStream<SpeechRecognitionUpdate, Error> {
        await stop()
        guard await requestAuthorisation() == .authorised else {
            throw SpeechRecognitionError.permissionDenied
        }
        guard let recogniser = SFSpeechRecognizer(locale: locale), recogniser.isAvailable else {
            throw SpeechRecognitionError.unavailable
        }
        guard recogniser.supportsOnDeviceRecognition else {
            throw SpeechRecognitionError.onDeviceRecognitionUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let (stream, continuation) = AsyncThrowingStream<SpeechRecognitionUpdate, Error>.makeStream()
        self.continuation = continuation
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw SpeechRecognitionError.audioInputUnavailable }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recogniser.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let confidence = result.bestTranscription.segments.last.map { Double($0.confidence) }
                    self.continuation?.yield(
                        SpeechRecognitionUpdate(
                            text: result.bestTranscription.formattedString,
                            isFinal: result.isFinal,
                            timestamp: Date(),
                            confidence: confidence
                        )
                    )
                }
                if let error {
                    self.continuation?.finish(throwing: error)
                    self.continuation = nil
                } else if result?.isFinal == true {
                    self.continuation?.finish()
                    self.continuation = nil
                }
            }
        }
        return stream
    }

    func stop() async {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        continuation?.finish()
        continuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@available(iOS 26.0, *)
@MainActor
private final class SpeechAnalyzerRecognitionService: SpeechRecognitionService {
    private let locale: Locale
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var reservedLocale: Locale?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var outputContinuation: AsyncThrowingStream<SpeechRecognitionUpdate, Error>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?

    init(locale: Locale) {
        self.locale = locale
    }

    func requestAuthorisation() async -> SpeechAuthorisationStatus {
        await requestSpeechAndMicrophoneAuthorisation()
    }

    func start() async throws -> AsyncThrowingStream<SpeechRecognitionUpdate, Error> {
        await stop()
        guard await requestAuthorisation() == .authorised else {
            throw SpeechRecognitionError.permissionDenied
        }
        guard SpeechTranscriber.isAvailable,
              let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechRecognitionError.onDeviceRecognitionUnavailable
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .progressiveTranscription)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        _ = try await AssetInventory.reserve(locale: supportedLocale)
        reservedLocale = supportedLocale

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw SpeechRecognitionError.audioInputUnavailable }
        try await analyzer.prepareToAnalyze(in: format)

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation
        let (outputStream, outputContinuation) = AsyncThrowingStream<SpeechRecognitionUpdate, Error>.makeStream()
        self.outputContinuation = outputContinuation

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, time in
            let timestamp = CMTime(value: time.sampleTime, timescale: CMTimeScale(format.sampleRate.rounded()))
            inputContinuation.yield(AnalyzerInput(buffer: buffer, bufferStartTime: timestamp))
        }
        audioEngine.prepare()
        try audioEngine.start()

        analysisTask = Task {
            do {
                try await analyzer.start(inputSequence: inputStream)
            } catch is CancellationError {
                // Expected when the user pauses or leaves the teleprompter.
            } catch {
                outputContinuation.finish(throwing: error)
            }
        }
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    outputContinuation.yield(
                        SpeechRecognitionUpdate(
                            text: String(result.text.characters),
                            isFinal: result.isFinal,
                            timestamp: Date(),
                            confidence: nil
                        )
                    )
                }
            } catch is CancellationError {
                // Expected when the user pauses or leaves the teleprompter.
            } catch {
                outputContinuation.finish(throwing: error)
            }
        }
        return outputStream
    }

    func stop() async {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        inputContinuation?.finish()
        inputContinuation = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        analysisTask?.cancel()
        resultsTask?.cancel()
        analysisTask = nil
        resultsTask = nil
        outputContinuation?.finish()
        outputContinuation = nil
        if let reservedLocale {
            _ = await AssetInventory.release(reservedLocale: reservedLocale)
            self.reservedLocale = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
