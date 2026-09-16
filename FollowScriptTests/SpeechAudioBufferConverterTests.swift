import AVFoundation
import XCTest
@testable import FollowScript

final class SpeechAudioBufferConverterTests: XCTestCase {
    func testMicrophoneMeasurementSeparatesRMSLevelFromClippingPeak() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100))
        buffer.frameLength = 100
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<100 { samples[index] = 0.05 }
        samples[50] = 0.99

        let measurement = MicrophoneCaptureMonitor.measurement(in: buffer)

        XCTAssertLessThan(measurement.level, 0.88)
        XCTAssertEqual(measurement.peak, 0.99, accuracy: 0.001)
        XCTAssertTrue(measurement.isClipping)
    }

    func testConvertsMicrophoneFloatPCMToSpeechInt16PCM() throws {
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ), let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 480),
           let samples = inputBuffer.floatChannelData?[0] else {
            return XCTFail("Could not create test PCM formats")
        }
        inputBuffer.frameLength = 480
        for index in 0..<Int(inputBuffer.frameLength) {
            samples[index] = sin(Float(index) * 0.05)
        }

        let converter = try SpeechAudioBufferConverter(
            inputFormat: inputFormat,
            outputFormat: outputFormat
        )
        let firstOutput = try converter.convert(inputBuffer)
        let secondOutput = try converter.convert(inputBuffer)

        XCTAssertEqual(firstOutput.format.commonFormat, .pcmFormatInt16)
        XCTAssertEqual(firstOutput.format.sampleRate, 16_000)
        XCTAssertEqual(firstOutput.format.channelCount, 1)
        XCTAssertGreaterThan(firstOutput.frameLength, 0)
        XCTAssertGreaterThan(secondOutput.frameLength, 0)
    }
}
