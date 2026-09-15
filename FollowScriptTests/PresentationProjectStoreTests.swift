import Foundation
import XCTest
#if canImport(FollowScriptCore)
@testable import FollowScriptCore
#else
@testable import FollowScript
#endif

final class PresentationProjectStoreTests: XCTestCase {
    func testProjectAndTakeLifecycleKeepsMediaOutsideMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try PresentationProjectStore.createProject(script: "A saved script", rootURL: root)
        XCTAssertEqual(try PresentationProjectStore.projects(rootURL: root).map(\.id), [project.id])

        let source = root.appendingPathComponent("source.caf")
        try Data([1, 2, 3]).write(to: source)
        let take = PresentationTake(id: UUID(), projectID: project.id, mode: .audio,
                                    startedAt: Date(), endedAt: Date(), mediaFilename: "take.caf", duration: 3)
        let savedURL = try PresentationProjectStore.saveTake(take, source: source, rootURL: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: savedURL), Data([1, 2, 3]))
        XCTAssertEqual(try PresentationProjectStore.takes(for: project.id, rootURL: root).map(\.id), [take.id])

        let renamed = try PresentationProjectStore.rename(project, to: "  New name  ", rootURL: root)
        XCTAssertEqual(renamed.title, "New name")
        XCTAssertEqual(try PresentationProjectStore.projects(rootURL: root).first?.title, "New name")
        try PresentationProjectStore.delete(take, rootURL: root)
        XCTAssertTrue(try PresentationProjectStore.takes(for: project.id, rootURL: root).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedURL.path))
        try PresentationProjectStore.delete(renamed, rootURL: root)
        XCTAssertTrue(try PresentationProjectStore.projects(rootURL: root).isEmpty)
    }

    func testMediaPathCannotEscapeProjectFolder() throws {
        let take = PresentationTake(id: UUID(), projectID: UUID(), mode: .audio,
                                    startedAt: Date(), endedAt: Date(), mediaFilename: "../outside.caf", duration: 1)
        XCTAssertThrowsError(try PresentationProjectStore.mediaURL(for: take))
    }

    func testAACMediaFilenameIsAcceptedForNewAudioTakes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try PresentationProjectStore.createProject(script: "Test", rootURL: root)
        let take = PresentationTake(id: UUID(), projectID: project.id, mode: .audio,
                                    startedAt: Date(), endedAt: Date(), mediaFilename: "take.m4a", duration: 1)
        XCTAssertEqual(try PresentationProjectStore.mediaURL(for: take, rootURL: root).pathExtension, "m4a")
    }
}
