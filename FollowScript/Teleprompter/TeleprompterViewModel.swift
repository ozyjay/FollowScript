import Foundation
import Combine

@MainActor
final class TeleprompterViewModel: ObservableObject {
    let script: ScriptDocument
    @Published private(set) var alignmentState = AlignmentState.initial
    @Published private(set) var recognisedText = ""
    @Published private(set) var matchedRange: ClosedRange<Int>?
    @Published private(set) var searchMode: AlignmentResult.SearchMode = .global
    @Published private(set) var candidateScore = 0.0
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var scrollTarget: Int?
    @Published private(set) var automaticFollowingSuspended = false

    private let service: any SpeechRecognitionService
    private let engine: ScriptAlignmentEngine
    private var recognitionTask: Task<Void, Never>?
    private var followResumeTask: Task<Void, Never>?
    private var lastScrollTarget: Int?
    private var wantsRecognition = false

    init(
        scriptText: String,
        service: (any SpeechRecognitionService)? = nil,
        engine: ScriptAlignmentEngine = ScriptAlignmentEngine()
    ) {
        script = ScriptDocument(text: scriptText)
        self.service = service ?? SpeechServiceFactory.live()
        self.engine = engine
    }

    var currentTokenIndex: Int? { alignmentState.tokenIndex }
    var confidence: Double { alignmentState.confidence }
    var trackingState: AlignmentTrackingState { alignmentState.trackingState }

    func start() {
        guard recognitionTask == nil else { return }
        wantsRecognition = true
        errorMessage = nil
        recognitionTask = Task { [weak self] in
            await self?.recognitionLoop()
        }
    }

    func pause() {
        wantsRecognition = false
        isListening = false
        recognitionTask?.cancel()
        recognitionTask = nil
        Task { await service.stop() }
    }

    func resume() { start() }

    func stop() {
        pause()
        followResumeTask?.cancel()
    }

    func userDidScroll() {
        automaticFollowingSuspended = true
        followResumeTask?.cancel()
        followResumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.returnToCurrentPosition()
        }
    }

    func returnToCurrentPosition() {
        followResumeTask?.cancel()
        automaticFollowingSuspended = false
        if let currentTokenIndex {
            scrollTarget = currentTokenIndex
            lastScrollTarget = currentTokenIndex
        }
    }

    private func recognitionLoop() async {
        defer {
            recognitionTask = nil
            isListening = false
        }
        while wantsRecognition && !Task.isCancelled {
            do {
                let stream = try await service.start()
                isListening = true
                for try await update in stream {
                    guard wantsRecognition, !Task.isCancelled else { break }
                    consume(update)
                }
                if wantsRecognition && !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(200))
                }
            } catch is CancellationError {
                break
            } catch {
                isListening = false
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Speech recognition could not continue."
                wantsRecognition = false
            }
        }
        await service.stop()
    }

    private func consume(_ update: SpeechRecognitionUpdate) {
        recognisedText = update.text
        let result = engine.align(
            script: script,
            recognisedText: update.text,
            previous: alignmentState,
            isFinal: update.isFinal
        )
        alignmentState = result.state
        matchedRange = result.matchedRange
        searchMode = result.searchMode
        candidateScore = result.candidateScore

        guard let tokenIndex = result.tokenIndex, !automaticFollowingSuspended else { return }
        let progressed = lastScrollTarget.map { tokenIndex - $0 >= 6 || tokenIndex < $0 - 5 } ?? true
        if progressed {
            scrollTarget = tokenIndex
            lastScrollTarget = tokenIndex
        }
    }
}
