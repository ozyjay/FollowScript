import AVFoundation
import XCTest
@testable import FollowScript

final class SpeechAudioBufferConverterTests: XCTestCase {
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
