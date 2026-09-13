import Compression
import XCTest
@testable import FollowScript

final class ScriptFileImporterTests: XCTestCase {
    func testImportsPlainText() async throws {
        let url = try temporaryFile(extension: "txt", data: Data("A plain script.\n\nWith two paragraphs.".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await ScriptFileImporter.importText(from: url)

        XCTAssertEqual(text, "A plain script.\n\nWith two paragraphs.")
    }

    func testImportsMarkdownWithoutFormattingMarkers() async throws {
        let source = "# Opening\n\nRead **this line** clearly."
        let url = try temporaryFile(extension: "md", data: Data(source.utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await ScriptFileImporter.importText(from: url)

        XCTAssertFalse(text.contains("#"))
        XCTAssertFalse(text.contains("**"))
        XCTAssertTrue(text.contains("Opening"))
        XCTAssertTrue(text.contains("Read this line clearly."))
    }

    func testImportsDeflatedWordDocumentText() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Hello from Word</w:t><w:tab/><w:t>today.</w:t></w:r></w:p>
            <w:p><w:r><w:t>Second paragraph.</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        let archive = try zip(entryName: "word/document.xml", contents: Data(xml.utf8), compress: true)
        let url = try temporaryFile(extension: "docx", data: archive)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await ScriptFileImporter.importText(from: url)

        XCTAssertEqual(text, "Hello from Word\ttoday.\n\nSecond paragraph.")
    }

    func testImportsOpenDocumentText() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content
          xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
          xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
          <office:body><office:text>
            <text:h>Opening</text:h>
            <text:p>Hello <text:span>ODT</text:span><text:line-break/>again.</text:p>
          </office:text></office:body>
        </office:document-content>
        """
        let archive = try zip(entryName: "content.xml", contents: Data(xml.utf8), compress: false)
        let url = try temporaryFile(extension: "odt", data: archive)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await ScriptFileImporter.importText(from: url)

        XCTAssertEqual(text, "Opening\n\nHello ODT\nagain.")
    }

    private func temporaryFile(extension extensionName: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(extensionName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func zip(entryName: String, contents: Data, compress: Bool) throws -> Data {
        let encodedContents: Data
        let compressionMethod: UInt16
        if compress {
            var destination = Data(count: max(256, contents.count * 2))
            let destinationCapacity = destination.count
            let encodedCount = destination.withUnsafeMutableBytes { output in
                contents.withUnsafeBytes { input in
                    compression_encode_buffer(
                        output.bindMemory(to: UInt8.self).baseAddress!,
                        destinationCapacity,
                        input.bindMemory(to: UInt8.self).baseAddress!,
                        contents.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            guard encodedCount > 0 else {
                throw ScriptImportError.invalidDocument
            }
            encodedContents = Data(destination.prefix(encodedCount))
            compressionMethod = 8
        } else {
            encodedContents = contents
            compressionMethod = 0
        }

        let name = Data(entryName.utf8)
        var local = Data()
        local.appendLE(UInt32(0x0403_4b50))
        local.appendLE(UInt16(20))
        local.appendLE(UInt16(0))
        local.appendLE(compressionMethod)
        local.appendLE(UInt16(0))
        local.appendLE(UInt16(0))
        local.appendLE(UInt32(0))
        local.appendLE(UInt32(encodedContents.count))
        local.appendLE(UInt32(contents.count))
        local.appendLE(UInt16(name.count))
        local.appendLE(UInt16(0))
        local.append(name)
        local.append(encodedContents)

        var central = Data()
        central.appendLE(UInt32(0x0201_4b50))
        central.appendLE(UInt16(20))
        central.appendLE(UInt16(20))
        central.appendLE(UInt16(0))
        central.appendLE(compressionMethod)
        central.appendLE(UInt16(0))
        central.appendLE(UInt16(0))
        central.appendLE(UInt32(0))
        central.appendLE(UInt32(encodedContents.count))
        central.appendLE(UInt32(contents.count))
        central.appendLE(UInt16(name.count))
        central.appendLE(UInt16(0))
        central.appendLE(UInt16(0))
        central.appendLE(UInt16(0))
        central.appendLE(UInt16(0))
        central.appendLE(UInt32(0))
        central.appendLE(UInt32(0))
        central.append(name)

        var result = local
        result.append(central)
        result.appendLE(UInt32(0x0605_4b50))
        result.appendLE(UInt16(0))
        result.appendLE(UInt16(0))
        result.appendLE(UInt16(1))
        result.appendLE(UInt16(1))
        result.appendLE(UInt32(central.count))
        result.appendLE(UInt32(local.count))
        result.appendLE(UInt16(0))
        return result
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }
}
