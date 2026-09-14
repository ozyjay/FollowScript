import AVFoundation
import CoreMedia
import Speech

@available(iOS 26.0, *)
enum FollowScriptSpeechTranscriberConfiguration {
    static var stableProgressivePreset: SpeechTranscriber.Preset {
        SpeechTranscriber.Preset(
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .alternativeTranscriptions],
            attributeOptions: [.audioTimeRange]
        )
    }
}

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

private func currentAudioInput(in session: AVAudioSession) -> AudioInputDescriptor? {
    guard let port = session.currentRoute.inputs.first else { return nil }
    return AudioInputDescriptor(
        name: port.portName,
        isExternal: port.portType != .builtInMic
    )
}

private func currentMicrophoneGain(in session: AVAudioSession) -> MicrophoneGainState {
    MicrophoneGainState(isAdjustable: session.isInputGainSettable, value: Double(session.inputGain))
}

private func setCurrentMicrophoneGain(_ value: Double) throws {
    let session = AVAudioSession.sharedInstance()
    guard session.isInputGainSettable else { return }
    try session.setInputGain(Float(min(1, max(0, value))))
}

@MainActor
private final class LegacySpeechRecognitionService: SpeechRecognitionService {
    private let locale: Locale
    private let audioEngine = AVAudioEngine()
    private var lifecycleGeneration = 0
    private var tapInstalled = false
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var continuation: AsyncThrowingStream<SpeechRecognitionUpdate, Error>.Continuation?
    private let captureMonitor = MicrophoneCaptureMonitor()
    private var microphoneFormat: AVAudioFormat?
    private var routeChangeTask: Task<Void, Never>?

    init(locale: Locale) {
        self.locale = locale
    }

    func requestAuthorisation() async -> SpeechAuthorisationStatus {
        await requestSpeechAndMicrophoneAuthorisation()
    }

    func start() async throws -> AsyncThrowingStream<SpeechRecognitionUpdate, Error> {
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        await tearDownCurrentSession()

        do {
            try ensureCurrent(generation)
            guard await requestAuthorisation() == .authorised else {
                throw SpeechRecognitionError.permissionDenied
            }
            try ensureCurrent(generation)
            guard let recogniser = SFSpeechRecognizer(locale: locale), recogniser.isAvailable else {
                throw SpeechRecognitionError.unavailable
            }
            guard recogniser.supportsOnDeviceRecognition else {
                throw SpeechRecognitionError.onDeviceRecognitionUnavailable
            }

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            reportCurrentAudioInput()
            monitorAudioRouteChanges()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request

            let (stream, continuation) = AsyncThrowingStream<SpeechRecognitionUpdate, Error>.makeStream()
            self.continuation = continuation
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw SpeechRecognitionError.audioInputUnavailable }
            microphoneFormat = format
            try ensureCurrent(generation)

            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                self.captureMonitor.process(buffer)
                request.append(buffer)
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()

            task = recogniser.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, generation == self.lifecycleGeneration else { return }
                    if let result {
                        let confidence = result.bestTranscription.segments.last.map { Double($0.confidence) }
                        self.continuation?.yield(
                            SpeechRecognitionUpdate(
                                text: result.bestTranscription.formattedString,
                                isFinal: result.isFinal,
                                timestamp: Date(),
                                audioTimeRange: result.bestTranscription.segments.last.map {
                                    $0.timestamp..<($0.timestamp + $0.duration)
                                },
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
        } catch {
            if generation == lifecycleGeneration {
                await tearDownCurrentSession()
            }
            throw error
        }
    }

    func stop() async {
        lifecycleGeneration &+= 1
        await tearDownCurrentSession()
    }

    func audioInputEvents() -> AsyncStream<AudioInputEvent> { captureMonitor.events() }

    func setInputGain(_ value: Double) throws {
        try setCurrentMicrophoneGain(value)
        captureMonitor.reportGain(currentMicrophoneGain(in: .sharedInstance()))
    }

    func startRecording() throws {
        guard let microphoneFormat else { throw AudioRecordingError.microphoneNotRunning }
        try captureMonitor.startRecording(format: microphoneFormat)
    }

    func stopRecording() throws -> URL? { captureMonitor.stopRecording() }

    private func reportCurrentAudioInput() {
        if let input = currentAudioInput(in: .sharedInstance()) {
            captureMonitor.reportInput(input)
        }
        captureMonitor.reportGain(currentMicrophoneGain(in: .sharedInstance()))
    }

    private func monitorAudioRouteChanges() {
        routeChangeTask?.cancel()
        routeChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification
            ) {
                guard !Task.isCancelled else { return }
                self?.reportCurrentAudioInput()
            }
        }
    }

    private func ensureCurrent(_ generation: Int) throws {
        try Task.checkCancellation()
        guard generation == lifecycleGeneration else { throw CancellationError() }
    }

    private func tearDownCurrentSession() async {
        routeChangeTask?.cancel()
        routeChangeTask = nil
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.reset()
        microphoneFormat = nil
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
    private var lifecycleGeneration = 0
    private var tapInstalled = false
    private var analyzer: SpeechAnalyzer?
    private var reservedLocale: Locale?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var outputContinuation: AsyncThrowingStream<SpeechRecognitionUpdate, Error>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private let captureMonitor = MicrophoneCaptureMonitor()
    private var microphoneFormat: AVAudioFormat?
    private var routeChangeTask: Task<Void, Never>?

    init(locale: Locale) {
        self.locale = locale
    }

    func requestAuthorisation() async -> SpeechAuthorisationStatus {
        await requestSpeechAndMicrophoneAuthorisation()
    }

    func start() async throws -> AsyncThrowingStream<SpeechRecognitionUpdate, Error> {
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        await tearDownCurrentSession()

        do {
            try ensureCurrent(generation)
            guard await requestAuthorisation() == .authorised else {
                throw SpeechRecognitionError.permissionDenied
            }
            try ensureCurrent(generation)
            guard SpeechTranscriber.isAvailable,
                  let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                throw SpeechRecognitionError.onDeviceRecognitionUnavailable
            }
            try ensureCurrent(generation)

            let transcriber = SpeechTranscriber(
                locale: supportedLocale,
                preset: FollowScriptSpeechTranscriberConfiguration.stableProgressivePreset
            )
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try ensureCurrent(generation)
                try await installation.downloadAndInstall()
            }
            try ensureCurrent(generation)
            _ = try await AssetInventory.reserve(locale: supportedLocale)
            reservedLocale = supportedLocale
            try ensureCurrent(generation)

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            reportCurrentAudioInput()
            monitorAudioRouteChanges()

            let inputNode = audioEngine.inputNode
            let microphoneFormat = inputNode.outputFormat(forBus: 0)
            guard microphoneFormat.sampleRate > 0 else {
                throw SpeechRecognitionError.audioInputUnavailable
            }
            self.microphoneFormat = microphoneFormat
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber],
                considering: microphoneFormat
            ), analyzerFormat.commonFormat == .pcmFormatInt16 else {
                throw SpeechRecognitionError.audioConversionFailed
            }
            let audioConverter = try SpeechAudioBufferConverter(
                inputFormat: microphoneFormat,
                outputFormat: analyzerFormat
            )
            try await analyzer.prepareToAnalyze(in: analyzerFormat)
            try ensureCurrent(generation)

            let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.inputContinuation = inputContinuation
            let (outputStream, outputContinuation) = AsyncThrowingStream<SpeechRecognitionUpdate, Error>.makeStream()
            self.outputContinuation = outputContinuation

            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: microphoneFormat) { buffer, _ in
                self.captureMonitor.process(buffer)
                do {
                    let convertedBuffer = try audioConverter.convert(buffer)
                    inputContinuation.yield(AnalyzerInput(buffer: convertedBuffer))
                } catch {
                    inputContinuation.finish()
                    outputContinuation.finish(throwing: error)
                }
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()

            analysisTask = Task { [weak self] in
                do {
                    try await analyzer.start(inputSequence: inputStream)
                } catch is CancellationError {
                    // Expected when the user pauses or leaves the teleprompter.
                } catch {
                    guard let self, generation == self.lifecycleGeneration else { return }
                    outputContinuation.finish(throwing: error)
                }
            }
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self, generation == self.lifecycleGeneration else { return }
                        outputContinuation.yield(
                            SpeechRecognitionUpdate(
                                text: String(result.text.characters),
                                alternatives: result.alternatives.map { String($0.characters) },
                                isFinal: result.isFinal,
                                timestamp: Date(),
                                audioTimeRange: result.range.secondsRange,
                                confidence: nil
                            )
                        )
                    }
                } catch is CancellationError {
                    // Expected when the user pauses or leaves the teleprompter.
                } catch {
                    guard let self, generation == self.lifecycleGeneration else { return }
                    outputContinuation.finish(throwing: error)
                }
            }
            return outputStream
        } catch {
            if generation == lifecycleGeneration {
                await tearDownCurrentSession()
            }
            throw error
        }
    }

    func stop() async {
        lifecycleGeneration &+= 1
        await tearDownCurrentSession()
    }

    func audioInputEvents() -> AsyncStream<AudioInputEvent> { captureMonitor.events() }

    func setInputGain(_ value: Double) throws {
        try setCurrentMicrophoneGain(value)
        captureMonitor.reportGain(currentMicrophoneGain(in: .sharedInstance()))
    }

    func startRecording() throws {
        guard let microphoneFormat else { throw AudioRecordingError.microphoneNotRunning }
        try captureMonitor.startRecording(format: microphoneFormat)
    }

    func stopRecording() throws -> URL? { captureMonitor.stopRecording() }

    private func reportCurrentAudioInput() {
        if let input = currentAudioInput(in: .sharedInstance()) {
            captureMonitor.reportInput(input)
        }
        captureMonitor.reportGain(currentMicrophoneGain(in: .sharedInstance()))
    }

    private func monitorAudioRouteChanges() {
        routeChangeTask?.cancel()
        routeChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification
            ) {
                guard !Task.isCancelled else { return }
                self?.reportCurrentAudioInput()
            }
        }
    }

    private func ensureCurrent(_ generation: Int) throws {
        try Task.checkCancellation()
        guard generation == lifecycleGeneration else { throw CancellationError() }
    }

    private func tearDownCurrentSession() async {
        routeChangeTask?.cancel()
        routeChangeTask = nil
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.reset()
        microphoneFormat = nil
        inputContinuation?.finish()
        inputContinuation = nil
        let analyzerToCancel = analyzer
        analyzer = nil
        analysisTask?.cancel()
        resultsTask?.cancel()
        analysisTask = nil
        resultsTask = nil
        outputContinuation?.finish()
        outputContinuation = nil
        let localeToRelease = reservedLocale
        reservedLocale = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        await analyzerToCancel?.cancelAndFinishNow()
        if let localeToRelease {
            _ = await AssetInventory.release(reservedLocale: localeToRelease)
        }
    }
}

@available(iOS 26.0, *)
private extension CMTimeRange {
    var secondsRange: Range<TimeInterval>? {
        let start = CMTimeGetSeconds(self.start)
        let duration = CMTimeGetSeconds(self.duration)
        guard start.isFinite, duration.isFinite, duration >= 0 else { return nil }
        return start..<(start + duration)
    }
}
