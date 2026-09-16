import Foundation

@MainActor
final class MockSpeechRecognitionService: SpeechRecognitionService {
    private var continuation: AsyncThrowingStream<SpeechRecognitionUpdate, Error>.Continuation?
    private var eventContinuation: AsyncStream<AudioInputEvent>.Continuation?
    private(set) var isRecording = false
    var recordingURL: URL?
    private(set) var gain = MicrophoneGainState(isAdjustable: false, value: 1)

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

    func audioInputEvents() -> AsyncStream<AudioInputEvent> {
        let (stream, continuation) = AsyncStream<AudioInputEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        eventContinuation = continuation
        return stream
    }

    func setInputGain(_ value: Double) throws {
        guard gain.isAdjustable else { return }
        gain = .init(isAdjustable: true, value: min(1, max(0, value)))
        eventContinuation?.yield(.gainChanged(gain))
    }

    func sendGain(isAdjustable: Bool, value: Double) {
        gain = .init(isAdjustable: isAdjustable, value: value)
        eventContinuation?.yield(.gainChanged(gain))
    }

    func startRecording() throws { isRecording = true }
    func stopRecording() throws -> URL? {
        isRecording = false
        return recordingURL
    }

    func sendAudioLevel(_ level: Double, peak: Double? = nil) {
        eventContinuation?.yield(.level(.init(level: level, peak: peak ?? level)))
    }

    func sendAudioInput(name: String, isExternal: Bool) {
        eventContinuation?.yield(.inputChanged(.init(name: name, isExternal: isExternal)))
    }

    func send(_ text: String, alternatives: [String] = [], isFinal: Bool = false,
              audioTimeRange: Range<TimeInterval>? = nil, confidence: Double? = nil) {
        continuation?.yield(
            SpeechRecognitionUpdate(
                text: text,
                alternatives: alternatives,
                isFinal: isFinal,
                timestamp: Date(),
                audioTimeRange: audioTimeRange,
                confidence: confidence
            )
        )
    }

    func fail(with error: Error) {
        continuation?.finish(throwing: error)
        continuation = nil
    }
}
