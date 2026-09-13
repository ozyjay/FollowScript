import Foundation

@MainActor
final class MockSpeechRecognitionService: SpeechRecognitionService {
    private var continuation: AsyncThrowingStream<SpeechRecognitionUpdate, Error>.Continuation?

    func requestAuthorisation() async -> SpeechAuthorisationStatus { .authorised }

    func start() async throws -> AsyncThrowingStream<SpeechRecognitionUpdate, Error> {
        let (stream, continuation) = AsyncThrowingStream<SpeechRecognitionUpdate, Error>.makeStream()
        self.continuation = continuation
        return stream
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
    }

    func send(_ text: String, isFinal: Bool = false, confidence: Double? = nil) {
        continuation?.yield(
            SpeechRecognitionUpdate(
                text: text,
                isFinal: isFinal,
                timestamp: Date(),
                confidence: confidence
            )
        )
    }

    func fail(with error: Error) {
        continuation?.finish(throwing: error)
        continuation = nil
    }
}
