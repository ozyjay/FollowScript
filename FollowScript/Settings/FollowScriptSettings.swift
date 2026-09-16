import Foundation
import UIKit

struct FollowScriptSettings: Codable, Equatable, Sendable {
    enum TextAlignmentOption: String, Codable, CaseIterable, Identifiable, Sendable {
        case leading
        case centre

        var id: String { rawValue }
        var title: String { self == .leading ? "Left" : "Centre" }
    }

    enum VideoPromptPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
        case automatic
        case top
        case leading
        case trailing

        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .top: "Top"
            case .leading: "Left"
            case .trailing: "Right"
            }
        }

        func resolved(isLandscape: Bool, orientation: UIInterfaceOrientation) -> VideoPromptPlacement {
            guard self == .automatic else { return self }
            guard isLandscape else { return .top }
            return orientation == .landscapeLeft ? .trailing : .leading
        }
    }

    enum VideoFrameRate: String, Codable, CaseIterable, Identifiable, Sendable {
        case automatic
        case fps24
        case fps25
        case fps30
        case fps50
        case fps60

        var id: String { rawValue }
        var framesPerSecond: Int? {
            switch self {
            case .automatic: nil
            case .fps24: 24
            case .fps25: 25
            case .fps30: 30
            case .fps50: 50
            case .fps60: 60
            }
        }
        var title: String { framesPerSecond.map { "\($0) fps" } ?? "Automatic" }
    }

    enum VideoFocusMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case cameraDefault
        case continuous
        case locked

        var id: String { rawValue }
        var title: String {
            switch self {
            case .cameraDefault: "Camera default"
            case .continuous: "Continuous autofocus"
            case .locked: "Lock focus"
            }
        }
    }

    var videoPromptPlacement: VideoPromptPlacement = .automatic
    var videoFrameRate: VideoFrameRate = .automatic
    var videoFocusMode: VideoFocusMode = .cameraDefault
    var enhancesRecordedVoice = false
    var lastPresentationMode: PresentationMode = .teleprompter
    var fontSize: Double = 42
    var lineSpacing: Double = 12
    var textAlignment: TextAlignmentOption = .leading
    var highlightsActivePhrase = true
    var centresHighlightedText = true
    var mirrorsPrompt = false
    var flipsPromptVertically = false
    var keepsDisplayAwake = false
    var logsTimestampedTrackingInformation = false
    var ignoresSquareBracketedText = true
    var removesExtraWhitespace = true

    private enum CodingKeys: String, CodingKey {
        case videoPromptPlacement
        case videoFrameRate
        case videoFocusMode
        case enhancesRecordedVoice
        case lastPresentationMode
        case fontSize
        case lineSpacing
        case textAlignment
        case highlightsActivePhrase
        case centresHighlightedText
        case mirrorsPrompt
        case flipsPromptVertically
        case keepsDisplayAwake
        case logsTimestampedTrackingInformation
        case ignoresSquareBracketedText
        case removesExtraWhitespace
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videoPromptPlacement = try container.decodeIfPresent(VideoPromptPlacement.self, forKey: .videoPromptPlacement) ?? .automatic
        videoFrameRate = try container.decodeIfPresent(VideoFrameRate.self, forKey: .videoFrameRate) ?? .automatic
        videoFocusMode = try container.decodeIfPresent(VideoFocusMode.self, forKey: .videoFocusMode) ?? .cameraDefault
        enhancesRecordedVoice = try container.decodeIfPresent(Bool.self, forKey: .enhancesRecordedVoice) ?? false
        lastPresentationMode = try container.decodeIfPresent(PresentationMode.self, forKey: .lastPresentationMode) ?? .teleprompter
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 42
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 12
        textAlignment = try container.decodeIfPresent(TextAlignmentOption.self, forKey: .textAlignment) ?? .leading
        highlightsActivePhrase = try container.decodeIfPresent(Bool.self, forKey: .highlightsActivePhrase) ?? true
        centresHighlightedText = try container.decodeIfPresent(Bool.self, forKey: .centresHighlightedText) ?? true
        mirrorsPrompt = try container.decodeIfPresent(Bool.self, forKey: .mirrorsPrompt) ?? false
        flipsPromptVertically = try container.decodeIfPresent(Bool.self, forKey: .flipsPromptVertically) ?? false
        keepsDisplayAwake = try container.decodeIfPresent(Bool.self, forKey: .keepsDisplayAwake) ?? false
        logsTimestampedTrackingInformation = try container.decodeIfPresent(
            Bool.self,
            forKey: .logsTimestampedTrackingInformation
        ) ?? false
        ignoresSquareBracketedText = try container.decodeIfPresent(
            Bool.self,
            forKey: .ignoresSquareBracketedText
        ) ?? true
        removesExtraWhitespace = try container.decodeIfPresent(
            Bool.self,
            forKey: .removesExtraWhitespace
        ) ?? true
    }
}
