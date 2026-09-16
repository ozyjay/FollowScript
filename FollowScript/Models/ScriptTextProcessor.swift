import Foundation

enum ScriptTextProcessor {
    static func prepare(
        _ source: String,
        ignoringSquareBracketedText: Bool,
        removingExtraWhitespace: Bool = false
    ) -> String {
        let prepared = ignoringSquareBracketedText
            ? removingSquareBracketedText(from: source)
            : source

        guard removingExtraWhitespace else { return prepared }
        let collapsed = prepared
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return insertingMissingSentenceSpaces(in: collapsed)
    }

    private static func removingSquareBracketedText(from source: String) -> String {

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

    /// Adds the conventional separator where a sentence-ending period is immediately
    /// followed by an uppercase letter. Existing whitespace has already been collapsed.
    /// Requiring an uppercase letter avoids splitting decimals, filenames and abbreviations.
    private static func insertingMissingSentenceSpaces(in text: String) -> String {
        var result = ""
        var previousCharacter: Character?

        for character in text {
            if previousCharacter == ".", character.isUppercase {
                result.append(" ")
            }
            result.append(character)
            previousCharacter = character
        }
        return result
    }
}
