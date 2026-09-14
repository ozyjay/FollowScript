import Foundation
import Combine

enum MicrophoneLevelQuality: String, Equatable {
    case quiet = "Quiet"
    case good = "Good"
    case loud = "Too loud"

    init(level: Double, quietThreshold: Double = 0.22) {
        if level < quietThreshold { self = .quiet }
        else if level > 0.88 { self = .loud }
        else { self = .good }
    }
}

enum RecognitionActivity: String, Equatable {
    case paused = "Paused"
    case listening = "Listening"
    case hearingSpeech = "Hearing speech"
    case noWordsRecognised = "Speech heard, no words yet"
}

enum FollowingPresentationState: String, Equatable {
    case paused = "Following paused"
    case finding = "Finding your place"
    case following = "Following"
    case unsure = "Unsure — keep speaking"
    case searching = "Searching ahead"
}

enum MicrophoneCheckPhase: Equatable {
    case idle
    case measuringRoom
    case reading
    case complete
}

struct MicrophoneCheckResult: Equatable {
    let microphoneLevelOK: Bool
    let recognitionOK: Bool
    let alignmentOK: Bool
    let guidance: String
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
    @Published private(set) var recognitionActivity: RecognitionActivity = .paused
    @Published private(set) var microphoneGain = MicrophoneGainState(isAdjustable: false, value: 1)
    @Published private(set) var microphoneCheckPhase: MicrophoneCheckPhase = .idle
    @Published private(set) var microphoneCheckResult: MicrophoneCheckResult?

    private let service: any SpeechRecognitionService
    private let engine: ScriptAlignmentEngine
    private let microphoneCheckRoomDuration: Duration
    private let microphoneCheckReadingDuration: Duration
    private var recognitionTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var followResumeTask: Task<Void, Never>?
    private var audioLevelTask: Task<Void, Never>?
    private var scrollCatchUpTask: Task<Void, Never>?
    private var pendingScrollDestination: Int?
    private var lastScrollTarget: Int?
    private var wantsRecognition = false
    private var quietThreshold = 0.22
    private var speechWithoutRecognitionStartedAt: Date?
    private var lastRecognitionAt: Date?
    private var microphoneCheckTask: Task<Void, Never>?
    private var microphoneCheckLevels: [Double] = []
    private var microphoneCheckPeak = 0.0
    private var microphoneCheckInitialText = ""
    private var microphoneCheckSawAlignment = false

    init(
        scriptText: String,
        ignoresSquareBracketedText: Bool = true,
        service: (any SpeechRecognitionService)? = nil,
        engine: ScriptAlignmentEngine = ScriptAlignmentEngine(),
        microphoneCheckRoomDuration: Duration = .seconds(2),
        microphoneCheckReadingDuration: Duration = .seconds(8)
    ) {
        script = ScriptDocument(
            text: ScriptTextProcessor.prepare(
                scriptText,
                ignoringSquareBracketedText: ignoresSquareBracketedText
            )
        )
        self.service = service ?? SpeechServiceFactory.live()
        self.engine = engine
        self.microphoneCheckRoomDuration = microphoneCheckRoomDuration
        self.microphoneCheckReadingDuration = microphoneCheckReadingDuration
    }

    var currentTokenIndex: Int? { alignmentState.estimatedTokenIndex }
    var committedTokenIndex: Int? { alignmentState.committedTokenIndex }
    var confidence: Double { alignmentState.confidence }
    var trackingState: AlignmentTrackingState { alignmentState.trackingState }
    var microphoneLevelQuality: MicrophoneLevelQuality { .init(level: audioLevel, quietThreshold: quietThreshold) }
    var followingPresentationState: FollowingPresentationState {
        guard isListening else { return .paused }
        if alignmentState.committedTokenIndex == nil { return .finding }
        switch trackingState {
        case .tracking: return .following
        case .uncertain: return .unsure
        case .reacquiring: return .searching
        }
    }
    var calibrationPrompt: String {
        let start = alignmentState.committedTokenIndex ?? 0
        let end = min(script.tokens.count, start + 10)
        return script.tokens[start..<end].map(\.original).joined(separator: " ")
    }

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
        recognitionActivity = .paused
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
        microphoneCheckTask?.cancel()
        microphoneCheckTask = nil
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

    func setMicrophoneGain(_ value: Double) {
        do {
            try service.setInputGain(value)
            microphoneGain = .init(isAdjustable: microphoneGain.isAdjustable, value: min(1, max(0, value)))
        } catch {
            audioInputWarning = "This microphone could not apply the requested gain."
        }
    }

    func beginMicrophoneCheck() {
        microphoneCheckTask?.cancel()
        microphoneCheckLevels = []
        microphoneCheckPeak = 0
        microphoneCheckInitialText = recognisedText
        microphoneCheckSawAlignment = false
        microphoneCheckResult = nil
        microphoneCheckPhase = .measuringRoom
        let roomDuration = microphoneCheckRoomDuration
        let readingDuration = microphoneCheckReadingDuration
        microphoneCheckTask = Task { [weak self] in
            try? await Task.sleep(for: roomDuration)
            guard !Task.isCancelled, let self else { return }
            self.microphoneCheckPhase = .reading
            try? await Task.sleep(for: readingDuration)
            guard !Task.isCancelled else { return }
            self.finishMicrophoneCheck()
        }
    }

    func cancelMicrophoneCheck() {
        microphoneCheckTask?.cancel()
        microphoneCheckTask = nil
        microphoneCheckPhase = .idle
    }

    func finishMicrophoneCheck() {
        microphoneCheckTask?.cancel()
        microphoneCheckTask = nil
        let roomLevel = microphoneCheckLevels.isEmpty
            ? 0
            : microphoneCheckLevels.reduce(0, +) / Double(microphoneCheckLevels.count)
        quietThreshold = min(0.26, max(0.10, roomLevel + 0.08))
        let microphoneOK = microphoneCheckPeak >= quietThreshold
        let recognitionOK = recognisedText != microphoneCheckInitialText && !recognisedText.isEmpty
        let alignmentOK = microphoneCheckSawAlignment
        let guidance: String
        if !microphoneOK {
            guidance = "Move closer to the microphone or check the selected input."
        } else if !recognitionOK {
            guidance = "Audio is arriving, but no words were recognised. Reduce background noise and try again."
        } else if !alignmentOK {
            guidance = "Speech was recognised, but the phrase did not match this part of the script."
        } else {
            guidance = "Microphone, recognition and following are ready."
        }
        microphoneCheckResult = .init(
            microphoneLevelOK: microphoneOK,
            recognitionOK: recognitionOK,
            alignmentOK: alignmentOK,
            guidance: guidance
        )
        microphoneCheckPhase = .complete
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
        if let committedTokenIndex {
            scrollTarget = committedTokenIndex
            lastScrollTarget = committedTokenIndex
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
                    guard let self else { break }
                    self.audioLevel = level
                    self.consumeMicrophoneLevelForCheck(level)
                    self.updateRecognitionActivity(for: level)
                case .inputChanged(let input):
                    guard let self else { break }
                    let lostExternalInput = self.audioInput?.isExternal == true && !input.isExternal
                    self.audioInput = input
                    self.audioInputWarning = lostExternalInput
                        ? "External microphone disconnected. Now using \(input.name)."
                        : nil
                case .gainChanged(let gain):
                    self?.microphoneGain = gain
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
        lastRecognitionAt = Date()
        speechWithoutRecognitionStartedAt = nil
        recognitionActivity = .hearingSpeech
        let observations = [AlignmentObservation(text: update.text, confidence: update.confidence)]
            + update.alternatives.map { AlignmentObservation(text: $0) }
        let result = engine.align(
            script: script,
            observations: observations,
            previous: alignmentState,
            isFinal: update.isFinal,
            observationTime: update.audioTimeRange?.upperBound ?? update.timestamp.timeIntervalSinceReferenceDate
        )
        alignmentState = result.state
        matchedRange = result.matchedRange
        searchMode = result.searchMode
        candidateScore = result.candidateScore
        if microphoneCheckPhase == .reading, result.matchedRange != nil {
            microphoneCheckSawAlignment = true
        }

        guard let tokenIndex = result.committedTokenIndex, !automaticFollowingSuspended else { return }
        requestScroll(towards: tokenIndex)
    }

    private func consumeMicrophoneLevelForCheck(_ level: Double) {
        if microphoneCheckPhase == .measuringRoom {
            microphoneCheckLevels.append(level)
        } else if microphoneCheckPhase == .reading {
            microphoneCheckPeak = max(microphoneCheckPeak, level)
        }
    }

    private func updateRecognitionActivity(for level: Double) {
        guard isListening else { recognitionActivity = .paused; return }
        guard level >= quietThreshold else {
            speechWithoutRecognitionStartedAt = nil
            recognitionActivity = .listening
            return
        }
        if lastRecognitionAt.map({ Date().timeIntervalSince($0) < 1.5 }) == true {
            recognitionActivity = .hearingSpeech
            return
        }
        let started = speechWithoutRecognitionStartedAt ?? Date()
        speechWithoutRecognitionStartedAt = started
        recognitionActivity = Date().timeIntervalSince(started) >= 1.5 ? .noWordsRecognised : .hearingSpeech
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
