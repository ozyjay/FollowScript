import AVFoundation
import CoreMedia
import Foundation

enum AudioTakeExportError: LocalizedError {
    case invalidSource, exporterUnavailable, invalidOutput, cleanupFailed

    var errorDescription: String? {
        switch self {
        case .invalidSource: "The recorded audio could not be opened for AAC conversion."
        case .exporterUnavailable: "AAC conversion is not available for this recording."
        case .invalidOutput: "AAC conversion did not produce a playable audio file."
        case .cleanupFailed: "AAC conversion failed and its unfinished file could not be removed."
        }
    }
}

/// Converts a completed PCM take; it never runs on the live microphone tap.
@MainActor
enum AudioTakeExporter {
    static func exportAAC(from source: URL) async throws -> URL {
        guard source.isFileURL, source.pathExtension.lowercased() == "caf",
              FileManager.default.fileExists(atPath: source.path) else {
            throw AudioTakeExportError.invalidSource
        }
        let asset = AVURLAsset(url: source)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty,
              await AVAssetExportSession.compatibility(
                ofExportPreset: AVAssetExportPresetAppleM4A, with: asset, outputFileType: .m4a
              ),
              let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioTakeExportError.exporterUnavailable
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID()).m4a")
        do {
            try await exporter.export(to: destination, as: .m4a)
            let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let exportedAsset = AVURLAsset(url: destination)
            guard size > 0,
                  let track = try await exportedAsset.loadTracks(withMediaType: .audio).first,
                  try await track.load(.formatDescriptions).contains(where: {
                      CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC
                  }) else {
                throw AudioTakeExportError.invalidOutput
            }
            return destination
        } catch {
            if FileManager.default.fileExists(atPath: destination.path) {
                do { try FileManager.default.removeItem(at: destination) }
                catch { throw AudioTakeExportError.cleanupFailed }
            }
            throw error
        }
    }
}
