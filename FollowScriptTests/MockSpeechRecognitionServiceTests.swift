import XCTest
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
        XCTAssertEqual(model.trackingState, .tracking)
        XCTAssertNotNil(model.scrollTarget)
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

    func testPausingFinalisesActiveRecording() async throws {
        let service = MockSpeechRecognitionService()
        service.recordingURL = URL(fileURLWithPath: "/tmp/test-recording.caf")
        let model = TeleprompterViewModel(scriptText: "A short script.", service: service)

        model.start()
        try await Task.sleep(for: .milliseconds(30))
        model.toggleRecording()
        XCTAssertTrue(model.isRecording)

        model.pause()

        XCTAssertFalse(model.isRecording)
        XCTAssertEqual(model.latestRecordingURL, service.recordingURL)
        XCTAssertFalse(service.isRecording)
        model.stop()
    }

    func testMicrophoneQualityThresholds() {
        XCTAssertEqual(MicrophoneLevelQuality(level: 0.1), .quiet)
        XCTAssertEqual(MicrophoneLevelQuality(level: 0.5), .good)
        XCTAssertEqual(MicrophoneLevelQuality(level: 0.95), .loud)
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
        XCTAssertEqual(model.scrollTarget, 0)
        XCTAssertEqual(model.recognisedText, "")
        XCTAssertFalse(model.automaticFollowingSuspended)
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
    func startRecording() throws {}
    func stopRecording() throws -> URL? { nil }
}
