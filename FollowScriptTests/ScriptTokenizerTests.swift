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

    func testEmptyAndShortScripts() {
        XCTAssertTrue(tokenizer.tokenise(" \n ").isEmpty)
        XCTAssertEqual(tokenizer.tokenise("Go!").first?.displayText, "Go!")
    }
}
