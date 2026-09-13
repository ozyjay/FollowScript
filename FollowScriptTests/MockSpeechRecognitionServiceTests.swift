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
}

@MainActor
private final class SlowStoppingSpeechRecognitionService: SpeechRecognitionService {
    private var continuation: AsyncThrowingStream<SpeechRecognitionUpdate, Error>.Continuation?
    private(set) var startCount = 0
    private(set) var startedDuringStop = false
    private var stopInProgress = false

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
}
