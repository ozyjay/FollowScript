import AVFoundation
import XCTest
@testable import FollowScript

@MainActor
final class RecordingPlaybackModelTests: XCTestCase {
    func testRecordedPCMCAFLoadsForAudioPlayback() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
        buffer.frameLength = 44_100
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<44_100 { samples[index] = 0 }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }

        let model = RecordingPlaybackModel(url: url)
        await model.prepare()
        XCTAssertNil(model.errorMessage)
        XCTAssertGreaterThan(model.duration, 0.9)
        XCTAssertTrue(model.isPlaying)
        model.stop()
    }

    func testMissingTakeShowsAnErrorInsteadOfOpeningAnEmptyPlayer() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mov")
        let model = RecordingPlaybackModel(url: url)
        await model.prepare()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.videoPlayer)
        XCTAssertFalse(model.isPlaying)
    }
}
