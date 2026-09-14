import XCTest
#if SWIFT_PACKAGE
@testable import FollowScriptCore
#else
@testable import FollowScript
#endif

final class AlignmentClusterTests: XCTestCase {
    func testAdjacentCandidateEndpointsAreTreatedAsOneLocationCluster() {
        var configuration = ScriptAlignmentEngine.Configuration.standard
        configuration.localAdvanceSlack = 100
        configuration.ambiguousJumpDistance = 3
        configuration.minimumCandidateScoreMargin = 1
        configuration.candidateClusterRadius = 3
        configuration.beamWidth = 2
        let engine = ScriptAlignmentEngine(configuration: configuration)
        let script = ScriptDocument(text: "anchor one two three four five target common phrase ending")
        let previous = AlignmentState(
            tokenIndex: 0,
            confidence: 0.9,
            trackingState: .tracking,
            lowConfidenceUpdates: 0
        )

        let result = engine.align(
            script: script,
            recognisedText: "target common phrase ending",
            previous: previous,
            isFinal: true
        )

        XCTAssertGreaterThan(result.committedTokenIndex ?? 0, 0)
        XCTAssertEqual(result.decisionTrace.reason, .accepted)
        XCTAssertNil(result.decisionTrace.scoreMargin)
    }

    func testDistantCandidateClusterStillCountsAsAmbiguity() {
        var configuration = ScriptAlignmentEngine.Configuration.standard
        configuration.localAdvanceSlack = 100
        configuration.ambiguousJumpDistance = 3
        configuration.minimumCandidateScoreMargin = 1
        configuration.candidateClusterRadius = 2
        let engine = ScriptAlignmentEngine(configuration: configuration)
        let script = ScriptDocument(
            text: "anchor we can do this filler1 filler2 filler3 filler4 we can do this finish"
        )
        let previous = AlignmentState(
            tokenIndex: 0,
            confidence: 0.9,
            trackingState: .tracking,
            lowConfidenceUpdates: 0
        )

        let result = engine.align(
            script: script,
            recognisedText: "we can do this",
            previous: previous,
            isFinal: true
        )

        XCTAssertEqual(result.committedTokenIndex, 0)
        XCTAssertEqual(result.decisionTrace.reason, .ambiguousCandidates)
        XCTAssertNotNil(result.decisionTrace.scoreMargin)
    }

    func testFollowModePrefersNearbyPlausibleClusterOverDistantBeam() {
        var configuration = ScriptAlignmentEngine.Configuration.standard
        configuration.continuityPreferenceMargin = 1
        configuration.ambiguousJumpDistance = 100
        configuration.localAdvanceSlack = 100
        let engine = ScriptAlignmentEngine(configuration: configuration)
        let script = ScriptDocument(
            text: "anchor we can do this filler1 filler2 filler3 filler4 we can do this finish"
        )
        let previous = AlignmentState(
            tokenIndex: 0,
            confidence: 0.9,
            trackingState: .tracking,
            lowConfidenceUpdates: 0,
            hypotheses: [AlignmentHypothesis(tokenIndex: 9, score: 1)]
        )

        let result = engine.align(
            script: script,
            recognisedText: "we can do this",
            previous: previous,
            isFinal: false
        )

        XCTAssertEqual(result.committedTokenIndex, 4)
        XCTAssertEqual(result.decisionTrace.decision, .advance)
        XCTAssertEqual(result.decisionTrace.reason, .accepted)
    }

    func testGlobalReacquisitionStillAllowsDistinctiveLargeCatchUp() {
        let engine = ScriptAlignmentEngine()
        let filler = (1...25).map { "filler\($0)" }.joined(separator: " ")
        let script = ScriptDocument(text: "anchor \(filler) cobalt telescope marks destination")
        let previous = AlignmentState(
            tokenIndex: 0,
            confidence: 0.2,
            trackingState: .reacquiring,
            lowConfidenceUpdates: 2
        )

        let result = engine.align(
            script: script,
            recognisedText: "cobalt telescope marks destination",
            previous: previous,
            isFinal: true
        )

        XCTAssertEqual(result.searchMode, .global)
        XCTAssertGreaterThan(result.committedTokenIndex ?? 0, 25)
        XCTAssertEqual(result.decisionTrace.reason, .accepted)
    }
}
