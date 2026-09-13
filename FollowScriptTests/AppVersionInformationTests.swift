import XCTest
@testable import FollowScript

final class AppVersionInformationTests: XCTestCase {
    func testPresentsVersionAndBuildFromBundleInformation() {
        let information = AppVersionInformation(infoDictionary: [
            "CFBundleShortVersionString": "1.7",
            "CFBundleVersion": "42"
        ])

        XCTAssertEqual(information.version, "1.7")
        XCTAssertEqual(information.build, "42")
        XCTAssertEqual(information.displayText, "Version 1.7 • Build 42")
    }

    func testUsesPlaceholderForMissingVersionInformation() {
        let information = AppVersionInformation(infoDictionary: [:])

        XCTAssertEqual(information.displayText, "Version — • Build —")
    }
}
