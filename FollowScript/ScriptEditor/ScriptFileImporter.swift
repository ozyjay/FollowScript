import Compression
import Foundation
import UniformTypeIdentifiers
import UIKit

enum ScriptImportError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case fileTooLarge
    case invalidDocument
    case unsupportedArchive
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let extensionName):
            "FollowScript cannot import .\(extensionName) files."
        case .fileTooLarge:
            "The selected document is too large to import safely."
        case .invalidDocument:
            "The selected file does not contain a readable document."
        case .unsupportedArchive:
            "This document uses an unsupported archive format."
        case .emptyDocument:
            "The selected document does not contain any script text."
        }
    }
}

enum ScriptFileImporter {
    private static let supportedExtensions = [
        "docx", "odt", "md", "markdown", "txt", "text", "rtf", "html", "htm"
    ]
    private static let maximumFileSize = 50 * 1_024 * 1_024
    private static let maximumExtractedTextSize = 10 * 1_024 * 1_024

    static let supportedContentTypes: [UTType] = supportedExtensions.compactMap {
        UTType(filenameExtension: $0)
    }

    static func importText(from url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let gainedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gainedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= maximumFileSize else {
                throw ScriptImportError.fileTooLarge
            }

            let text = try decode(data, fileExtension: url.pathExtension.lowercased())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw ScriptImportError.emptyDocument
            }
            return text
        }.value
    }

    private static func decode(_ data: Data, fileExtension: String) throws -> String {
        switch fileExtension {
        case "txt", "text":
            return try decodePlainText(data)
        case "md", "markdown":
            let source = try decodePlainText(data)
            return try String(AttributedString(markdown: source).characters)
        case "rtf":
            return try decodeAttributedText(data, type: .rtf)
        case "html", "htm":
            return try decodeAttributedText(data, type: .html)
        case "docx":
            let xml = try ZIPDocumentReader.entry(named: "word/document.xml", in: data)
            return try XMLDocumentTextReader.text(from: xml, format: .word)
        case "odt":
            let xml = try ZIPDocumentReader.entry(named: "content.xml", in: data)
            return try XMLDocumentTextReader.text(from: xml, format: .openDocument)
        default:
            throw ScriptImportError.unsupportedFormat(fileExtension.isEmpty ? "unknown" : fileExtension)
        }
    }

    private static func decodePlainText(_ data: Data) throws -> String {
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        throw ScriptImportError.invalidDocument
    }

    private static func decodeAttributedText(
        _ data: Data,
        type: NSAttributedString.DocumentType
    ) throws -> String {
        do {
            return try NSAttributedString(
                data: data,
                options: [.documentType: type],
                documentAttributes: nil
            ).string
        } catch {
            throw ScriptImportError.invalidDocument
        }
    }

    private enum ZIPDocumentReader {
        private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
        private static let centralDirectorySignature: UInt32 = 0x0201_4b50
        private static let localHeaderSignature: UInt32 = 0x0403_4b50

        static func entry(named targetName: String, in archive: Data) throws -> Data {
            guard let endOffset = endOfCentralDirectory(in: archive),
                  archive.uint16LE(at: endOffset + 4) == 0,
                  archive.uint16LE(at: endOffset + 6) == 0,
                  let entryCount = archive.uint16LE(at: endOffset + 10),
                  let centralOffsetValue = archive.uint32LE(at: endOffset + 16) else {
                throw ScriptImportError.invalidDocument
            }

            var offset = Int(centralOffsetValue)
            for _ in 0..<Int(entryCount) {
                guard archive.uint32LE(at: offset) == centralDirectorySignature,
                      let flags = archive.uint16LE(at: offset + 8),
                      let method = archive.uint16LE(at: offset + 10),
                      let compressedSizeValue = archive.uint32LE(at: offset + 20),
                      let uncompressedSizeValue = archive.uint32LE(at: offset + 24),
                      let nameLength = archive.uint16LE(at: offset + 28),
                      let extraLength = archive.uint16LE(at: offset + 30),
                      let commentLength = archive.uint16LE(at: offset + 32),
                      let localOffsetValue = archive.uint32LE(at: offset + 42) else {
                    throw ScriptImportError.invalidDocument
                }

                let nameStart = offset + 46
                let nameEnd = nameStart + Int(nameLength)
                guard let nameData = archive.safeSubdata(in: nameStart..<nameEnd),
                      let name = String(data: nameData, encoding: .utf8) else {
                    throw ScriptImportError.invalidDocument
                }

                if name == targetName {
                    guard flags & 0x0001 == 0 else {
                        throw ScriptImportError.unsupportedArchive
                    }
                    return try extract(
                        archive: archive,
                        localOffset: Int(localOffsetValue),
                        method: method,
                        compressedSize: Int(compressedSizeValue),
                        uncompressedSize: Int(uncompressedSizeValue)
                    )
                }

                offset = nameEnd + Int(extraLength) + Int(commentLength)
            }

            throw ScriptImportError.invalidDocument
        }

        private static func endOfCentralDirectory(in archive: Data) -> Int? {
            guard archive.count >= 22 else { return nil }
            let earliestOffset = max(0, archive.count - 65_557)
            for offset in stride(from: archive.count - 22, through: earliestOffset, by: -1) {
                if archive.uint32LE(at: offset) == endOfCentralDirectorySignature {
                    return offset
                }
            }
            return nil
        }

        private static func extract(
            archive: Data,
            localOffset: Int,
            method: UInt16,
            compressedSize: Int,
            uncompressedSize: Int
        ) throws -> Data {
            guard archive.uint32LE(at: localOffset) == localHeaderSignature,
                  let localNameLength = archive.uint16LE(at: localOffset + 26),
                  let localExtraLength = archive.uint16LE(at: localOffset + 28),
                  uncompressedSize > 0,
                  uncompressedSize <= maximumExtractedTextSize else {
                throw ScriptImportError.invalidDocument
            }

            let dataStart = localOffset + 30 + Int(localNameLength) + Int(localExtraLength)
            guard let compressed = archive.safeSubdata(in: dataStart..<(dataStart + compressedSize)) else {
                throw ScriptImportError.invalidDocument
            }

            switch method {
            case 0:
                guard compressed.count == uncompressedSize else {
                    throw ScriptImportError.invalidDocument
                }
                return compressed
            case 8:
                var output = Data(count: uncompressedSize)
                let decodedCount = output.withUnsafeMutableBytes { destination in
                    compressed.withUnsafeBytes { source in
                        compression_decode_buffer(
                            destination.bindMemory(to: UInt8.self).baseAddress!,
                            uncompressedSize,
                            source.bindMemory(to: UInt8.self).baseAddress!,
                            compressed.count,
                            nil,
                            COMPRESSION_ZLIB
                        )
                    }
                }
                guard decodedCount == uncompressedSize else {
                    throw ScriptImportError.invalidDocument
                }
                return output
            default:
                throw ScriptImportError.unsupportedArchive
            }
        }
    }

    private enum XMLDocumentTextReader {
        enum Format {
            case word
            case openDocument
        }

        static func text(from data: Data, format: Format) throws -> String {
            let delegate = TextParserDelegate(format: format)
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.delegate = delegate
            guard parser.parse() else {
                throw ScriptImportError.invalidDocument
            }
            return delegate.text
        }
    }

    private final class TextParserDelegate: NSObject, XMLParserDelegate {
        private let format: XMLDocumentTextReader.Format
        private var paragraph = ""
        private var paragraphs: [String] = []
        private var isInsideParagraph = false
        private var isInsideWordText = false

        init(format: XMLDocumentTextReader.Format) {
            self.format = format
        }

        var text: String {
            paragraphs.joined(separator: "\n\n")
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = localName(elementName, qualifiedName: qName)
            switch format {
            case .word:
                guard namespaceURI?.contains("wordprocessingml") == true else { return }
                if name == "p" {
                    beginParagraph()
                } else if isInsideParagraph, name == "t" {
                    isInsideWordText = true
                } else if isInsideParagraph, name == "tab" {
                    paragraph.append("\t")
                } else if isInsideParagraph, name == "br" || name == "cr" {
                    paragraph.append("\n")
                }
            case .openDocument:
                guard namespaceURI?.contains("opendocument:xmlns:text") == true else { return }
                if name == "p" || name == "h" {
                    beginParagraph()
                } else if isInsideParagraph, name == "tab" {
                    paragraph.append("\t")
                } else if isInsideParagraph, name == "line-break" {
                    paragraph.append("\n")
                } else if isInsideParagraph, name == "s" {
                    let count = attributeDict.first { key, _ in
                        key == "c" || key.hasSuffix(":c")
                    }.flatMap { Int($0.value) } ?? 1
                    paragraph.append(String(repeating: " ", count: min(count, 100)))
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            switch format {
            case .word where isInsideParagraph && isInsideWordText:
                paragraph.append(string)
            case .openDocument where isInsideParagraph:
                paragraph.append(string)
            default:
                break
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = localName(elementName, qualifiedName: qName)
            switch format {
            case .word:
                if name == "t" {
                    isInsideWordText = false
                } else if name == "p" {
                    endParagraph()
                }
            case .openDocument:
                if name == "p" || name == "h" {
                    endParagraph()
                }
            }
        }

        private func beginParagraph() {
            if isInsideParagraph {
                endParagraph()
            }
            paragraph = ""
            isInsideParagraph = true
        }

        private func endParagraph() {
            guard isInsideParagraph else { return }
            let cleaned = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                paragraphs.append(cleaned)
            }
            paragraph = ""
            isInsideParagraph = false
            isInsideWordText = false
        }

        private func localName(_ elementName: String, qualifiedName: String?) -> String {
            if !elementName.isEmpty {
                return elementName
            }
            return (qualifiedName ?? elementName).split(separator: ":").last.map(String.init) ?? elementName
        }
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16? {
        guard let bytes = safeSubdata(in: offset..<(offset + 2)) else { return nil }
        return bytes.withUnsafeBytes { rawPointer in
            let pointer = rawPointer.bindMemory(to: UInt8.self)
            return UInt16(pointer[0]) | (UInt16(pointer[1]) << 8)
        }
    }

    func uint32LE(at offset: Int) -> UInt32? {
        guard let bytes = safeSubdata(in: offset..<(offset + 4)) else { return nil }
        return bytes.withUnsafeBytes { rawPointer in
            let pointer = rawPointer.bindMemory(to: UInt8.self)
            let byte0 = UInt32(pointer[0])
            let byte1 = UInt32(pointer[1]) << 8
            let byte2 = UInt32(pointer[2]) << 16
            let byte3 = UInt32(pointer[3]) << 24
            return byte0 | byte1 | byte2 | byte3
        }
    }

    func safeSubdata(in range: Range<Int>) -> Data? {
        guard range.lowerBound >= 0, range.upperBound <= count else { return nil }
        return subdata(in: range)
    }
}
