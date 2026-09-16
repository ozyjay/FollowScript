import Foundation
import XCTest
@testable import FollowScript

@MainActor
final class AppModelPresentationTests: XCTestCase {
    private var rootURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        suiteName = "AppModelPresentationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rootURL)
        defaults = nil
        suiteName = nil
        rootURL = nil
        super.tearDown()
    }

    func testStandaloneScriptMigratesIntoSelectedPresentation() throws {
        defaults.set("A legacy script", forKey: "currentScript")

        let model = AppModel(defaults: defaults, projectsRootURL: rootURL)

        XCTAssertEqual(model.selectedProject?.title, "My Presentation")
        XCTAssertEqual(model.scriptText, "A legacy script")
        XCTAssertEqual(try PresentationProjectStore.projects(rootURL: rootURL).first?.script, "A legacy script")
        XCTAssertNil(defaults.string(forKey: "currentScript"))
    }

    func testEditingUpdatesSelectedPresentationWithoutChangingItsIdentity() throws {
        let model = AppModel(defaults: defaults, projectsRootURL: rootURL)
        let originalID = try XCTUnwrap(model.selectedProject?.id)

        model.scriptText = "The updated presentation script"
        model.flushPendingChanges()

        XCTAssertEqual(model.selectedProject?.id, originalID)
        XCTAssertEqual(try PresentationProjectStore.projects(rootURL: rootURL).first?.script,
                       "The updated presentation script")
    }

    func testSelectingPresentationChangesTheEditorAndPersistsSelection() throws {
        let model = AppModel(defaults: defaults, projectsRootURL: rootURL)
        let selected = try XCTUnwrap(model.createPresentation(title: "Second", script: "Second script"))

        let restored = AppModel(defaults: defaults, projectsRootURL: rootURL)

        XCTAssertEqual(restored.selectedProject?.id, selected.id)
        XCTAssertEqual(restored.scriptText, "Second script")
    }
}
