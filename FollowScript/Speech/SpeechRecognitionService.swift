import Foundation

enum SpeechAuthorisationStatus: Equatable, Sendable {
    case notDetermined
    case authorised
    case denied
    case restricted
}

struct SpeechRecognitionUpdate: Equatable, Sendable {
    let text: String
    let isFinal: Bool
    let timestamp: Date
    let confidence: Double?
}

enum AudioInputEvent: Equatable, Sendable {
    case level(Double)
    case recordingFailed(String)
}

enum SpeechRecognitionError: LocalizedError, Equatable {
    case permissionDenied
    case unavailable
    case onDeviceRecognitionUnavailable
    case audioInputUnavailable
    case audioConversionFailed
    case interrupted

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Microphone and speech recognition access are required to follow your speech."
        case .unavailable:
            "Speech recognition is not available right now."
        case .onDeviceRecognitionUnavailable:
            "On-device speech recognition is not available for the selected language."
        case .audioInputUnavailable:
            "FollowScript could not access the microphone."
        case .audioConversionFailed:
            "FollowScript could not prepare the microphone audio for speech recognition."
        case .interrupted:
            "Speech recognition was interrupted. You can resume when ready."
        }
    }
}

@MainActor
protocol SpeechRecognitionService: AnyObject {
    func requestAuthorisation() async -> SpeechAuthorisationStatus
    func start() async throws -> AsyncThrowingStream<SpeechRecognitionUpdate, Error>
    func stop() async
    func audioInputEvents() -> AsyncStream<AudioInputEvent>
    func startRecording() throws
    func stopRecording() throws -> URL?
}
