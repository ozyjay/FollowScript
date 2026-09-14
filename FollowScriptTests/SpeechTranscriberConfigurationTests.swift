import Speech
import XCTest
@testable import FollowScript

@available(iOS 26.0, *)
final class SpeechTranscriberConfigurationTests: XCTestCase {
    func testStableProgressivePresetFavoursAccuracyWithoutLosingProgressiveMetadata() {
        let preset = FollowScriptSpeechTranscriberConfiguration.stableProgressivePreset

        XCTAssertEqual(preset.transcriptionOptions, [])
        XCTAssertEqual(
            preset.reportingOptions,
            [.volatileResults, .alternativeTranscriptions]
        )
        XCTAssertFalse(preset.reportingOptions.contains(.fastResults))
        XCTAssertEqual(preset.attributeOptions, [.audioTimeRange])
    }
}
