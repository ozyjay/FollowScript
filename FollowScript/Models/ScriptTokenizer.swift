import Foundation

struct ScriptTokenizer: Sendable {
    private static let fillers: Set<String> = ["ah", "erm", "hmm", "like", "uh", "um"]

    func tokenise(_ source: String, excludingFillers: Bool = false) -> [ScriptToken] {
        let expression = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"#)
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = expression?.matches(in: source, range: fullRange) ?? []

        var paragraph = 0
        var previousEnd = 0
        var tokens: [ScriptToken] = []

        for (matchIndex, match) in matches.enumerated() {
            if match.range.location > previousEnd {
                let gapRange = NSRange(location: previousEnd, length: match.range.location - previousEnd)
                if let range = Range(gapRange, in: source), source[range].contains("\n") {
                    paragraph += 1
                }
            }
            guard let range = Range(match.range, in: source) else { continue }
            let original = String(source[range])
            let displayEnd = matchIndex + 1 < matches.count ? matches[matchIndex + 1].range.location : source.utf16.count
            let displayRange = NSRange(location: match.range.location, length: displayEnd - match.range.location)
            let displayText = Range(displayRange, in: source).map { String(source[$0]) } ?? original
            let normalised = Self.normalise(original)
            previousEnd = NSMaxRange(match.range)
            guard !normalised.isEmpty,
                  !excludingFillers || !Self.fillers.contains(normalised) else { continue }
            tokens.append(
                ScriptToken(
                    index: tokens.count,
                    original: original,
                    displayText: displayText,
                    normalised: normalised,
                    sourceRange: match.range,
                    paragraph: paragraph
                )
            )
        }
        return tokens
    }

    func recognitionTokens(_ text: String) -> [String] {
        tokenise(text, excludingFillers: true).map(\.normalised)
    }

    static func normalise(_ token: String) -> String {
        token
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'", with: "")
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
    }
}
