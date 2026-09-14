import Foundation

struct ScriptAlignmentEngine: Sendable {
    struct Configuration: Equatable, Sendable {
        var recognitionWindow = 16
        var localLookAhead = 80
        var lengthTolerance = 4
        var uncertainThreshold = 0.48
        var trackingThreshold = 0.62
        var reacquisitionThreshold = 0.66
        var updatesBeforeGlobalSearch = 2
        var minimumInitialPartialTokens = 2
        var partialResultTokenLag = 1

        static let standard = Configuration()
    }

    private let configuration: Configuration
    private let tokenizer = ScriptTokenizer()

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    func align(
        script: ScriptDocument,
        recognisedText: String,
        previous: AlignmentState = .initial,
        isFinal: Bool = false
    ) -> AlignmentResult {
        let allRecognitionTokens = tokenizer.recognitionTokens(recognisedText)
        let recognised = Array(allRecognitionTokens.suffix(configuration.recognitionWindow))
        guard !script.tokens.isEmpty, !recognised.isEmpty else {
            return unchangedResult(previous: previous)
        }
        guard previous.tokenIndex != nil
                || isFinal
                || recognised.count >= configuration.minimumInitialPartialTokens else {
            return unchangedResult(previous: previous)
        }

        let useGlobalSearch = previous.tokenIndex == nil
            || previous.lowConfidenceUpdates >= configuration.updatesBeforeGlobalSearch
            || previous.trackingState == .reacquiring

        let searchMode: AlignmentResult.SearchMode = useGlobalSearch ? .global : .local
        let bounds = searchBounds(scriptCount: script.tokens.count, previous: previous, global: useGlobalSearch)
        let best = bestCandidate(
            scriptTokens: script.tokens.map(\.normalised),
            recognised: recognised,
            endBounds: bounds,
            minimumCandidateStart: previous.tokenIndex ?? 0,
            previousIndex: previous.tokenIndex,
            global: useGlobalSearch
        )

        guard let best else { return unchangedResult(previous: previous) }

        let evidence = min(1, Double(Set(recognised).count) / 5.0)
        let finalBoost = isFinal ? 0.03 : 0
        let confidence = min(1, max(0, best.score * (0.62 + 0.38 * evidence) + finalBoost))
        let threshold = useGlobalSearch ? configuration.reacquisitionThreshold : configuration.uncertainThreshold
        let accepted = confidence >= threshold

        let largeJump = previous.tokenIndex.map { abs(best.end - $0) > configuration.localLookAhead } ?? false
        let jumpHasEvidence = recognised.count >= 3 && confidence >= configuration.reacquisitionThreshold
        let mayMove = accepted && (!largeJump || (useGlobalSearch && jumpHasEvidence))
        let selectedIndex: Int?
        if mayMove {
            let lag = isFinal ? 0 : configuration.partialResultTokenLag
            let laggedIndex = max(0, best.end - lag)
            selectedIndex = max(previous.tokenIndex ?? laggedIndex, laggedIndex)
        } else {
            selectedIndex = previous.tokenIndex
        }
        let lowConfidenceUpdates = mayMove ? 0 : previous.lowConfidenceUpdates + 1
        let trackingState: AlignmentTrackingState
        if mayMove && confidence >= configuration.trackingThreshold {
            trackingState = .tracking
        } else if lowConfidenceUpdates >= configuration.updatesBeforeGlobalSearch {
            trackingState = .reacquiring
        } else {
            trackingState = .uncertain
        }

        let state = AlignmentState(
            tokenIndex: selectedIndex,
            confidence: confidence,
            trackingState: trackingState,
            lowConfidenceUpdates: lowConfidenceUpdates
        )
        return AlignmentResult(
            tokenIndex: selectedIndex,
            matchedRange: mayMove ? best.start...best.end : nil,
            confidence: confidence,
            trackingState: trackingState,
            searchMode: searchMode,
            candidateScore: best.score,
            state: state
        )
    }

    private func searchBounds(
        scriptCount: Int,
        previous: AlignmentState,
        global: Bool
    ) -> ClosedRange<Int> {
        guard let index = previous.tokenIndex else { return 0...(scriptCount - 1) }
        let upperBound = global
            ? scriptCount - 1
            : min(scriptCount - 1, index + configuration.localLookAhead)
        return index...upperBound
    }

    private struct Candidate {
        let start: Int
        let end: Int
        let score: Double
    }

    private func bestCandidate(
        scriptTokens: [String],
        recognised: [String],
        endBounds: ClosedRange<Int>,
        minimumCandidateStart: Int,
        previousIndex: Int?,
        global: Bool
    ) -> Candidate? {
        var best: Candidate?
        let minimumLength = max(1, recognised.count - configuration.lengthTolerance)
        let maximumLength = recognised.count + configuration.lengthTolerance

        for end in endBounds {
            for length in minimumLength...maximumLength {
                let start = end - length + 1
                guard start >= minimumCandidateStart else { continue }
                let scriptSlice = Array(scriptTokens[start...end])
                var score = similarity(recognised, scriptSlice)
                if let previousIndex {
                    let delta = end - previousIndex
                    if delta <= configuration.localLookAhead {
                        score += 0.10 * (1 - min(1, Double(delta) / Double(configuration.localLookAhead)))
                    }
                    if global && delta > configuration.localLookAhead { score -= 0.03 }
                }
                let candidate = Candidate(start: start, end: end, score: min(1, max(0, score)))
                if let currentBest = best {
                    if candidate.score > currentBest.score { best = candidate }
                } else {
                    best = candidate
                }
            }
        }
        return best
    }

    private func similarity(_ lhs: [String], _ rhs: [String]) -> Double {
        let maximum = max(lhs.count, rhs.count)
        guard maximum > 0 else { return 0 }
        let edit = 1 - Double(editDistance(lhs, rhs)) / Double(maximum)
        let lcs = Double(longestCommonSubsequence(lhs, rhs)) / Double(maximum)
        let orderedCoverage = Double(longestCommonSubsequence(lhs, rhs)) / Double(max(1, lhs.count))
        return 0.50 * edit + 0.30 * lcs + 0.20 * orderedCoverage
    }

    private func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        var previous = Array(0...rhs.count)
        for (leftIndex, left) in lhs.enumerated() {
            var current = [leftIndex + 1] + Array(repeating: 0, count: rhs.count)
            for (rightIndex, right) in rhs.enumerated() {
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + (left == right ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private func longestCommonSubsequence(_ lhs: [String], _ rhs: [String]) -> Int {
        var previous = Array(repeating: 0, count: rhs.count + 1)
        for left in lhs {
            var current = Array(repeating: 0, count: rhs.count + 1)
            for (index, right) in rhs.enumerated() {
                current[index + 1] = left == right
                    ? previous[index] + 1
                    : max(previous[index + 1], current[index])
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private func unchangedResult(previous: AlignmentState) -> AlignmentResult {
        AlignmentResult(
            tokenIndex: previous.tokenIndex,
            matchedRange: nil,
            confidence: 0,
            trackingState: previous.tokenIndex == nil ? .reacquiring : .uncertain,
            searchMode: previous.trackingState == .reacquiring ? .global : .local,
            candidateScore: 0,
            state: AlignmentState(
                tokenIndex: previous.tokenIndex,
                confidence: 0,
                trackingState: previous.tokenIndex == nil ? .reacquiring : .uncertain,
                lowConfidenceUpdates: previous.lowConfidenceUpdates + 1
            )
        )
    }
}
