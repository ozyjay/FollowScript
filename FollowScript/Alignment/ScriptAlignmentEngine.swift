import Foundation

struct ScriptAlignmentEngine: Sendable {
    struct Configuration: Equatable, Sendable {
        var recognitionWindow = 16
        var localLookAhead = 80
        var localLookBehind = 5
        var lengthTolerance = 4
        var uncertainThreshold = 0.48
        var trackingThreshold = 0.62
        var reacquisitionThreshold = 0.66
        var commitThreshold = 0.64
        var distinctiveJumpThreshold = 0.74
        var updatesBeforeGlobalSearch = 2
        var minimumInitialPartialTokens = 2
        var singleTokenPartialResultLag = 1
        var localAdvanceSlack = 4
        var beamWidth = 7
        var idfStrength = 0.28
        var repetitionPenalty = 0.10
        var skipPenaltyPerToken = 0.012
        var distantJumpPenalty = 0.12
        var minimumCandidateScoreMargin = 0.035
        var ambiguousJumpDistance = 5
        var forwardContinuityBonus = 0.035
        var backwardTransitionPenalty = 0.28
        var defaultSpeakingRate = 2.6
        var timingSlackTokens = 4.0

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
        isFinal: Bool = false,
        observationTime: TimeInterval? = nil
    ) -> AlignmentResult {
        align(script: script, observations: [.init(text: recognisedText)], previous: previous,
              isFinal: isFinal, observationTime: observationTime)
    }

    func align(script: ScriptDocument, observations: [AlignmentObservation], previous: AlignmentState = .initial,
               isFinal: Bool = false, observationTime: TimeInterval? = nil) -> AlignmentResult {
        let alternatives = observations.compactMap { observation -> ([String], Double?)? in
            let tokens = Array(tokenizer.recognitionTokens(observation.text).suffix(configuration.recognitionWindow))
            return tokens.isEmpty ? nil : (tokens, observation.confidence)
        }
        guard let first = alternatives.first else {
            return unchangedResult(previous: previous, observationTime: observationTime, reason: .emptyRecognition)
        }
        let recognised = first.0
        guard !script.tokens.isEmpty, !recognised.isEmpty else {
            return unchangedResult(previous: previous, observationTime: observationTime, reason: .emptyRecognition)
        }
        guard previous.tokenIndex != nil
                || isFinal
                || recognised.count >= configuration.minimumInitialPartialTokens else {
            return unchangedResult(previous: previous, observationTime: observationTime, reason: .awaitingMorePartialTokens)
        }

        let useGlobalSearch = previous.tokenIndex == nil
            || previous.lowConfidenceUpdates >= configuration.updatesBeforeGlobalSearch
            || previous.trackingState == .reacquiring

        let searchMode: AlignmentResult.SearchMode = useGlobalSearch ? .global : .local
        let bounds = searchBounds(scriptCount: script.tokens.count, previous: previous, global: useGlobalSearch)
        let weights = distinctivenessWeights(script.tokens.map(\.normalised))
        let candidates = bestCandidates(
            scriptTokens: script.tokens.map(\.normalised),
            alternatives: alternatives,
            weights: weights,
            endBounds: bounds,
            minimumCandidateStart: previous.tokenIndex ?? 0,
            previousIndex: previous.tokenIndex,
            previousHypotheses: previous.hypotheses,
            global: useGlobalSearch,
            elapsed: elapsed(current: observationTime, previous: previous.lastObservationTime),
            speakingRate: previous.speakingRateTokensPerSecond
        )
        guard let best = candidates.first else {
            return unchangedResult(previous: previous, observationTime: observationTime, reason: .insufficientEvidence)
        }

        let scoreMargin = candidates.dropFirst().first.map { best.score - $0.score }

        let evidence = min(1, Double(Set(recognised).count) / 5.0)
        let finalBoost = isFinal ? 0.03 : 0
        let confidence = min(1, max(0, best.score * (0.62 + 0.38 * evidence) + finalBoost))
        let threshold = useGlobalSearch ? configuration.reacquisitionThreshold : configuration.uncertainThreshold
        let accepted = confidence >= configuration.uncertainThreshold

        let forwardMovement = previous.tokenIndex.map { best.end - $0 }
        let largeJump = forwardMovement.map { $0 > configuration.localLookAhead } ?? false
        let jumpHasEvidence = recognised.count >= 3 && confidence >= configuration.distinctiveJumpThreshold
            && distinctiveCoverage(recognised, scriptTokens: script.tokens.map(\.normalised), weights: weights) >= 0.45
        let exceedsAdvanceBudget = forwardMovement.map {
            $0 > recognised.count + configuration.localAdvanceSlack
        } ?? false
        let exceedsLocalAdvanceBudget = !useGlobalSearch && exceedsAdvanceBudget
        let globalJumpNeedsEvidence = useGlobalSearch && exceedsAdvanceBudget && !jumpHasEvidence
        let ambiguousJump = previous.tokenIndex.map {
            best.end - $0 >= configuration.ambiguousJumpDistance
                && (scoreMargin ?? 1) < configuration.minimumCandidateScoreMargin
        } ?? false
        let estimateAllowed = accepted && !ambiguousJump && !exceedsLocalAdvanceBudget
            && !globalJumpNeedsEvidence
            && (!largeJump || (useGlobalSearch && jumpHasEvidence))
        let estimatedIndex = estimateAllowed
            ? lagged(best.end, recognisedTokenCount: recognised.count, isFinal: isFinal)
            : previous.estimatedTokenIndex
        let mayMove = accepted && !ambiguousJump
            && confidence >= (useGlobalSearch ? threshold : configuration.commitThreshold)
            && !exceedsLocalAdvanceBudget
            && !globalJumpNeedsEvidence
            && (!largeJump || (useGlobalSearch && jumpHasEvidence))
        let selectedIndex: Int?
        if mayMove {
            let laggedIndex = lagged(best.end, recognisedTokenCount: recognised.count, isFinal: isFinal)
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
            lowConfidenceUpdates: lowConfidenceUpdates,
            estimatedTokenIndex: estimatedIndex,
            hypotheses: candidates.map { .init(tokenIndex: $0.end, score: $0.score) },
            lastObservationTime: observationTime ?? previous.lastObservationTime,
            speakingRateTokensPerSecond: updatedRate(previous: previous, committed: selectedIndex, observationTime: observationTime)
        )
        let decisionReason: AlignmentDecisionTrace.Reason
        if !accepted || confidence < (useGlobalSearch ? threshold : configuration.commitThreshold) {
            decisionReason = .insufficientEvidence
        } else if ambiguousJump {
            decisionReason = .ambiguousCandidates
        } else if exceedsLocalAdvanceBudget {
            decisionReason = .localAdvanceTooLarge
        } else if globalJumpNeedsEvidence || (largeJump && !(useGlobalSearch && jumpHasEvidence)) {
            decisionReason = .distantJumpNeedsDistinctiveEvidence
        } else {
            decisionReason = .accepted
        }
        return AlignmentResult(
            estimatedTokenIndex: estimatedIndex,
            committedTokenIndex: selectedIndex,
            matchedRange: estimateAllowed ? best.start...best.end : nil,
            confidence: confidence,
            trackingState: trackingState,
            searchMode: searchMode,
            candidateScore: best.score,
            decisionTrace: AlignmentDecisionTrace(
                candidates: candidates.prefix(3).map { .init(tokenIndex: $0.end, score: $0.score) },
                scoreMargin: scoreMargin,
                decision: mayMove ? .advance : .hold,
                reason: decisionReason
            ),
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

    private func bestCandidates(
        scriptTokens: [String],
        alternatives: [([String], Double?)],
        weights: [Double],
        endBounds: ClosedRange<Int>,
        minimumCandidateStart: Int,
        previousIndex: Int?,
        previousHypotheses: [AlignmentHypothesis],
        global: Bool,
        elapsed: Double?,
        speakingRate: Double?
    ) -> [Candidate] {
        let recognised = alternatives[0].0
        var candidates: [Candidate] = []
        let minimumLength = max(1, recognised.count - configuration.lengthTolerance)
        let maximumLength = recognised.count + configuration.lengthTolerance

        for end in endBounds {
            for length in minimumLength...maximumLength {
                let start = end - length + 1
                guard start >= minimumCandidateStart else { continue }
                let scriptSlice = Array(scriptTokens[start...end])
                let sliceWeights = Array(weights[start...end])
                var score = alternatives.enumerated().map { offset, alternative in
                    similarity(alternative.0, scriptSlice, weights: sliceWeights)
                        * (alternative.1 ?? (offset == 0 ? 1 : 0.8))
                }.max() ?? 0
                if let previousIndex {
                    let parents = previousHypotheses.isEmpty
                        ? [AlignmentHypothesis(tokenIndex: previousIndex, score: 1)]
                        : previousHypotheses
                    let pathScore = parents.map { parent in
                        0.16 * transitionScore(
                            delta: end - parent.tokenIndex,
                            elapsed: elapsed,
                            speakingRate: speakingRate,
                            global: global
                        ) + 0.04 * parent.score
                    }.max() ?? 0
                    score = 0.80 * score + pathScore
                    if end > previousIndex, end - previousIndex <= recognised.count + 1 {
                        score += configuration.forwardContinuityBonus
                    }
                }
                let candidate = Candidate(start: start, end: end, score: min(1, max(0, score)))
                candidates.append(candidate)
            }
        }
        let bestPerPosition = Dictionary(grouping: candidates, by: \.end).compactMap { _, values in
            values.max { $0.score < $1.score }
        }
        return Array(bestPerPosition.sorted { $0.score > $1.score }.prefix(configuration.beamWidth))
    }

    private func similarity(_ lhs: [String], _ rhs: [String], weights: [Double]) -> Double {
        let maximum = max(lhs.count, rhs.count)
        guard maximum > 0 else { return 0 }
        let edit = 1 - Double(editDistance(lhs, rhs)) / Double(maximum)
        let lcs = Double(longestCommonSubsequence(lhs, rhs)) / Double(maximum)
        let orderedCoverage = Double(longestCommonSubsequence(lhs, rhs)) / Double(max(1, lhs.count))
        let lhsSet = Set(lhs)
        let total = max(0.001, weights.reduce(0, +))
        let distinctive = zip(rhs, weights).reduce(0.0) { $0 + (lhsSet.contains($1.0) ? $1.1 : 0) } / total
        return 0.38 * edit + 0.25 * lcs + 0.17 * orderedCoverage + 0.20 * distinctive
    }

    private func distinctivenessWeights(_ tokens: [String]) -> [Double] {
        var counts: [String: Int] = [:]; tokens.forEach { counts[$0, default: 0] += 1 }
        let total = Double(max(1, tokens.count))
        return tokens.map { 1 + configuration.idfStrength * log((total + 1) / Double((counts[$0] ?? 1) + 1)) }
    }

    private func distinctiveCoverage(_ recognised: [String], scriptTokens: [String], weights: [Double]) -> Double {
        let words = Set(recognised); let maximum = weights.max() ?? 1
        return zip(scriptTokens, weights).filter { words.contains($0.0) }.map(\.1).max().map { $0 / maximum } ?? 0
    }

    private func transitionScore(delta: Int, elapsed: Double?, speakingRate: Double?, global: Bool) -> Double {
        if delta < 0 {
            return max(0, 0.70 - configuration.backwardTransitionPenalty
                - Double(abs(delta)) * configuration.repetitionPenalty)
        }
        if delta == 0 { return 0.94 }
        var penalty = Double(max(0, delta - 1)) * configuration.skipPenaltyPerToken
        if let elapsed {
            let expected = elapsed * (speakingRate ?? configuration.defaultSpeakingRate)
            penalty += max(0, Double(delta) - expected - configuration.timingSlackTokens) * configuration.skipPenaltyPerToken
        }
        if global && delta > configuration.localLookAhead { penalty += configuration.distantJumpPenalty }
        return max(0, 0.96 - penalty)
    }

    private func lagged(_ index: Int, recognisedTokenCount: Int, isFinal: Bool) -> Int {
        let lag = !isFinal && recognisedTokenCount == 1 ? configuration.singleTokenPartialResultLag : 0
        return max(0, index - lag)
    }
    private func elapsed(current: TimeInterval?, previous: TimeInterval?) -> Double? {
        guard let current, let previous, current >= previous else { return nil }; return min(10, current - previous)
    }
    private func updatedRate(previous: AlignmentState, committed: Int?, observationTime: TimeInterval?) -> Double? {
        guard let oldIndex = previous.committedTokenIndex, let committed, committed >= oldIndex,
              let interval = elapsed(current: observationTime, previous: previous.lastObservationTime), interval > 0 else {
            return previous.speakingRateTokensPerSecond
        }
        let observed = min(5.5, max(1, Double(committed - oldIndex) / interval))
        return previous.speakingRateTokensPerSecond.map { 0.8 * $0 + 0.2 * observed } ?? observed
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

    private func unchangedResult(
        previous: AlignmentState,
        observationTime: TimeInterval?,
        reason: AlignmentDecisionTrace.Reason
    ) -> AlignmentResult {
        let lowConfidenceUpdates = previous.lowConfidenceUpdates + 1
        return AlignmentResult(
            estimatedTokenIndex: previous.estimatedTokenIndex,
            committedTokenIndex: previous.committedTokenIndex,
            matchedRange: nil,
            confidence: 0,
            trackingState: previous.tokenIndex == nil ? .reacquiring : .uncertain,
            searchMode: previous.trackingState == .reacquiring ? .global : .local,
            candidateScore: 0,
            decisionTrace: AlignmentDecisionTrace(
                candidates: [],
                scoreMargin: nil,
                decision: .hold,
                reason: reason
            ),
            state: AlignmentState(
                tokenIndex: previous.tokenIndex,
                confidence: 0,
                trackingState: previous.tokenIndex == nil ? .reacquiring : .uncertain,
                lowConfidenceUpdates: lowConfidenceUpdates,
                estimatedTokenIndex: previous.estimatedTokenIndex,
                hypotheses: previous.hypotheses,
                lastObservationTime: observationTime ?? previous.lastObservationTime,
                speakingRateTokensPerSecond: previous.speakingRateTokensPerSecond
            )
        )
    }
}
