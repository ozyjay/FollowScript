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
        XCTAssertTrue(settings.centresHighlightedText)
        XCTAssertFalse(settings.mirrorsPrompt)
        XCTAssertFalse(settings.flipsPromptVertically)
        XCTAssertFalse(settings.keepsDisplayAwake)
        XCTAssertTrue(settings.ignoresSquareBracketedText)
        XCTAssertTrue(settings.removesExtraWhitespace)
    }

    func testPromptFlipPreferencesRoundTripThroughPersistenceEncoding() throws {
        var settings = FollowScriptSettings()
        settings.mirrorsPrompt = true
        settings.flipsPromptVertically = true
        settings.keepsDisplayAwake = true
        settings.centresHighlightedText = false
        settings.ignoresSquareBracketedText = false
        settings.removesExtraWhitespace = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(FollowScriptSettings.self, from: data)

        XCTAssertTrue(decoded.mirrorsPrompt)
        XCTAssertTrue(decoded.flipsPromptVertically)
        XCTAssertTrue(decoded.keepsDisplayAwake)
        XCTAssertFalse(decoded.centresHighlightedText)
        XCTAssertFalse(decoded.ignoresSquareBracketedText)
        XCTAssertFalse(decoded.removesExtraWhitespace)
    }
}
