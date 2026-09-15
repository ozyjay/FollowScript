import XCTest
import Combine
@testable import FollowScript

@MainActor
final class MockSpeechRecognitionServiceTests: XCTestCase {
    func testMockStreamsDeterministicUpdates() async throws {
        let service = MockSpeechRecognitionService()
        let stream = try await service.start()
        service.send("hello world", isFinal: true, confidence: 0.9)
        await service.stop()

        var received: [SpeechRecognitionUpdate] = []
        for try await update in stream { received.append(update) }
        XCTAssertEqual(received.map(\.text), ["hello world"])
        XCTAssertEqual(received.first?.confidence, 0.9)
    }

    func testMockRecognitionDrivesTeleprompterAlignment() async throws {
        let service = MockSpeechRecognitionService()
        let model = TeleprompterViewModel(
            scriptText: "Welcome to the presentation. Today we share the final result.",
            service: service
        )

        model.start()
        try await Task.sleep(for: .milliseconds(50))
        service.send("today we share the final result", isFinal: true)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.currentTokenIndex, 9)
        XCTAssertNil(model.nextPromptTokenIndex)
        XCTAssertEqual(model.trackingState, .tracking)
        XCTAssertNotNil(model.scrollTarget)
        model.stop()
    }

    func testNextPromptTokenIndexLeadsEstimatedPositionWithoutChangingIt() {
        let model = TeleprompterViewModel(
            scriptText: "One two three",
            service: MockSpeechRecognitionService()
        )

        XCTAssertNil(model.nextPromptTokenIndex)
        XCTAssertNil(model.spokenThroughTokenIndex)

        model.moveFollowing(to: 0)
        XCTAssertEqual(model.currentTokenIndex, 0)
        XCTAssertEqual(model.nextPromptTokenIndex, 1)
        XCTAssertNil(model.spokenThroughTokenIndex)

        model.moveFollowing(to: 1)
        XCTAssertEqual(model.currentTokenIndex, 1)
        XCTAssertEqual(model.nextPromptTokenIndex, 2)
        XCTAssertNil(model.spokenThroughTokenIndex)

        model.moveFollowing(to: 2)
        XCTAssertEqual(model.currentTokenIndex, 2)
        XCTAssertNil(model.nextPromptTokenIndex)
        XCTAssertEqual(model.spokenThroughTokenIndex, 0)
    }

    func testPartialMatchRangeIsExposedOnlyWhileRecognitionIsPartial() async throws {
        let service = MockSpeechRecognitionService()
        let model = TeleprompterViewModel(
            scriptText: "Welcome to the presentation. Today we share the final result.",
            service: service
        )

        model.start()
        try await Task.sleep(for: .milliseconds(50))
        service.send("today we share", isFinal: false)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.partialMatchedRange, 4...6)

        service.send("today we share the final result", isFinal: true)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(model.partialMatchedRange)
        model.stop()
    }

    func testRapidPauseResumeWaitsForPreviousSessionCleanup() async throws {
        let service = SlowStoppingSpeechRecognitionService()
        let model = TeleprompterViewModel(
            scriptText: "A short script for lifecycle testing.",
            service: service
        )

        model.start()
        try await Task.sleep(for: .milliseconds(30))
        model.pause()
        model.resume()
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(service.startedDuringStop)
        XCTAssertEqual(service.startCount, 2)
        model.stop()
    }

    func testAudioLevelUpdatesQuality() async throws {
        let service = MockSpeechRecognitionService()
        let model = TeleprompterViewModel(scriptText: "A short script.", service: service)

        model.start()
        try await Task.sleep(for: .milliseconds(30))
        service.sendAudioLevel(0.5)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(model.audioLevel, 0.5)
        XCTAssertEqual(model.microphoneLevelQuality, .good)
        model.stop()
    }

    func testExternalAudioInputIsVisibleAndDisconnectionWarns() async throws {
        let service = MockSpeechRecognitionService()
        let model = TeleprompterViewModel(scriptText: "A short script.", service: service)

        model.start()
        try await Task.sleep(for: .milliseconds(30))
        service.sendAudioInput(name: "DJI Mic Mini Receiver", isExternal: true)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(
            model.audioInput,
            AudioInputDescriptor(name: "DJI Mic Mini Receiver", isExternal: true)
        )
        XCTAssertNil(model.audioInputWarning)

        service.sendAudioInput(name: "iPhone Microphone", isExternal: false)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(
            model.audioInput,
            AudioInputDescriptor(name: "iPhone Microphone", isExternal: false)
        )
        XCTAssertEqual(
            model.audioInputWarning,
            "External microphone disconnected. Now using iPhone Microphone."
        )
        model.stop()
    }

    func testPausingFinalisesActiveAudioRecording() async throws {
        let service = MockSpeechRecognitionService()
        let project = PresentationProject(id: UUID(), title: "Test", script: "A short script.", createdAt: Date())
        let model = TeleprompterViewModel(
            scriptText: "A short script.", mode: .audio, project: project, service: service
        )

        model.start()
        try await Task.sleep(for: .milliseconds(30))
        await model.toggleRecording()
        XCTAssertTrue(model.isRecording)
        XCTAssertTrue(service.isRecording)

        model.pause()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(model.isRecording)
        XCTAssertFalse(service.isRecording)
        model.stop()
    }

    func testTeleprompterOnlyDoesNotStartRecording() async {
        let service = MockSpeechRecognitionService()
        let model = TeleprompterViewModel(scriptText: "A short script.", mode: .teleprompter, service: service)
        await model.toggleRecording()
        XCTAssertFalse(model.isRecording)
        XCTAssertFalse(service.isRecording)
    }

    func testMicrophoneQualityThresholds() {
        XCTAssertEqual(MicrophoneLevelQuality(level: 0.1), .quiet)
        XCTAssertEqual(MicrophoneLevelQuality(level: 0.5), .good)
        XCTAssertEqual(MicrophoneLevelQuality(level: 0.95), .loud)
    }

    func testSupportedMicrophoneGainCanBeChanged() async throws {
        let service = MockSpeechRecognitionService()
        let model = TeleprompterViewModel(scriptText: "A short script.", service: service)
        model.start()
        try await Task.sleep(for: .milliseconds(30))
        service.sendGain(isAdjustable: true, value: 0.4)
        try await Task.sleep(for: .milliseconds(30))

        model.setMicrophoneGain(0.7)

        XCTAssertTrue(model.microphoneGain.isAdjustable)
        XCTAssertEqual(model.microphoneGain.value, 0.7, accuracy: 0.001)
        model.stop()
    }

    func testTrackingPresentationDistinguishesRecognitionAndFollowing() async throws {
        let service = MockSpeechRecognitionService()
        let model = TeleprompterViewModel(scriptText: "Rare cobalt telescope marks this place.", service: service)
        model.start()
        try await Task.sleep(for: .milliseconds(30))
        service.sendAudioLevel(0.5)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.recognitionActivity, .hearingSpeech)
        XCTAssertEqual(model.followingPresentationState, .finding)

        service.send("rare cobalt telescope marks this place", isFinal: true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.followingPresentationState, .following)
        model.stop()
    }

    func testMicrophoneCheckSeparatesAudioRecognitionAndAlignment() async throws {
        let service = MockSpeechRecognitionService()
        let model = TeleprompterViewModel(
            scriptText: "Rare cobalt telescope marks this place.",
            service: service,
            microphoneCheckRoomDuration: .milliseconds(10),
            microphoneCheckReadingDuration: .seconds(1)
        )
        model.start()
        try await Task.sleep(for: .milliseconds(30))
        model.beginMicrophoneCheck()
        service.sendAudioLevel(0.05)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.microphoneCheckPhase, .reading)

        service.sendAudioLevel(0.6)
        service.send("rare cobalt telescope marks this place", isFinal: true)
        try await Task.sleep(for: .milliseconds(30))
        model.finishMicrophoneCheck()

        XCTAssertEqual(model.microphoneCheckResult?.microphoneLevelOK, true)
        XCTAssertEqual(model.microphoneCheckResult?.recognitionOK, true)
        XCTAssertEqual(model.microphoneCheckResult?.alignmentOK, true)
        XCTAssertEqual(model.microphoneCheckPhase, .complete)
        model.stop()
    }

    func testUserCanMoveFollowingBackwards() async throws {
        let service = MockSpeechRecognitionService()
        let model = TeleprompterViewModel(
            scriptText: "First passage has several words. Middle passage has several words. Final passage has several words.",
            service: service
        )

        model.start()
        try await Task.sleep(for: .milliseconds(30))
        service.send("final passage has several words", isFinal: true)
        try await Task.sleep(for: .milliseconds(30))
        let laterPosition = try XCTUnwrap(model.currentTokenIndex)

        model.moveFollowing(to: 0)

        XCTAssertGreaterThan(laterPosition, 0)
        XCTAssertEqual(model.currentTokenIndex, 0)
        XCTAssertEqual(model.committedTokenIndex, 0)
        XCTAssertEqual(model.alignmentState.hypotheses, [AlignmentHypothesis(tokenIndex: 0, score: 1)])
        XCTAssertEqual(model.scrollTarget, 0)
        XCTAssertEqual(model.recognisedText, "")
        XCTAssertFalse(model.automaticFollowingSuspended)

        try await Task.sleep(for: .milliseconds(50))
        service.send("first passage has several words", isFinal: true)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.currentTokenIndex, 4)
        XCTAssertEqual(model.committedTokenIndex, 4)
        model.stop()
    }

    func testDistantReacquisitionUsesBoundedScrollStep() async throws {
        let service = MockSpeechRecognitionService()
        let script = (0..<150).map { "word\($0)" }.joined(separator: " ")
        let model = TeleprompterViewModel(scriptText: script, service: service)

        model.start()
        try await Task.sleep(for: .milliseconds(30))
        service.send("word10 word11 word12 word13 word14", isFinal: true)
        try await Task.sleep(for: .milliseconds(30))
        let initialScrollTarget = try XCTUnwrap(model.scrollTarget)

        service.send("unrelated noisy material", isFinal: true)
        service.send("still unrelated noise", isFinal: true)
        service.send("word120 word121 word122 word123 word124", isFinal: true)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(model.currentTokenIndex, 124)
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(model.scrollTarget),
            initialScrollTarget + 8
        )
        XCTAssertLessThan(try XCTUnwrap(model.scrollTarget), model.currentTokenIndex ?? 0)
        model.stop()
    }

    func testRapidRecognitionBurstCoalescesScrollPublication() async throws {
        let service = MockSpeechRecognitionService()
        let model = TeleprompterViewModel(
            scriptText: "one two three four five six seven eight",
            service: service
        )
        var publishedTargets: [Int] = []
        let observation = model.$scrollTarget
            .compactMap { $0 }
            .sink { publishedTargets.append($0) }

        model.start()
        try await Task.sleep(for: .milliseconds(30))
        service.send("one two", isFinal: false)
        service.send("one two three four", isFinal: false)
        service.send("one two three four five six", isFinal: false)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(model.committedTokenIndex, 5)
        XCTAssertEqual(publishedTargets, [5])
        withExtendedLifetime(observation) {}
        model.stop()
    }
}

@MainActor
private final class SlowStoppingSpeechRecognitionService: SpeechRecognitionService {
    private var continuation: AsyncThrowingStream<SpeechRecognitionUpdate, Error>.Continuation?
    private(set) var startCount = 0
    private(set) var startedDuringStop = false
    private var stopInProgress = false
    private let eventStream = AsyncStream<AudioInputEvent> { _ in }

    func requestAuthorisation() async -> SpeechAuthorisationStatus { .authorised }

    func start() async throws -> AsyncThrowingStream<SpeechRecognitionUpdate, Error> {
        if stopInProgress { startedDuringStop = true }
        startCount += 1
        let (stream, continuation) = AsyncThrowingStream<SpeechRecognitionUpdate, Error>.makeStream()
        self.continuation = continuation
        return stream
    }

    func stop() async {
        stopInProgress = true
        let sessionContinuation = continuation
        continuation = nil
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                continuation.resume()
            }
        }
        sessionContinuation?.finish()
        stopInProgress = false
    }

    func audioInputEvents() -> AsyncStream<AudioInputEvent> { eventStream }
    func setInputGain(_ value: Double) throws {}
    func startRecording() throws {}
    func stopRecording() throws -> URL? { nil }
}
