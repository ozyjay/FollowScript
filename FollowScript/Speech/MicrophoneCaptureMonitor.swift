import AVFoundation
import Foundation

enum AudioRecordingError: LocalizedError {
    case microphoneNotRunning
    case couldNotCreateFolder

    var errorDescription: String? {
        switch self {
        case .microphoneNotRunning:
            "Start listening before recording audio."
        case .couldNotCreateFolder:
            "FollowScript could not create its local Recordings folder."
        }
    }
}

/// Receives buffers on the audio tap's real-time thread and serialises metering and file writes.
final class MicrophoneCaptureMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var eventContinuations: [UUID: AsyncStream<AudioInputEvent>.Continuation] = [:]
    private var lastLevelEmission = ContinuousClock.now

    func events() -> AsyncStream<AudioInputEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AudioInputEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        lock.withLock { eventContinuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.eventContinuations[id] = nil }
        }
        return stream
    }

    func reportInput(_ input: AudioInputDescriptor) {
        lock.withLock {
            for continuation in eventContinuations.values {
                continuation.yield(.inputChanged(input))
            }
        }
    }

    func reportGain(_ gain: MicrophoneGainState) {
        lock.withLock {
            for continuation in eventContinuations.values {
                continuation.yield(.gainChanged(gain))
            }
        }
    }

    func startRecording(format: AVAudioFormat) throws {
        let folder = try Self.recordingsFolder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let uniqueSuffix = UUID().uuidString.prefix(8)
        let url = folder.appendingPathComponent(
            "FollowScript_\(formatter.string(from: Date()))_\(uniqueSuffix).caf"
        )
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        lock.withLock {
            audioFile = file
            recordingURL = url
        }
    }

    func stopRecording() -> URL? {
        lock.withLock {
            audioFile = nil
            defer { recordingURL = nil }
            return recordingURL
        }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let now = ContinuousClock.now
        let shouldEmit = lock.withLock { () -> Bool in
            if now - lastLevelEmission >= .milliseconds(80) {
                lastLevelEmission = now
                return true
            }
            return false
        }

        let level = shouldEmit ? Self.normalisedLevel(in: buffer) : nil
        lock.withLock {
            if let audioFile {
                do {
                    try audioFile.write(from: buffer)
                } catch {
                    self.audioFile = nil
                    for continuation in eventContinuations.values {
                        continuation.yield(.recordingFailed(error.localizedDescription))
                    }
                }
            }
            if let level {
                for continuation in eventContinuations.values {
                    continuation.yield(.level(level))
                }
            }
        }
    }

    static func normalisedLevel(in buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let frameCount = Int(buffer.frameLength)
        var sumOfSquares = 0.0
        for channelIndex in 0..<Int(buffer.format.channelCount) {
            let channel = channels[channelIndex]
            for frame in 0..<frameCount {
                let sample = Double(channel[frame])
                sumOfSquares += sample * sample
            }
        }
        let sampleCount = Double(frameCount * Int(buffer.format.channelCount))
        let rms = sqrt(sumOfSquares / sampleCount)
        let decibels = 20 * log10(max(rms, 0.000_001))
        return min(max((decibels + 60) / 48, 0), 1)
    }

    private static func recordingsFolder() throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AudioRecordingError.couldNotCreateFolder
        }
        let folder = documents.appendingPathComponent("Recordings", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            throw AudioRecordingError.couldNotCreateFolder
        }
    }
}
