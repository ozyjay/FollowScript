import Foundation
import Combine

enum MicrophoneLevelQuality: String, Equatable {
    case quiet = "Too quiet"
    case good = "Good"
    case loud = "Too loud"

    init(level: Double) {
        if level < 0.22 { self = .quiet }
        else if level > 0.88 { self = .loud }
        else { self = .good }
    }
}

@MainActor
final class TeleprompterViewModel: ObservableObject {
    private enum ScrollConfiguration {
        static let minimumTokenAdvance = 2
        static let maximumAnimatedAdvance = 8
        static let catchUpInterval = Duration.milliseconds(220)
    }

    let script: ScriptDocument
    @Published private(set) var alignmentState = AlignmentState.initial
    @Published private(set) var recognisedText = ""
    @Published private(set) var matchedRange: ClosedRange<Int>?
    @Published private(set) var searchMode: AlignmentResult.SearchMode = .global
    @Published private(set) var candidateScore = 0.0
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var scrollTarget: Int?
    @Published private(set) var automaticFollowingSuspended = false
    @Published private(set) var audioLevel = 0.0
    @Published private(set) var audioInput: AudioInputDescriptor?
    @Published private(set) var audioInputWarning: String?
    @Published private(set) var isRecording = false
    @Published private(set) var latestRecordingURL: URL?
    @Published private(set) var recordingErrorMessage: String?

    private let service: any SpeechRecognitionService
    private let engine: ScriptAlignmentEngine
    private var recognitionTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var followResumeTask: Task<Void, Never>?
    private var audioLevelTask: Task<Void, Never>?
    private var scrollCatchUpTask: Task<Void, Never>?
    private var pendingScrollDestination: Int?
    private var lastScrollTarget: Int?
    private var wantsRecognition = false

    init(
        scriptText: String,
        service: (any SpeechRecognitionService)? = nil,
        engine: ScriptAlignmentEngine = ScriptAlignmentEngine()
    ) {
        script = ScriptDocument(text: scriptText)
        self.service = service ?? SpeechServiceFactory.live()
        self.engine = engine
    }

    var currentTokenIndex: Int? { alignmentState.tokenIndex }
    var confidence: Double { alignmentState.confidence }
    var trackingState: AlignmentTrackingState { alignmentState.trackingState }
    var microphoneLevelQuality: MicrophoneLevelQuality { .init(level: audioLevel) }

    func start() {
        wantsRecognition = true
        errorMessage = nil
        launchRecognitionIfNeeded()
        startMonitoringAudioLevel()
    }

    private func launchRecognitionIfNeeded() {
        guard recognitionTask == nil else { return }
        recognitionTask = Task { [weak self] in
            await self?.recognitionLoop()
        }
    }

    func pause() {
        finishRecording()
        wantsRecognition = false
        isListening = false
        audioLevel = 0
        restartTask?.cancel()
        restartTask = nil
        recognitionTask?.cancel()
    }

    func resume() {
        wantsRecognition = true
        errorMessage = nil
        guard let activeTask = recognitionTask else {
            launchRecognitionIfNeeded()
            return
        }

        restartTask?.cancel()
        restartTask = Task { [weak self] in
            await activeTask.value
            guard let self, self.wantsRecognition, !Task.isCancelled else { return }
            self.restartTask = nil
            self.launchRecognitionIfNeeded()
        }
    }

    func stop() {
        pause()
        restartTask?.cancel()
        restartTask = nil
        followResumeTask?.cancel()
        scrollCatchUpTask?.cancel()
        scrollCatchUpTask = nil
        audioLevelTask?.cancel()
        audioLevelTask = nil
    }

    func toggleRecording() {
        if isRecording {
            finishRecording()
            return
        }
        do {
            try service.startRecording()
            latestRecordingURL = nil
            recordingErrorMessage = nil
            isRecording = true
        } catch {
            recordingErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "FollowScript could not start recording."
        }
    }

    func clearRecordingError() {
        recordingErrorMessage = nil
    }

    func userDidScroll() {
        automaticFollowingSuspended = true
        scrollCatchUpTask?.cancel()
        scrollCatchUpTask = nil
        pendingScrollDestination = nil
        followResumeTask?.cancel()
        followResumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.returnToCurrentPosition()
        }
    }

    func returnToCurrentPosition() {
        followResumeTask?.cancel()
        scrollCatchUpTask?.cancel()
        scrollCatchUpTask = nil
        pendingScrollDestination = nil
        automaticFollowingSuspended = false
        if let currentTokenIndex {
            scrollTarget = currentTokenIndex
            lastScrollTarget = currentTokenIndex
        }
    }

    /// Establishes a new user-selected anchor. Automatic alignment remains forward-only from here.
    func moveFollowing(to tokenIndex: Int) {
        guard script.tokens.indices.contains(tokenIndex) else { return }
        alignmentState = AlignmentState(
            tokenIndex: tokenIndex,
            confidence: 1,
            trackingState: .tracking,
            lowConfidenceUpdates: 0
        )
        matchedRange = tokenIndex...tokenIndex
        searchMode = .local
        candidateScore = 1
        recognisedText = ""
        followResumeTask?.cancel()
        scrollCatchUpTask?.cancel()
        scrollCatchUpTask = nil
        pendingScrollDestination = nil
        automaticFollowingSuspended = false
        scrollTarget = tokenIndex
        lastScrollTarget = tokenIndex

        // Clear the recogniser's cumulative transcript so earlier speech cannot immediately
        // return alignment to the old position.
        if wantsRecognition {
            recognitionTask?.cancel()
            isListening = false
            resume()
        }
    }

    private func recognitionLoop() async {
        defer {
            if !wantsRecognition { finishRecording() }
            recognitionTask = nil
            isListening = false
        }
        while wantsRecognition && !Task.isCancelled {
            do {
                let stream = try await service.start()
                isListening = true
                for try await update in stream {
                    guard wantsRecognition, !Task.isCancelled else { break }
                    consume(update)
                }
                if wantsRecognition && !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(200))
                }
            } catch is CancellationError {
                break
            } catch {
                isListening = false
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Speech recognition could not continue."
                wantsRecognition = false
            }
        }
        await service.stop()
    }

    private func startMonitoringAudioLevel() {
        guard audioLevelTask == nil else { return }
        audioLevelTask = Task { [weak self, service] in
            for await event in service.audioInputEvents() {
                guard !Task.isCancelled else { break }
                switch event {
                case .level(let level):
                    self?.audioLevel = level
                case .inputChanged(let input):
                    guard let self else { break }
                    let lostExternalInput = self.audioInput?.isExternal == true && !input.isExternal
                    self.audioInput = input
                    self.audioInputWarning = lostExternalInput
                        ? "External microphone disconnected. Now using \(input.name)."
                        : nil
                case .recordingFailed(let message):
                    self?.isRecording = false
                    self?.recordingErrorMessage = "The recording stopped because audio could not be saved: \(message)"
                }
            }
        }
    }

    private func finishRecording() {
        guard isRecording else { return }
        do {
            latestRecordingURL = try service.stopRecording()
        } catch {
            recordingErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "FollowScript could not finish the recording."
        }
        isRecording = false
    }

    private func consume(_ update: SpeechRecognitionUpdate) {
        recognisedText = update.text
        let result = engine.align(
            script: script,
            recognisedText: update.text,
            previous: alignmentState,
            isFinal: update.isFinal
        )
        alignmentState = result.state
        matchedRange = result.matchedRange
        searchMode = result.searchMode
        candidateScore = result.candidateScore

        guard let tokenIndex = result.tokenIndex, !automaticFollowingSuspended else { return }
        requestScroll(towards: tokenIndex)
    }

    private func requestScroll(towards tokenIndex: Int) {
        guard let lastScrollTarget else {
            scrollTarget = tokenIndex
            self.lastScrollTarget = tokenIndex
            return
        }
        guard tokenIndex - lastScrollTarget >= ScrollConfiguration.minimumTokenAdvance else { return }

        pendingScrollDestination = max(pendingScrollDestination ?? tokenIndex, tokenIndex)
        guard scrollCatchUpTask == nil else { return }
        scrollCatchUpTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled,
                  !self.automaticFollowingSuspended,
                  let destination = self.pendingScrollDestination,
                  let current = self.lastScrollTarget,
                  destination - current >= ScrollConfiguration.minimumTokenAdvance {
                let next = min(destination, current + ScrollConfiguration.maximumAnimatedAdvance)
                self.scrollTarget = next
                self.lastScrollTarget = next
                if next >= destination {
                    self.pendingScrollDestination = nil
                    break
                }
                try? await Task.sleep(for: ScrollConfiguration.catchUpInterval)
            }
            self.scrollCatchUpTask = nil
        }
    }
}
