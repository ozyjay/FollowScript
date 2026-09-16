import XCTest
import UIKit
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
        XCTAssertFalse(settings.logsTimestampedTrackingInformation)
        XCTAssertTrue(settings.ignoresSquareBracketedText)
        XCTAssertTrue(settings.removesExtraWhitespace)
    }

    func testPromptFlipPreferencesRoundTripThroughPersistenceEncoding() throws {
        var settings = FollowScriptSettings()
        settings.mirrorsPrompt = true
        settings.flipsPromptVertically = true
        settings.keepsDisplayAwake = true
        settings.logsTimestampedTrackingInformation = true
        settings.centresHighlightedText = false
        settings.ignoresSquareBracketedText = false
        settings.removesExtraWhitespace = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(FollowScriptSettings.self, from: data)

        XCTAssertTrue(decoded.mirrorsPrompt)
        XCTAssertTrue(decoded.flipsPromptVertically)
        XCTAssertTrue(decoded.keepsDisplayAwake)
        XCTAssertTrue(decoded.logsTimestampedTrackingInformation)
        XCTAssertFalse(decoded.centresHighlightedText)
        XCTAssertFalse(decoded.ignoresSquareBracketedText)
        XCTAssertFalse(decoded.removesExtraWhitespace)
    }

    func testVideoPromptPlacementDefaultsForOlderSavedSettings() throws {
        let data = Data(#"{"fontSize":42,"lastPresentationMode":"audiovisual"}"#.utf8)
        let settings = try JSONDecoder().decode(FollowScriptSettings.self, from: data)
        XCTAssertEqual(settings.videoPromptPlacement, .automatic)
        XCTAssertEqual(settings.videoFrameRate, .automatic)
    }

    func testVideoPromptPlacementPersistsAndFollowsCameraEdge() throws {
        var settings = FollowScriptSettings()
        settings.videoPromptPlacement = .trailing
        let decoded = try JSONDecoder().decode(FollowScriptSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.videoPromptPlacement, .trailing)
        XCTAssertEqual(FollowScriptSettings.VideoPromptPlacement.automatic.resolved(
            isLandscape: false, orientation: .portrait), .top)
        XCTAssertEqual(FollowScriptSettings.VideoPromptPlacement.automatic.resolved(
            isLandscape: true, orientation: .landscapeLeft), .trailing)
        XCTAssertEqual(FollowScriptSettings.VideoPromptPlacement.automatic.resolved(
            isLandscape: true, orientation: .landscapeRight), .leading)
    }

    func testVideoFrameRatePersists() throws {
        for rate in FollowScriptSettings.VideoFrameRate.allCases {
            var settings = FollowScriptSettings()
            settings.videoFrameRate = rate
            let decoded = try JSONDecoder().decode(FollowScriptSettings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(decoded.videoFrameRate, rate)
        }
        XCTAssertEqual(FollowScriptSettings.VideoFrameRate.fps25.framesPerSecond, 25)
        XCTAssertEqual(FollowScriptSettings.VideoFrameRate.fps50.framesPerSecond, 50)
    }
}
