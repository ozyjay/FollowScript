import Foundation

struct AlignmentReplayFrame: Equatable, Sendable {
    let expectedTokenIndex: Int
    let result: AlignmentResult
}

struct AlignmentReplayMetrics: Equatable, Sendable {
    let meanAbsolutePositionError: Double
    let maximumAbsolutePositionError: Int
    let falseJumpCount: Int
    let reacquisitionUpdateCount: Int

    init(frames: [AlignmentReplayFrame], falseJumpDistance: Int = 20) {
        guard !frames.isEmpty else {
            meanAbsolutePositionError = 0
            maximumAbsolutePositionError = 0
            falseJumpCount = 0
            reacquisitionUpdateCount = 0
            return
        }
        let errors = frames.map { abs(($0.result.estimatedTokenIndex ?? 0) - $0.expectedTokenIndex) }
        meanAbsolutePositionError = Double(errors.reduce(0, +)) / Double(errors.count)
        maximumAbsolutePositionError = errors.max() ?? 0
        falseJumpCount = zip(frames, frames.dropFirst()).filter { previous, current in
            guard let previousIndex = previous.result.committedTokenIndex,
                  let currentIndex = current.result.committedTokenIndex else { return false }
            return currentIndex - previousIndex >= falseJumpDistance
                && current.expectedTokenIndex - previous.expectedTokenIndex < falseJumpDistance
        }.count
        reacquisitionUpdateCount = frames.filter { $0.result.trackingState == .reacquiring }.count
    }
}
