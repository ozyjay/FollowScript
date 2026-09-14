import Foundation

enum AlignmentTrackingState: String, Equatable, Sendable {
    case tracking
    case uncertain
    case reacquiring
}

struct AlignmentState: Equatable, Sendable {
    var estimatedTokenIndex: Int?
    var committedTokenIndex: Int?
    var confidence: Double
    var trackingState: AlignmentTrackingState
    var lowConfidenceUpdates: Int
    var hypotheses: [AlignmentHypothesis]
    var lastObservationTime: TimeInterval?
    var speakingRateTokensPerSecond: Double?

    var tokenIndex: Int? {
        get { committedTokenIndex }
        set { estimatedTokenIndex = newValue; committedTokenIndex = newValue }
    }

    init(tokenIndex: Int?, confidence: Double, trackingState: AlignmentTrackingState, lowConfidenceUpdates: Int,
         estimatedTokenIndex: Int? = nil, hypotheses: [AlignmentHypothesis] = [],
         lastObservationTime: TimeInterval? = nil, speakingRateTokensPerSecond: Double? = nil) {
        self.estimatedTokenIndex = estimatedTokenIndex ?? tokenIndex
        self.committedTokenIndex = tokenIndex
        self.confidence = confidence
        self.trackingState = trackingState
        self.lowConfidenceUpdates = lowConfidenceUpdates
        self.hypotheses = hypotheses
        self.lastObservationTime = lastObservationTime
        self.speakingRateTokensPerSecond = speakingRateTokensPerSecond
    }

    static let initial = AlignmentState(
        tokenIndex: nil,
        confidence: 0,
        trackingState: .reacquiring,
        lowConfidenceUpdates: 0
    )
}

struct AlignmentHypothesis: Equatable, Sendable {
    let tokenIndex: Int
    let score: Double
}

struct AlignmentObservation: Equatable, Sendable {
    let text: String
    let confidence: Double?
    let phoneticTokens: [String]?

    init(text: String, confidence: Double? = nil, phoneticTokens: [String]? = nil) {
        self.text = text; self.confidence = confidence; self.phoneticTokens = phoneticTokens
    }
}

struct AlignmentResult: Equatable, Sendable {
    let estimatedTokenIndex: Int?
    let committedTokenIndex: Int?
    let matchedRange: ClosedRange<Int>?
    let confidence: Double
    let trackingState: AlignmentTrackingState
    let searchMode: SearchMode
    let candidateScore: Double
    let state: AlignmentState

    var tokenIndex: Int? { committedTokenIndex }

    enum SearchMode: String, Equatable, Sendable {
        case local
        case global
    }
}
