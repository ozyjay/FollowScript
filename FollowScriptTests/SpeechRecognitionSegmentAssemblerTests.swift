import XCTest
#if SWIFT_PACKAGE
@testable import FollowScriptCore
#else
@testable import FollowScript
#endif

final class SpeechRecognitionSegmentAssemblerTests: XCTestCase {
    func testVolatileRevisionReplacesSameAudioRange() {
        var assembler = SpeechRecognitionSegmentAssembler()

        _ = assembler.ingest(
            text: "ICT Pro",
            audioTimeRange: 0..<1,
            isFinal: false
        )
        let revised = assembler.ingest(
            text: "ICT Project",
            audioTimeRange: 0..<1,
            isFinal: false
        )

        XCTAssertEqual(revised.text, "ICT Project")
    }

    func testAdjacentFinalFragmentsBecomeRollingContext() {
        var assembler = SpeechRecognitionSegmentAssembler()

        _ = assembler.ingest(
            text: "ICT Project",
            audioTimeRange: 0..<1,
            isFinal: true,
            finalizationTime: 1
        )
        _ = assembler.ingest(
            text: "One, Analysis",
            audioTimeRange: 1..<2,
            isFinal: true,
            finalizationTime: 2
        )
        _ = assembler.ingest(
            text: "and",
            audioTimeRange: 2..<3,
            isFinal: true,
            finalizationTime: 3
        )
        let result = assembler.ingest(
            text: "Design.",
            audioTimeRange: 3..<4,
            isFinal: true,
            finalizationTime: 4
        )

        XCTAssertEqual(result.text, "ICT Project One, Analysis and Design.")
        XCTAssertEqual(result.audioTimeRange, 0..<4)
    }

    func testFinalResultReplacesPriorVolatileRevision() {
        var assembler = SpeechRecognitionSegmentAssembler()

        _ = assembler.ingest(
            text: "Jason Holts",
            audioTimeRange: 4..<5,
            isFinal: false
        )
        let result = assembler.ingest(
            text: "Jason Holdsworth",
            audioTimeRange: 4..<5,
            isFinal: true,
            finalizationTime: 5
        )

        XCTAssertEqual(result.text, "Jason Holdsworth")
    }

    func testFinalizationTimePreservesEarlierVolatileSegmentWhenNewPhraseArrives() {
        var assembler = SpeechRecognitionSegmentAssembler()

        _ = assembler.ingest(
            text: "CP 5046",
            audioTimeRange: 0..<1,
            isFinal: false
        )
        let result = assembler.ingest(
            text: "you'll work",
            audioTimeRange: 1..<2,
            isFinal: false,
            finalizationTime: 1
        )

        XCTAssertEqual(result.text, "CP 5046 you'll work")
    }

    func testAlternativesReceiveTheSameEarlierContext() {
        var assembler = SpeechRecognitionSegmentAssembler()

        _ = assembler.ingest(
            text: "ICT Project",
            audioTimeRange: 0..<1,
            isFinal: true,
            finalizationTime: 1
        )
        let result = assembler.ingest(
            text: "One Analysis",
            alternatives: ["1 Analysis", "One, Analysis"],
            audioTimeRange: 1..<2,
            isFinal: false,
            finalizationTime: 1
        )

        XCTAssertEqual(
            result.alternatives,
            ["ICT Project 1 Analysis", "ICT Project One, Analysis"]
        )
    }

    func testResetDropsContextBetweenRecognitionSessions() {
        var assembler = SpeechRecognitionSegmentAssembler()
        _ = assembler.ingest(
            text: "old session",
            audioTimeRange: 0..<1,
            isFinal: true,
            finalizationTime: 1
        )

        assembler.reset()
        let result = assembler.ingest(
            text: "new session",
            audioTimeRange: 0..<1,
            isFinal: false
        )

        XCTAssertEqual(result.text, "new session")
    }
}
