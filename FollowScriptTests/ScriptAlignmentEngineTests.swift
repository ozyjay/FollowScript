import XCTest
#if SWIFT_PACKAGE
@testable import FollowScriptCore
#else
@testable import FollowScript
#endif

final class ScriptAlignmentEngineTests: XCTestCase {
    private let engine = ScriptAlignmentEngine()

    func testExactReadingAndCapitalisation() {
        let result = align("One bright morning we crossed the river.", speech: "ONE BRIGHT MORNING WE CROSSED")
        XCTAssertEqual(result.tokenIndex, 4)
        XCTAssertEqual(result.trackingState, .tracking)
    }

    func testPunctuationDifferences() {
        let result = align("Wait—please stop; then breathe.", speech: "wait please stop then breathe")
        XCTAssertEqual(result.tokenIndex, 4)
    }

    func testMissingAndInsertedWords() {
        let script = ScriptDocument(text: "The research demonstrates that cybersickness remains a significant challenge for immersive virtual reality systems")
        let omitted = engine.align(script: script, recognisedText: "research demonstrates cybersickness remains a significant challenge")
        let inserted = engine.align(script: script, recognisedText: "the research clearly demonstrates that cybersickness really remains a significant challenge")
        XCTAssertTrue((omitted.tokenIndex ?? 0) >= 7)
        XCTAssertTrue((inserted.tokenIndex ?? 0) >= 7)
    }

    func testFillersHaveLittleInfluence() {
        let result = align("We first examined attention and then participant comfort", speech: "um we first uh examined attention and then participant comfort")
        XCTAssertEqual(result.tokenIndex, 7)
    }

    func testSingleAndMultipleRecognitionErrors() {
        let script = ScriptDocument(text: "We measured comprehension response time and long term trust")
        let single = engine.align(
            script: script,
            recognisedText: "we measured comprehension response lime and long term trust",
            isFinal: true
        )
        let multiple = engine.align(
            script: script,
            recognisedText: "we measured convention response lime and long term trust",
            isFinal: true
        )
        XCTAssertEqual(single.tokenIndex, 8)
        XCTAssertEqual(multiple.tokenIndex, 8)
    }

    func testRepeatedWordsDoNotPreventProgress() {
        let result = align("We will keep listening and keep learning as we keep building", speech: "keep listening and keep learning")
        XCTAssertTrue((result.tokenIndex ?? 0) >= 5)
    }

    func testRepeatedPhrasePrefersContinuity() {
        let script = ScriptDocument(text: "We begin together. Some material sits here. We begin together. The final section follows.")
        let previous = AlignmentState(tokenIndex: 3, confidence: 0.9, trackingState: .tracking, lowConfidenceUpdates: 0)
        let result = engine.align(script: script, recognisedText: "we begin together", previous: previous)
        XCTAssertEqual(result.tokenIndex, 8)
    }

    func testEarlierSentenceCannotMovePositionBackwards() {
        let script = ScriptDocument(text: "First we explain the goal. Next we describe the method. Finally we share the result.")
        let previous = AlignmentState(tokenIndex: 13, confidence: 0.9, trackingState: .tracking, lowConfidenceUpdates: 0)
        let result = engine.align(script: script, recognisedText: "next we describe the method", previous: previous)
        XCTAssertEqual(result.tokenIndex, 13)
        XCTAssertNil(result.matchedRange)
    }

    func testGlobalReacquisitionCannotSearchBehindCurrentPosition() {
        let script = ScriptDocument(text: "Crimson falcon circles silent canyon. Middle transition. Silver ocean carries distant lanterns.")
        let previous = AlignmentState(tokenIndex: 7, confidence: 0.2, trackingState: .reacquiring, lowConfidenceUpdates: 2)

        let result = engine.align(
            script: script,
            recognisedText: "crimson falcon circles silent canyon",
            previous: previous,
            isFinal: true
        )

        XCTAssertEqual(result.searchMode, .global)
        XCTAssertEqual(result.tokenIndex, 7)
        XCTAssertNil(result.matchedRange)
    }

    func testForwardSentenceAndParagraphSkipReacquires() {
        let script = ScriptDocument(text: AlignmentFixtures.presentation)
        var state = AlignmentState(tokenIndex: 12, confidence: 0.8, trackingState: .tracking, lowConfidenceUpdates: 0)
        state = engine.align(script: script, recognisedText: "words nowhere in prepared copy", previous: state).state
        state = engine.align(script: script, recognisedText: "still unrelated noisy material", previous: state).state
        let result = engine.align(
            script: script,
            recognisedText: "our next step is to test these ideas with a broader community",
            previous: state
        )
        XCTAssertEqual(result.searchMode, .global)
        XCTAssertTrue((result.tokenIndex ?? 0) > 75)
        XCTAssertEqual(result.trackingState, .tracking)
    }

    func testEmptyAndLowConfidenceRecognitionAreStable() {
        let script = ScriptDocument(text: "A short known script with useful words")
        let previous = AlignmentState(tokenIndex: 3, confidence: 0.8, trackingState: .tracking, lowConfidenceUpdates: 0)
        let empty = engine.align(script: script, recognisedText: "", previous: previous)
        let noise = engine.align(script: script, recognisedText: "zebra quantum pineapple", previous: previous)
        XCTAssertEqual(empty.tokenIndex, 3)
        XCTAssertEqual(noise.tokenIndex, 3)
        XCTAssertNotEqual(noise.trackingState, .tracking)
    }

    func testPartialRecognitionCanTrack() {
        let result = align("FollowScript follows the speaker through a prepared script", speech: "follows the speaker", isFinal: false)
        XCTAssertNotNil(result.tokenIndex)
    }

    func testSingleWordPartialDoesNotPullEstablishedPositionForward() {
        let script = ScriptDocument(text: "analysis and design")
        let previous = AlignmentState(
            tokenIndex: 0,
            confidence: 0.9,
            trackingState: .tracking,
            lowConfidenceUpdates: 0
        )

        let result = engine.align(
            script: script,
            recognisedText: "and",
            previous: previous,
            isFinal: false
        )

        XCTAssertEqual(result.tokenIndex, 0)
        XCTAssertEqual(result.matchedRange, 1...1)
    }

    func testTentativeEstimateCanLeadCommittedScrollPosition() {
        var configuration = ScriptAlignmentEngine.Configuration.standard
        configuration.commitThreshold = 0.99
        let cautiousEngine = ScriptAlignmentEngine(configuration: configuration)
        let script = ScriptDocument(text: "alpha beta gamma delta epsilon zeta")
        let previous = AlignmentState(tokenIndex: 1, confidence: 0.9, trackingState: .tracking, lowConfidenceUpdates: 0)
        let result = cautiousEngine.align(script: script, recognisedText: "gamma delta", previous: previous)

        XCTAssertGreaterThan(result.estimatedTokenIndex ?? 0, result.committedTokenIndex ?? 0)
        XCTAssertNotNil(result.matchedRange)
    }

    func testBeamRetainsMultipleCandidatePositionsForRepeatedLanguage() {
        let script = ScriptDocument(text: "we begin together pause we begin together then finish")
        let result = engine.align(script: script, recognisedText: "we begin together", isFinal: true)

        XCTAssertGreaterThan(result.state.hypotheses.count, 1)
        XCTAssertGreaterThan(Set(result.state.hypotheses.map(\.tokenIndex)).count, 1)
    }

    func testAlternativeHypothesisCanRecoverPrimaryRecognitionError() {
        let script = ScriptDocument(text: "common words then cobalt telescope marks the destination")
        let result = engine.align(
            script: script,
            observations: [
                AlignmentObservation(text: "unrelated primary error", confidence: 0.4),
                AlignmentObservation(text: "cobalt telescope marks the destination", confidence: 0.9)
            ],
            isFinal: true
        )
        XCTAssertEqual(result.committedTokenIndex, 7)
    }

    func testTimingPenalisesImplausibleRapidMovement() {
        let words = (0..<50).map { "token\($0)" }
        let script = ScriptDocument(text: words.joined(separator: " "))
        let previous = AlignmentState(tokenIndex: 2, confidence: 0.9, trackingState: .tracking,
                                      lowConfidenceUpdates: 0, lastObservationTime: 10)
        let result = engine.align(script: script, recognisedText: "token25 token26 token27",
                                  previous: previous, observationTime: 10.1)
        XCTAssertEqual(result.committedTokenIndex, 2)
    }

    func testReplayMetricsReportPositionErrorAndFalseJumps() {
        let script = ScriptDocument(text: "one two three four five six seven eight")
        var state = AlignmentState.initial
        let updates = [("one two", 1), ("one two three four", 3), ("three four five six", 5)]
        let frames = updates.enumerated().map { offset, update -> AlignmentReplayFrame in
            let result = engine.align(script: script, recognisedText: update.0, previous: state,
                                      isFinal: true, observationTime: Double(offset + 1))
            state = result.state
            return AlignmentReplayFrame(expectedTokenIndex: update.1, result: result)
        }
        let metrics = AlignmentReplayMetrics(frames: frames)
        XCTAssertLessThanOrEqual(metrics.meanAbsolutePositionError, 1)
        XCTAssertEqual(metrics.falseJumpCount, 0)
    }

    func testParaphrasedPeoplePhraseDoesNotJumpToAlongTheWay() throws {
        let script = ScriptDocument(text: """
        In CP5046, you’ll work in a team to investigate a user-centred problem and develop an interactive solution through research, prototyping and feedback. You’ll begin with people, not code: learning what users need, testing assumptions and refining your ideas. Along the way, you’ll create prototypes.
        """)
        let feedback = try XCTUnwrap(script.tokens.first { $0.normalised == "feedback" }?.index)
        let people = try XCTUnwrap(script.tokens.first { $0.normalised == "people" }?.index)
        let way = try XCTUnwrap(script.tokens.first { $0.normalised == "way" }?.index)
        let previous = AlignmentState(
            tokenIndex: feedback,
            confidence: 0.9,
            trackingState: .tracking,
            lowConfidenceUpdates: 0
        )

        let result = engine.align(
            script: script,
            recognisedText: "you'll start with people",
            previous: previous,
            isFinal: false
        )

        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.tokenIndex), feedback)
        XCTAssertLessThanOrEqual(try XCTUnwrap(result.tokenIndex), people)
        XCTAssertNotEqual(result.tokenIndex, way)
    }

    func testShortLocalUpdateCannotAuthoriseDistantAdvance() {
        let script = ScriptDocument(text: "current one two three four five six seven eight nine distant phrase")
        let previous = AlignmentState(
            tokenIndex: 0,
            confidence: 0.9,
            trackingState: .tracking,
            lowConfidenceUpdates: 0
        )

        let result = engine.align(
            script: script,
            recognisedText: "distant phrase",
            previous: previous,
            isFinal: false
        )

        XCTAssertEqual(result.tokenIndex, 0)
        XCTAssertNil(result.matchedRange)
    }

    func testSingleWordPartialCannotPrematurelyAnchorSubjectTitle() {
        let script = ScriptDocument(text: "Hello, and welcome to CP5046: ICT Project 1 - Analysis and Design. I’m Jason Holdsworth.")

        let premature = engine.align(
            script: script,
            recognisedText: "and",
            isFinal: false
        )
        XCTAssertNil(premature.tokenIndex)

        let phraseStart = engine.align(
            script: script,
            recognisedText: "analysis and",
            previous: premature.state,
            isFinal: false
        )
        XCTAssertEqual(phraseStart.tokenIndex, 8)
        XCTAssertEqual(phraseStart.matchedRange, 8...9)

        let completedPhrase = engine.align(
            script: script,
            recognisedText: "analysis and design",
            previous: phraseStart.state,
            isFinal: true
        )
        XCTAssertEqual(completedPhrase.tokenIndex, 10)
        XCTAssertEqual(completedPhrase.matchedRange, 8...10)
    }

    func testModeratelySizedSequentialFixtureProgresses() {
        let script = ScriptDocument(text: AlignmentFixtures.presentation)
        var state = AlignmentState.initial
        var positions: [Int] = []
        for fragment in AlignmentFixtures.sequentialRecognition {
            let result = engine.align(script: script, recognisedText: fragment, previous: state, isFinal: true)
            state = result.state
            if let position = result.tokenIndex { positions.append(position) }
        }
        XCTAssertGreaterThan(positions.count, 8)
        XCTAssertTrue(zip(positions, positions.dropFirst()).allSatisfy { $0 <= $1 })
        XCTAssertTrue((positions.last ?? 0) > 100)
    }

    func testLongScriptUsesLocalSearchWhileTracking() {
        let text = (0..<500).map { "word\($0)" }.joined(separator: " ")
        let script = ScriptDocument(text: text)
        let previous = AlignmentState(tokenIndex: 250, confidence: 0.9, trackingState: .tracking, lowConfidenceUpdates: 0)
        let result = engine.align(script: script, recognisedText: "word251 word252 word253 word254", previous: previous)
        XCTAssertEqual(result.searchMode, .local)
        XCTAssertEqual(result.tokenIndex, 253)
    }

    private func align(
        _ script: String,
        speech: String,
        previous: AlignmentState = .initial,
        isFinal: Bool = true
    ) -> AlignmentResult {
        engine.align(script: ScriptDocument(text: script), recognisedText: speech, previous: previous, isFinal: isFinal)
    }
}
