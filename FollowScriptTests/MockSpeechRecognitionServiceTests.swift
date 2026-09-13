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
}
