import AVFoundation
import CoreMedia
import XCTest
@testable import FollowScript

@MainActor
final class AudioTakeExporterTests: XCTestCase {
    func testCompletedPCMRecordingExportsAACM4A() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: source) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
        buffer.frameLength = 44_100
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<44_100 {
            samples[index] = sin(Float(index) * 2 * .pi * 440 / 44_100) * 0.2
        }
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            try file.write(from: buffer)
        }

        let exported = try await AudioTakeExporter.exportAAC(from: source)
        defer { try? FileManager.default.removeItem(at: exported) }
        XCTAssertEqual(exported.pathExtension, "m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertGreaterThan(try exported.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0)
        let tracks = try await AVURLAsset(url: exported).loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let formatDescriptions = try await track.load(.formatDescriptions)
        XCTAssertTrue(formatDescriptions.contains {
            CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC
        })

        let playback = RecordingPlaybackModel(url: exported)
        await playback.prepare()
        XCTAssertNil(playback.errorMessage)
        XCTAssertGreaterThan(playback.duration, 0.9)
        playback.stop()
    }

    func testMissingSourceDoesNotCreateAACFile() async {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).caf")
        do {
            _ = try await AudioTakeExporter.exportAAC(from: source)
            XCTFail("Missing audio should not export")
        } catch {
            XCTAssertTrue(error is AudioTakeExportError)
        }
    }
}
