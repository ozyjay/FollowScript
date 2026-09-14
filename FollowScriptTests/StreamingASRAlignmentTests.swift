import XCTest
#if SWIFT_PACKAGE
@testable import FollowScriptCore
#else
@testable import FollowScript
#endif

final class StreamingASRAlignmentTests: XCTestCase {
    func testRepeatedPlausibleLocalHoldsDoNotEnterReacquisition() {
        var configuration = ScriptAlignmentEngine.Configuration.standard
        configuration.commitThreshold = 1.01
        let engine = ScriptAlignmentEngine(configuration: configuration)
        let script = ScriptDocument(text: "alpha beta gamma delta epsilon zeta eta theta")
        let previous = AlignmentState(
            tokenIndex: 2,
            confidence: 0.9,
            trackingState: .tracking,
            lowConfidenceUpdates: 0
        )

        let first = engine.align(
            script: script,
            recognisedText: "alpha beta gamma delta",
            previous: previous,
            isFinal: false
        )
        let second = engine.align(
            script: script,
            recognisedText: "alpha beta gamma delta epsilon",
            previous: first.state,
            isFinal: false
        )

        XCTAssertEqual(first.searchMode, .local)
        XCTAssertEqual(first.committedTokenIndex, 2)
        XCTAssertEqual(first.state.lowConfidenceUpdates, 0)
        XCTAssertEqual(first.trackingState, .uncertain)
        XCTAssertEqual(second.searchMode, .local)
        XCTAssertEqual(second.committedTokenIndex, 2)
        XCTAssertEqual(second.state.lowConfidenceUpdates, 0)
        XCTAssertNotEqual(second.trackingState, .reacquiring)
    }

    func testRepeatedImplausibleLocalEvidenceStillTriggersReacquisition() {
        var configuration = ScriptAlignmentEngine.Configuration.standard
        configuration.commitThreshold = 1.01
        let engine = ScriptAlignmentEngine(configuration: configuration)
        let script = ScriptDocument(text: "alpha beta gamma delta epsilon zeta eta theta")
        let previous = AlignmentState(
            tokenIndex: 2,
            confidence: 0.9,
            trackingState: .tracking,
            lowConfidenceUpdates: 0
        )

        let first = engine.align(
            script: script,
            recognisedText: "zebra quantum pineapple",
            previous: previous,
            isFinal: false
        )
        let second = engine.align(
            script: script,
            recognisedText: "violet submarine cactus",
            previous: first.state,
            isFinal: false
        )

        XCTAssertEqual(first.committedTokenIndex, 2)
        XCTAssertEqual(first.state.lowConfidenceUpdates, 1)
        XCTAssertEqual(first.trackingState, .uncertain)
        XCTAssertEqual(second.committedTokenIndex, 2)
        XCTAssertEqual(second.state.lowConfidenceUpdates, 2)
        XCTAssertEqual(second.trackingState, .reacquiring)
    }

    func testCumulativeRecognitionCanUseContextBehindCommittedAnchor() {
        let engine = ScriptAlignmentEngine()
        let script = ScriptDocument(text: "zero one two three four five six seven eight nine")
        let previous = AlignmentState(
            tokenIndex: 5,
            confidence: 0.9,
            trackingState: .tracking,
            lowConfidenceUpdates: 0
        )

        let result = engine.align(
            script: script,
            recognisedText: "two three four five six seven",
            previous: previous,
            isFinal: true
        )

        XCTAssertEqual(result.searchMode, .local)
        XCTAssertEqual(result.committedTokenIndex, 7)
        XCTAssertEqual(result.matchedRange, 5...7)
        XCTAssertEqual(result.trackingState, .tracking)
    }

    func testOverlappingContextCannotMoveCommittedEndpointBackwards() {
        let engine = ScriptAlignmentEngine()
        let script = ScriptDocument(text: "zero one two three four five six seven eight nine")
        let previous = AlignmentState(
            tokenIndex: 5,
            confidence: 0.9,
            trackingState: .tracking,
            lowConfidenceUpdates: 0
        )

        let result = engine.align(
            script: script,
            recognisedText: "zero one two three four",
            previous: previous,
            isFinal: true
        )

        XCTAssertGreaterThanOrEqual(result.committedTokenIndex ?? 0, 5)
        if let range = result.matchedRange {
            XCTAssertGreaterThanOrEqual(range.lowerBound, 5)
        }
    }
}
