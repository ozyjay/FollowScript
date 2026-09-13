import Foundation

struct FollowScriptSettings: Codable, Equatable, Sendable {
    enum TextAlignmentOption: String, Codable, CaseIterable, Identifiable, Sendable {
        case leading
        case centre

        var id: String { rawValue }
        var title: String { self == .leading ? "Left" : "Centre" }
    }

    var fontSize: Double = 42
    var lineSpacing: Double = 12
    var textAlignment: TextAlignmentOption = .leading
    var highlightsActivePhrase = true
    var mirrorsPrompt = false

    private enum CodingKeys: String, CodingKey {
        case fontSize
        case lineSpacing
        case textAlignment
        case highlightsActivePhrase
        case mirrorsPrompt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 42
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 12
        textAlignment = try container.decodeIfPresent(TextAlignmentOption.self, forKey: .textAlignment) ?? .leading
        highlightsActivePhrase = try container.decodeIfPresent(Bool.self, forKey: .highlightsActivePhrase) ?? true
        mirrorsPrompt = try container.decodeIfPresent(Bool.self, forKey: .mirrorsPrompt) ?? false
    }
}
