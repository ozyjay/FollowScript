import Foundation

struct ScriptDocument: Equatable, Sendable {
    let text: String
    let tokens: [ScriptToken]

    init(text: String, tokenizer: ScriptTokenizer = ScriptTokenizer()) {
        self.text = text
        self.tokens = tokenizer.tokenise(text)
    }

    var isEmpty: Bool { tokens.isEmpty }
}

struct ScriptToken: Identifiable, Equatable, Hashable, Sendable {
    let index: Int
    let original: String
    let displayText: String
    let normalised: String
    let sourceRange: NSRange
    let paragraph: Int

    var id: Int { index }
}
