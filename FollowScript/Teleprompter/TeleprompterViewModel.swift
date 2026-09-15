import Foundation
import Combine
import os

@MainActor
private final class TrackingLatencyInstrument {
    private struct PendingUpdate {
        let sequence: UInt64
        let signpostID: OSSignpostID
        let arrivalNanoseconds: UInt64
        let alignmentCompletedNanoseconds: UInt64
    }

    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "FollowScript",
        category: "TrackingLatency"
    )
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FollowScript",
        category: "TrackingLatency"
    )
    private static let summaryInterval = 20
    private let isEnabled: Bool

    private var nextSequence: UInt64 = 0
    private var pending: PendingUpdate?
    private var completedCount = 0
    private var alignmentTotalMilliseconds = 0.0
    private var uiCommitTotalMilliseconds = 0.0
    private var totalMaximumMilliseconds = 0.0

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func beginRecognitionUpdate(characterCount: Int, isFinal: Bool) -> (sequence: UInt64, signpostID: OSSignpostID, arrival: UInt64) {
        guard isEnabled else { return (0, .exclusive, 0) }
        closeSupersededUpdateIfNeeded()
        nextSequence &+= 1
        let signpostID = OSSignpostID(log: Self.log)
        let arrival = DispatchTime.now().uptimeNanoseconds
        os_signpost(
            .event,
            log: Self.log,
            name: "Recognition Result Arrival",
            signpostID: signpostID,
            "sequence=%llu characters=%d final=%{public}d",
            nextSequence,
            characterCount,
            isFinal
        )
        os_signpost(.begin, log: Self.log, name: "Tracking Total", signpostID: signpostID, "sequence=%llu", nextSequence)
        os_signpost(.begin, log: Self.log, name: "Alignment", signpostID: signpostID, "sequence=%llu", nextSequence)
        return (nextSequence, signpostID, arrival)
    }

    func alignmentCompleted(sequence: UInt64, signpostID: OSSignpostID, arrival: UInt64) {
        guard isEnabled else { return }
        let completed = DispatchTime.now().uptimeNanoseconds
        let alignmentMilliseconds = milliseconds(from: arrival, to: completed)
        os_signpost(
            .end,
            log: Self.log,
            name: "Alignment",
            signpostID: signpostID,
            "sequence=%llu duration_ms=%.3f",
            sequence,
            alignmentMilliseconds
        )
        os_signpost(.begin, log: Self.log, name: "UI State Commit", signpostID: signpostID, "sequence=%llu", sequence)
        pending = PendingUpdate(
            sequence: sequence,
            signpostID: signpostID,
            arrivalNanoseconds: arrival,
            alignmentCompletedNanoseconds: completed
        )
    }

    func uiStateDidCommit(sequence: UInt64) {
        guard isEnabled else { return }
        guard let pending, pending.sequence == sequence else { return }
        let committed = DispatchTime.now().uptimeNanoseconds
        let alignmentMilliseconds = milliseconds(
            from: pending.arrivalNanoseconds,
            to: pending.alignmentCompletedNanoseconds
        )
        let uiCommitMilliseconds = milliseconds(
            from: pending.alignmentCompletedNanoseconds,
            to: committed
        )
        let totalMilliseconds = milliseconds(from: pending.arrivalNanoseconds, to: committed)
        os_signpost(
            .end,
            log: Self.log,
            name: "UI State Commit",
            signpostID: pending.signpostID,
            "sequence=%llu duration_ms=%.3f",
            sequence,
            uiCommitMilliseconds
        )
        os_signpost(
            .end,
            log: Self.log,
            name: "Tracking Total",
            signpostID: pending.signpostID,
            "sequence=%llu duration_ms=%.3f",
            sequence,
            totalMilliseconds
        )
        self.pending = nil
        recordSummarySample(
            alignmentMilliseconds: alignmentMilliseconds,
            uiCommitMilliseconds: uiCommitMilliseconds,
            totalMilliseconds: totalMilliseconds
        )
    }

    private func closeSupersededUpdateIfNeeded() {
        guard let pending else { return }
        os_signpost(.end, log: Self.log, name: "UI State Commit", signpostID: pending.signpostID, "superseded=1")
        os_signpost(.end, log: Self.log, name: "Tracking Total", signpostID: pending.signpostID, "superseded=1")
        self.pending = nil
    }

    private func recordSummarySample(
        alignmentMilliseconds: Double,
        uiCommitMilliseconds: Double,
        totalMilliseconds: Double
    ) {
        completedCount += 1
        alignmentTotalMilliseconds += alignmentMilliseconds
        uiCommitTotalMilliseconds += uiCommitMilliseconds
        totalMaximumMilliseconds = max(totalMaximumMilliseconds, totalMilliseconds)
        guard completedCount == Self.summaryInterval else { return }
        Self.logger.info(
            "Tracking latency over \(self.completedCount, privacy: .public) committed updates: alignment mean \(self.alignmentTotalMilliseconds / Double(self.completedCount), format: .fixed(precision: 2), privacy: .public) ms, UI commit mean \(self.uiCommitTotalMilliseconds / Double(self.completedCount), format: .fixed(precision: 2), privacy: .public) ms, total mean \((self.alignmentTotalMilliseconds + self.uiCommitTotalMilliseconds) / Double(self.completedCount), format: .fixed(precision: 2), privacy: .public) ms, total max \(self.totalMaximumMilliseconds, format: .fixed(precision: 2), privacy: .public) ms"
        )
        completedCount = 0
        alignmentTotalMilliseconds = 0
        uiCommitTotalMilliseconds = 0
        totalMaximumMilliseconds = 0
    }

    private func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        Double(end - start) / 1_000_000
    }
}

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
        static let publicationInterval = Duration.milliseconds(16)
        static let catchUpInterval = Duration.milliseconds(220)
    }

    private enum TrackingDiagnosticConfiguration {
        // Mirrors ScriptAlignmentEngine.Configuration.standard.candidateClusterRadius.
        // Diagnostics are intentionally observational and do not feed this value back into alignment.
        static let candidateClusterRadius = 3
    }

    private static let decisionLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FollowScript",
        category: "TrackingDecision"
    )

    let script: ScriptDocument
    let mode: PresentationMode
    let videoCapture = VideoCaptureCoordinator()
    private var project: PresentationProject?
    private var takeID: UUID?
    private var recordingStartedAt: Date?
    private var isFinishingTake = false
    @Published private(set) var alignmentState = AlignmentState.initial
    @Published private(set) var recognisedText = ""
    @Published private(set) var matchedRange: ClosedRange<Int>?
    @Published private(set) var isCurrentMatchPartial = false
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
    private let logsTimestampedTrackingInformation: Bool
    private var recognitionTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var followResumeTask: Task<Void, Never>?
    private var audioLevelTask: Task<Void, Never>?
    private var scrollCatchUpTask: Task<Void, Never>?
    private var trackingUICommitTask: Task<Void, Never>?
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
    private let trackingLatency: TrackingLatencyInstrument
    private var previousRecognisedText = ""

    init(
        scriptText: String,
        mode: PresentationMode = .teleprompter,
        project: PresentationProject? = nil,
        ignoresSquareBracketedText: Bool = true,
        removesExtraWhitespace: Bool = true,
        logsTimestampedTrackingInformation: Bool = false,
        service: (any SpeechRecognitionService)? = nil,
        engine: ScriptAlignmentEngine = ScriptAlignmentEngine(),
        microphoneCheckRoomDuration: Duration = .seconds(2),
        microphoneCheckReadingDuration: Duration = .seconds(8)
    ) {
        script = ScriptDocument(
            text: ScriptTextProcessor.prepare(
                scriptText,
                ignoringSquareBracketedText: ignoresSquareBracketedText,
                removingExtraWhitespace: removesExtraWhitespace
            )
        )
        self.mode = mode
        self.project = project
        self.service = service ?? SpeechServiceFactory.live()
        self.engine = engine
        self.microphoneCheckRoomDuration = microphoneCheckRoomDuration
        self.microphoneCheckReadingDuration = microphoneCheckReadingDuration
        self.logsTimestampedTrackingInformation = logsTimestampedTrackingInformation
        trackingLatency = TrackingLatencyInstrument(isEnabled: logsTimestampedTrackingInformation)
    }

    var currentTokenIndex: Int? { alignmentState.estimatedTokenIndex }
    /// Presentation-only cue for the next script token to speak.
    /// Alignment and automatic scrolling continue to use their existing positions.
    var nextPromptTokenIndex: Int? {
        guard let currentTokenIndex else { return nil }
        let nextIndex = currentTokenIndex + 1
        return script.tokens.indices.contains(nextIndex) ? nextIndex : nil
    }
    /// Last token safe to present as spoken, retaining one unconfirmed token behind the estimate.
    var spokenThroughTokenIndex: Int? {
        guard let currentTokenIndex, currentTokenIndex >= 2 else { return nil }
        return currentTokenIndex - 2
    }
    var committedTokenIndex: Int? { alignmentState.committedTokenIndex }
    var partialMatchedRange: ClosedRange<Int>? { isCurrentMatchPartial ? matchedRange : nil }
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
        trackingUICommitTask?.cancel()
        trackingUICommitTask = nil
        audioLevelTask?.cancel()
        audioLevelTask = nil
        microphoneCheckTask?.cancel()
        microphoneCheckTask = nil
        if !isRecording && !isFinishingTake { videoCapture.shutdown() }
    }

    func prepareVideo() async {
        do { try await videoCapture.prepare() }
        catch { recordingErrorMessage = error.localizedDescription }
    }

    func toggleRecording() async {
        guard mode != .teleprompter else { return }
        if isRecording {
            await finishTake()
            return
        }
        do {
            if mode == .audiovisual && !videoCapture.isReady { try await videoCapture.prepare() }
            if project == nil { project = try PresentationProjectStore.createProject(script: script.text) }
            try service.startRecording()
            if mode == .audiovisual {
                do { try videoCapture.start() }
                catch { _ = try? service.stopRecording(); throw error }
            }
            takeID = UUID()
            recordingStartedAt = Date()
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
            lowConfidenceUpdates: 0,
            hypotheses: [AlignmentHypothesis(tokenIndex: tokenIndex, score: 1)]
        )
        matchedRange = tokenIndex...tokenIndex
        isCurrentMatchPartial = false
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
        isFinishingTake = true
        Task { await finishTake() }
    }

    private func finishTake() async {
        guard isRecording else { return }
        isRecording = false
        isFinishingTake = true
        defer {
            isFinishingTake = false
            if !wantsRecognition { videoCapture.shutdown() }
        }
        let audioURL: URL?
        do { audioURL = try service.stopRecording() }
        catch { recordingErrorMessage = error.localizedDescription; return }
        var exportedAudioURL: URL?
        do {
            let videoURL = mode == .audiovisual ? try await videoCapture.stop() : nil
            guard let audioURL, let project,
                  let takeID, let recordingStartedAt else { throw VideoCaptureError.unavailable }
            let source: URL
            let mediaExtension: String
            var conversionError: Error?
            if let videoURL {
                source = try await VideoTakeMuxer.combine(video: videoURL, audio: audioURL)
                try? FileManager.default.removeItem(at: videoURL)
                try? FileManager.default.removeItem(at: audioURL)
                mediaExtension = "mov"
            } else {
                do {
                    source = try await AudioTakeExporter.exportAAC(from: audioURL)
                    exportedAudioURL = source
                    mediaExtension = "m4a"
                } catch {
                    source = audioURL
                    mediaExtension = "caf"
                    conversionError = error
                }
            }
            let endedAt = Date()
            let take = PresentationTake(id: takeID, projectID: project.id, mode: mode,
                                        startedAt: recordingStartedAt, endedAt: endedAt,
                                        mediaFilename: "\(takeID).\(mediaExtension)",
                                        duration: endedAt.timeIntervalSince(recordingStartedAt))
            latestRecordingURL = try PresentationProjectStore.saveTake(take, source: source)
            if mediaExtension == "m4a" {
                do {
                    try FileManager.default.removeItem(at: audioURL)
                } catch {
                    recordingErrorMessage = "The AAC take was saved, but its original CAF audio could not be removed. \(error.localizedDescription)"
                }
            }
            if let conversionError {
                recordingErrorMessage = "AAC conversion failed, so this take was saved as its original CAF audio. \(conversionError.localizedDescription)"
            }
        } catch {
            var message = error.localizedDescription
            if let exportedAudioURL, FileManager.default.fileExists(atPath: exportedAudioURL.path) {
                do { try FileManager.default.removeItem(at: exportedAudioURL) }
                catch { message += " The unfinished AAC file could not be removed: \(error.localizedDescription)" }
            }
            recordingErrorMessage = message
        }
        takeID = nil
        recordingStartedAt = nil
    }

    private func consume(_ update: SpeechRecognitionUpdate) {
        let measurement = trackingLatency.beginRecognitionUpdate(
            characterCount: update.text.count,
            isFinal: update.isFinal
        )
        recognisedText = update.text
        lastRecognitionAt = Date()
        speechWithoutRecognitionStartedAt = nil
        recognitionActivity = .hearingSpeech
        let observations = [AlignmentObservation(text: update.text, confidence: update.confidence)]
            + update.alternatives.map { AlignmentObservation(text: $0) }
        let previousState = alignmentState
        let previousSearchMode = searchMode
        let result = engine.align(
            script: script,
            observations: observations,
            previous: previousState,
            isFinal: update.isFinal,
            observationTime: update.audioTimeRange?.upperBound ?? update.timestamp.timeIntervalSinceReferenceDate
        )
        trackingLatency.alignmentCompleted(
            sequence: measurement.sequence,
            signpostID: measurement.signpostID,
            arrival: measurement.arrival
        )
        traceTrackingDecision(
            update: update,
            previousText: previousRecognisedText,
            previousState: previousState,
            previousSearchMode: previousSearchMode,
            result: result
        )
        previousRecognisedText = update.text
        alignmentState = result.state
        matchedRange = result.matchedRange
        isCurrentMatchPartial = !update.isFinal && result.matchedRange != nil
        searchMode = result.searchMode
        candidateScore = result.candidateScore
        if microphoneCheckPhase == .reading, result.matchedRange != nil {
            microphoneCheckSawAlignment = true
        }

        if let tokenIndex = result.committedTokenIndex, !automaticFollowingSuspended {
            requestScroll(towards: tokenIndex)
        }
        scheduleTrackingUICommit(sequence: measurement.sequence)
    }

    private func scheduleTrackingUICommit(sequence: UInt64) {
        trackingUICommitTask?.cancel()
        trackingUICommitTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.trackingLatency.uiStateDidCommit(sequence: sequence)
            self?.trackingUICommitTask = nil
        }
    }

    private func traceTrackingDecision(
        update: SpeechRecognitionUpdate,
        previousText: String,
        previousState: AlignmentState,
        previousSearchMode: AlignmentResult.SearchMode,
        result: AlignmentResult
    ) {
        guard logsTimestampedTrackingInformation else { return }

        let previousPosition = previousState.committedTokenIndex
        let committed = result.committedTokenIndex
        let rawBest = result.decisionTrace.candidates.first
        let selectedCandidate = diagnosticSelectedCandidate(for: result, rawBest: rawBest)
        let continuityPreferenceApplied = rawBest?.tokenIndex != nil
            && selectedCandidate?.tokenIndex != nil
            && rawBest?.tokenIndex != selectedCandidate?.tokenIndex
            && result.searchMode == .local
        let positionChanged = committed != previousPosition
        let trackingStateChanged = result.trackingState != previousState.trackingState
        let searchModeChanged = result.searchMode != previousSearchMode
        let significantHold = result.decisionTrace.decision == .hold
            && result.decisionTrace.reason != .awaitingMorePartialTokens
            && result.decisionTrace.reason != .emptyRecognition

        guard positionChanged || trackingStateChanged || searchModeChanged
                || significantHold || continuityPreferenceApplied else { return }

        let movement = committed.map { $0 - (previousPosition ?? $0) } ?? 0
        let direction = movement > 0 ? "forward" : movement < 0 ? "backward" : "anchor"
        let candidates = result.decisionTrace.candidates.prefix(3).map {
            "\($0.tokenIndex):\(String(format: "%.3f", $0.score))"
        }.joined(separator: ",")
        let rawBestDescription = rawBest.map {
            "\($0.tokenIndex):\(String(format: "%.3f", $0.score))"
        } ?? "none"
        let selectedMatchDescription = selectedCandidate.map {
            "\($0.tokenIndex):\(String(format: "%.3f", $0.score))"
        } ?? "none"
        let clusterDescription = selectedCandidate.map { candidate -> String in
            let radius = TrackingDiagnosticConfiguration.candidateClusterRadius
            return "\(max(0, candidate.tokenIndex - radius))...\(candidate.tokenIndex + radius)"
        } ?? "none"
        let distantCompetitor = selectedCandidate.flatMap { candidate in
            result.decisionTrace.candidates.first {
                abs($0.tokenIndex - candidate.tokenIndex) > TrackingDiagnosticConfiguration.candidateClusterRadius
            }
        }
        let distantCompetitorDescription: String
        if let distantCompetitor {
            distantCompetitorDescription = "\(distantCompetitor.tokenIndex):\(String(format: "%.3f", distantCompetitor.score))"
        } else if result.decisionTrace.scoreMargin != nil {
            distantCompetitorDescription = "outsideTop3"
        } else {
            distantCompetitorDescription = "none"
        }
        let margin = result.decisionTrace.scoreMargin.map { String(format: "%.3f", $0) } ?? "n/a"
        let adjustment = diagnosticCommitAdjustment(
            update: update,
            rawBest: rawBest,
            selectedCandidate: selectedCandidate,
            committed: committed,
            decision: result.decisionTrace.decision
        )
        let stateTransition = previousState.trackingState == result.trackingState
            ? "none"
            : "\(previousState.trackingState.rawValue)->\(result.trackingState.rawValue)"
        let modeTransition = previousSearchMode == result.searchMode
            ? "none"
            : "\(previousSearchMode.rawValue)->\(result.searchMode.rawValue)"
        let event: String
        if previousState.trackingState != .reacquiring, result.trackingState == .reacquiring {
            event = "reacquisitionEnter"
        } else if previousState.trackingState == .reacquiring, result.trackingState != .reacquiring {
            event = "reacquisitionExit"
        } else if result.decisionTrace.decision == .hold {
            event = "hold"
        } else if continuityPreferenceApplied {
            event = "continuityPreference"
        } else {
            event = "advance"
        }

        Self.decisionLogger.info(
            "event=\(event, privacy: .public) recognised=\(update.text, privacy: .public) previous_recognised=\(previousText, privacy: .public) delta=\(self.incrementalText(from: previousText, to: update.text), privacy: .public) current=\(previousPosition.map(String.init) ?? "none", privacy: .public) raw_best=\(rawBestDescription, privacy: .public) selected_match=\(selectedMatchDescription, privacy: .public) cluster=\(clusterDescription, privacy: .public) distant_competitor=\(distantCompetitorDescription, privacy: .public) cluster_margin=\(margin, privacy: .public) committed=\(committed.map(String.init) ?? "none", privacy: .public) adjustment=\(adjustment, privacy: .public) movement=\(movement, privacy: .public) direction=\(direction, privacy: .public) mode=\(result.searchMode.rawValue, privacy: .public) mode_transition=\(modeTransition, privacy: .public) tracking=\(result.trackingState.rawValue, privacy: .public) state_transition=\(stateTransition, privacy: .public) candidates=\(candidates, privacy: .public) recognition=\(update.isFinal ? "final" : "partial", privacy: .public) decision=\(result.decisionTrace.decision.rawValue, privacy: .public) reason=\(result.decisionTrace.reason.rawValue, privacy: .public)"
        )
    }

    private func diagnosticSelectedCandidate(
        for result: AlignmentResult,
        rawBest: AlignmentDecisionTrace.Candidate?
    ) -> AlignmentDecisionTrace.Candidate? {
        if let endpoint = result.matchedRange?.upperBound {
            return result.decisionTrace.candidates.first { $0.tokenIndex == endpoint }
                ?? .init(tokenIndex: endpoint, score: result.candidateScore)
        }
        if let candidate = result.decisionTrace.candidates.first(where: {
            abs($0.score - result.candidateScore) < 0.000_5
        }) {
            return candidate
        }
        return rawBest
    }

    private func diagnosticCommitAdjustment(
        update: SpeechRecognitionUpdate,
        rawBest: AlignmentDecisionTrace.Candidate?,
        selectedCandidate: AlignmentDecisionTrace.Candidate?,
        committed: Int?,
        decision: AlignmentDecisionTrace.Decision
    ) -> String {
        var adjustments: [String] = []
        if decision == .hold {
            adjustments.append("hold")
        }
        if let rawBest, let selectedCandidate, rawBest.tokenIndex != selectedCandidate.tokenIndex {
            adjustments.append("continuityPreference")
        }
        if let selectedCandidate, let committed, selectedCandidate.tokenIndex != committed {
            if !update.isFinal && selectedCandidate.tokenIndex == committed + 1 {
                adjustments.append("singleWordPartialLag")
            } else {
                adjustments.append("commitHoldback")
            }
        }
        return adjustments.isEmpty ? "none" : adjustments.joined(separator: "+")
    }

    private func incrementalText(from previous: String, to current: String) -> String {
        guard !previous.isEmpty, current.hasPrefix(previous) else { return current }
        return String(current.dropFirst(previous.count)).trimmingCharacters(in: .whitespacesAndNewlines)
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
        if let lastScrollTarget,
           tokenIndex - lastScrollTarget < ScrollConfiguration.minimumTokenAdvance {
            return
        }

        pendingScrollDestination = max(pendingScrollDestination ?? tokenIndex, tokenIndex)
        guard scrollCatchUpTask == nil else { return }
        scrollCatchUpTask = Task { [weak self] in
            guard let self else { return }
            // Recognition can commit several adjacent updates inside one display frame.
            // Wait one frame interval so only the newest scroll destination is published.
            try? await Task.sleep(for: ScrollConfiguration.publicationInterval)
            while !Task.isCancelled, !self.automaticFollowingSuspended,
                  let destination = self.pendingScrollDestination {
                guard let current = self.lastScrollTarget else {
                    self.scrollTarget = destination
                    self.lastScrollTarget = destination
                    self.pendingScrollDestination = nil
                    break
                }
                guard destination - current >= ScrollConfiguration.minimumTokenAdvance else {
                    self.pendingScrollDestination = nil
                    break
                }
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
