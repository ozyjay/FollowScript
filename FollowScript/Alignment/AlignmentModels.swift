import Foundation

enum AlignmentTrackingState: String, Equatable, Sendable {
    case tracking
    case uncertain
    case reacquiring
}

struct AlignmentState: Equatable, Sendable {
    var tokenIndex: Int?
    var confidence: Double
    var trackingState: AlignmentTrackingState
    var lowConfidenceUpdates: Int

    static let initial = AlignmentState(
        tokenIndex: nil,
        confidence: 0,
        trackingState: .reacquiring,
        lowConfidenceUpdates: 0
    )
}

struct AlignmentResult: Equatable, Sendable {
    let tokenIndex: Int?
    let matchedRange: ClosedRange<Int>?
    let confidence: Double
    let trackingState: AlignmentTrackingState
    let searchMode: SearchMode
    let candidateScore: Double
    let state: AlignmentState

    enum SearchMode: String, Equatable, Sendable {
        case local
        case global
    }
}
