import XCTest
@testable import FollowScript

final class FollowScriptSettingsTests: XCTestCase {
    func testDecodingStoredSettingsWithoutMirrorPreferenceUsesNormalView() throws {
        let storedSettings = Data(
            #"{"fontSize":48,"lineSpacing":10,"textAlignment":"centre","highlightsActivePhrase":false}"#.utf8
        )

        let settings = try JSONDecoder().decode(FollowScriptSettings.self, from: storedSettings)

        XCTAssertEqual(settings.fontSize, 48)
        XCTAssertEqual(settings.lineSpacing, 10)
        XCTAssertEqual(settings.textAlignment, .centre)
        XCTAssertFalse(settings.highlightsActivePhrase)
        XCTAssertFalse(settings.mirrorsPrompt)
        XCTAssertFalse(settings.flipsPromptVertically)
    }

    func testPromptFlipPreferencesRoundTripThroughPersistenceEncoding() throws {
        var settings = FollowScriptSettings()
        settings.mirrorsPrompt = true
        settings.flipsPromptVertically = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(FollowScriptSettings.self, from: data)

        XCTAssertTrue(decoded.mirrorsPrompt)
        XCTAssertTrue(decoded.flipsPromptVertically)
    }
}
