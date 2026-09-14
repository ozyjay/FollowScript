import Foundation

enum ScriptTextProcessor {
    static func prepare(_ source: String, ignoringSquareBracketedText: Bool) -> String {
        guard ignoringSquareBracketedText else { return source }

        var result = ""
        var bracketedText = ""
        var depth = 0

        for character in source {
            if character == "[" {
                if depth == 0 { bracketedText = "[" }
                else { bracketedText.append(character) }
                depth += 1
            } else if character == "]", depth > 0 {
                bracketedText.append(character)
                depth -= 1
                if depth == 0 {
                    appendPlaceholderSpacing(from: bracketedText, to: &result)
                    bracketedText = ""
                }
            } else if depth > 0 {
                bracketedText.append(character)
            } else {
                result.append(character)
            }
        }

        // An unmatched opening bracket is ordinary script text rather than authority to
        // hide everything that follows it.
        result.append(bracketedText)
        return result
    }

    private static func appendPlaceholderSpacing(from removedText: String, to result: inout String) {
        if result.last?.isWhitespace != true { result.append(" ") }
        for character in removedText where character.isNewline {
            result.append(character)
        }
        if result.last?.isWhitespace != true { result.append(" ") }
    }
}
