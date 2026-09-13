@preconcurrency import AVFoundation

final class SpeechAudioBufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    let outputFormat: AVAudioFormat

    init(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw SpeechRecognitionError.audioConversionFailed
        }
        self.converter = converter
        self.outputFormat = outputFormat
    }

    func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let sampleRateRatio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let estimatedFrames = ceil(Double(inputBuffer.frameLength) * sampleRateRatio)
        let capacity = AVAudioFrameCount(max(1, estimatedFrames + 32))
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            throw SpeechRecognitionError.audioConversionFailed
        }

        var conversionError: NSError?
        let inputProvider = ConverterInputProvider(buffer: inputBuffer)
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.next(status: inputStatus)
        }

        guard status != .error, conversionError == nil else {
            throw conversionError ?? SpeechRecognitionError.audioConversionFailed
        }
        return outputBuffer
    }
}

private final class ConverterInputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var hasProvidedBuffer = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    // AVAudioConverter invokes this provider synchronously and serially during one conversion.
    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard !hasProvidedBuffer else {
            status.pointee = .noDataNow
            return nil
        }
        hasProvidedBuffer = true
        status.pointee = .haveData
        return buffer
    }
}
