import Foundation

/// Reconstructs a short rolling recognition context from time-ranged streaming ASR results.
///
/// SpeechTranscriber can emit multiple volatile revisions for the same audio range and later
/// emit separate finalised phrases. The assembler replaces overlapping volatile revisions,
/// preserves finalised segments, and returns chronological context for deterministic alignment.
struct SpeechRecognitionSegmentAssembler: Sendable {
    struct Output: Equatable, Sendable {
        let text: String
        let alternatives: [String]
        let audioTimeRange: Range<TimeInterval>?
    }

    private struct Segment: Sendable {
        let id: UInt64
        let text: String
        let range: Range<TimeInterval>
        var isFinal: Bool
    }

    private static let maximumRetainedSegments = 32
    private static let timeEpsilon = 0.001

    private var segments: [Segment] = []
    private var nextID: UInt64 = 0

    mutating func reset() {
        segments.removeAll(keepingCapacity: true)
        nextID = 0
    }

    mutating func ingest(
        text rawText: String,
        alternatives rawAlternatives: [String] = [],
        audioTimeRange: Range<TimeInterval>?,
        isFinal: Bool,
        finalizationTime: TimeInterval? = nil
    ) -> Output {
        let text = normalisedSpacing(rawText)
        guard let audioTimeRange,
              audioTimeRange.lowerBound.isFinite,
              audioTimeRange.upperBound.isFinite,
              audioTimeRange.upperBound >= audioTimeRange.lowerBound,
              !text.isEmpty else {
            return Output(
                text: text,
                alternatives: rawAlternatives.map(normalisedSpacing).filter { !$0.isEmpty },
                audioTimeRange: audioTimeRange
            )
        }

        markFinalisedSegments(through: finalizationTime)

        if isFinal {
            segments.removeAll { rangesOverlap($0.range, audioTimeRange) }
        } else {
            segments.removeAll { !$0.isFinal && rangesOverlap($0.range, audioTimeRange) }
        }

        let isCoveredByFinalSegment = !isFinal && segments.contains {
            $0.isFinal && range($0.range, contains: audioTimeRange)
        }

        var insertedID: UInt64?
        if !isCoveredByFinalSegment {
            nextID &+= 1
            insertedID = nextID
            segments.append(
                Segment(
                    id: nextID,
                    text: text,
                    range: audioTimeRange,
                    isFinal: isFinal
                )
            )
        }

        markFinalisedSegments(through: finalizationTime)
        segments.sort {
            if $0.range.lowerBound == $1.range.lowerBound {
                return $0.range.upperBound < $1.range.upperBound
            }
            return $0.range.lowerBound < $1.range.lowerBound
        }
        if segments.count > Self.maximumRetainedSegments {
            segments.removeFirst(segments.count - Self.maximumRetainedSegments)
        }

        let assembledText = joinedText(replacing: nil, with: nil)
        let assembledAlternatives: [String]
        if let insertedID {
            assembledAlternatives = rawAlternatives.compactMap { alternative in
                let replacement = normalisedSpacing(alternative)
                guard !replacement.isEmpty else { return nil }
                return joinedText(replacing: insertedID, with: replacement)
            }
        } else {
            assembledAlternatives = []
        }

        let contextRange = segments.first.flatMap { first in
            segments.last.map { first.range.lowerBound..<$0.range.upperBound }
        }
        return Output(
            text: assembledText,
            alternatives: assembledAlternatives,
            audioTimeRange: contextRange
        )
    }

    private mutating func markFinalisedSegments(through finalizationTime: TimeInterval?) {
        guard let finalizationTime, finalizationTime.isFinite else { return }
        for index in segments.indices where segments[index].range.upperBound <= finalizationTime + Self.timeEpsilon {
            segments[index].isFinal = true
        }
    }

    private func joinedText(replacing segmentID: UInt64?, with replacement: String?) -> String {
        segments.map { segment in
            if segment.id == segmentID, let replacement {
                return replacement
            }
            return segment.text
        }.joined(separator: " ")
    }

    private func rangesOverlap(_ lhs: Range<TimeInterval>, _ rhs: Range<TimeInterval>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    private func range(_ outer: Range<TimeInterval>, contains inner: Range<TimeInterval>) -> Bool {
        outer.lowerBound <= inner.lowerBound + Self.timeEpsilon
            && outer.upperBound + Self.timeEpsilon >= inner.upperBound
    }

    private func normalisedSpacing(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
