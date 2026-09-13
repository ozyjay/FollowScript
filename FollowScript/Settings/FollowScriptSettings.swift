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
}
