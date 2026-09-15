import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Exports the media as a file, rather than handing a bare local URL to ShareLink.
struct LocalRecordingFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .quickTimeMovie) { recording in
            try recording.sentFile(expectedExtension: "mov")
        }
        .exportingCondition { $0.url.pathExtension.lowercased() == "mov" }
        .suggestedFileName { $0.url.lastPathComponent }

        FileRepresentation(
            exportedContentType: UTType(importedAs: "com.apple.coreaudio-format", conformingTo: .audio)
        ) { recording in
            try recording.sentFile(expectedExtension: "caf")
        }
        .exportingCondition { $0.url.pathExtension.lowercased() == "caf" }
        .suggestedFileName { $0.url.lastPathComponent }
    }

    private func sentFile(expectedExtension: String) throws -> SentTransferredFile {
        guard url.isFileURL, url.pathExtension.lowercased() == expectedExtension,
              FileManager.default.fileExists(atPath: url.path) else {
            throw LocalRecordingFileError.fileMissing
        }
        return SentTransferredFile(url, allowAccessingOriginalFile: false)
    }
}

private enum LocalRecordingFileError: LocalizedError {
    case fileMissing
    var errorDescription: String? { "This recording is no longer on the device." }
}
