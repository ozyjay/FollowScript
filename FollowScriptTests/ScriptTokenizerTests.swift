import XCTest
#if SWIFT_PACKAGE
@testable import FollowScriptCore
#else
@testable import FollowScript
#endif

final class ScriptTokenizerTests: XCTestCase {
    private let tokenizer = ScriptTokenizer()

    func testTokenisationPreservesSourceMappingAndParagraphs() {
        let source = "Hello, world!\n\nIt’s time."
        let tokens = tokenizer.tokenise(source)

        XCTAssertEqual(tokens.map(\.original), ["Hello", "world", "It’s", "time"])
        XCTAssertEqual(tokens.map(\.normalised), ["hello", "world", "its", "time"])
        XCTAssertEqual(tokens.map(\.paragraph), [0, 0, 1, 1])
        for token in tokens {
            let range = Range(token.sourceRange, in: source)
            XCTAssertNotNil(range)
            if let range { XCTAssertEqual(String(source[range]), token.original) }
        }
        XCTAssertEqual(tokens.map(\.displayText).joined(), source)
    }

    func testNormalisationHandlesCasePunctuationDiacriticsAndApostrophes() {
        XCTAssertEqual(ScriptTokenizer.normalise("DON’T"), "dont")
        XCTAssertEqual(ScriptTokenizer.normalise("résumé"), "resume")
        XCTAssertEqual(tokenizer.recognitionTokens("Um, hello... UH world"), ["hello", "world"])
    }

    func testAllPunctuationSeparatesWordsWithoutBecomingMatchableContent() {
        let punctuated = "alpha-beta:gamma/delta;epsilon—zeta…eta¿theta¡iota (kappa) [lambda] {mu}"

        XCTAssertEqual(
            tokenizer.recognitionTokens(punctuated),
            ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu"]
        )
    }

    func testEmptyAndShortScripts() {
        XCTAssertTrue(tokenizer.tokenise(" \n ").isEmpty)
        XCTAssertEqual(tokenizer.tokenise("Go!").first?.displayText, "Go!")
    }

    func testSquareBracketedPlaceholdersCanBeRemovedBeforeTokenisation() {
        let source = "Start [camera direction [wide shot]\ncontinues] speaking now."
        let prepared = ScriptTextProcessor.prepare(source, ignoringSquareBracketedText: true)

        XCTAssertEqual(tokenizer.tokenise(prepared).map(\.normalised), ["start", "speaking", "now"])
        XCTAssertFalse(prepared.contains("camera direction"))
        XCTAssertTrue(prepared.contains("\n"))
    }

    func testSquareBracketedTextCanRemainPartOfScript() {
        let source = "Start [placeholder words] speaking."
        let prepared = ScriptTextProcessor.prepare(source, ignoringSquareBracketedText: false)

        XCTAssertEqual(prepared, source)
        XCTAssertEqual(
            tokenizer.tokenise(prepared).map(\.normalised),
            ["start", "placeholder", "words", "speaking"]
        )
    }

    func testUnmatchedOpeningBracketDoesNotHideRemainder() {
        let source = "Keep [this unfinished instruction"

        XCTAssertEqual(
            ScriptTextProcessor.prepare(source, ignoringSquareBracketedText: true),
            source
        )
    }

    func testExtraWhitespaceCanBeCollapsedForPrompting() {
        let source = "  First   line.\n\n\nSecond\tline.  "

        XCTAssertEqual(
            ScriptTextProcessor.prepare(
                source,
                ignoringSquareBracketedText: false,
                removingExtraWhitespace: true
            ),
            "First line. Second line."
        )
    }

    func testPromptingUsesOneSpaceAfterSentencePeriods() {
        let source = "First sentence.Second sentence.   Third sentence costs $3.50."

        XCTAssertEqual(
            ScriptTextProcessor.prepare(
                source,
                ignoringSquareBracketedText: false,
                removingExtraWhitespace: true
            ),
            "First sentence. Second sentence. Third sentence costs $3.50."
        )
    }

    func testExtraWhitespaceCanBePreservedForPrompting() {
        let source = "First line.\n\nSecond line."

        XCTAssertEqual(
            ScriptTextProcessor.prepare(
                source,
                ignoringSquareBracketedText: false,
                removingExtraWhitespace: false
            ),
            source
        )
    }
}
