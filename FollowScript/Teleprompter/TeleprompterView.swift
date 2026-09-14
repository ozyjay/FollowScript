import SwiftUI
import UIKit

struct TeleprompterView: View {
    @StateObject private var model: TeleprompterViewModel
    @State private var showsDiagnostics = false
    @State private var pausedByUser = false
    @State private var previousIdleTimerDisabled: Bool?
    @State private var requestedPromptRow: PromptRow?
    @Environment(\.scenePhase) private var scenePhase

    @Binding var settings: FollowScriptSettings
    let onExit: () -> Void

    init(
        scriptText: String,
        ignoresSquareBracketedText: Bool,
        settings: Binding<FollowScriptSettings>,
        onExit: @escaping () -> Void
    ) {
        _model = StateObject(
            wrappedValue: TeleprompterViewModel(
                scriptText: scriptText,
                ignoresSquareBracketedText: ignoresSquareBracketedText
            )
        )
        _settings = settings
        self.onExit = onExit
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        let tokensPerRow = promptTokensPerRow(for: geometry.size)
                        LazyVStack(alignment: swiftUIAlignment, spacing: settings.lineSpacing) {
                            Color.clear.frame(height: geometry.size.height * 0.28)
                            ForEach(rows(tokensPerRow: tokensPerRow)) { row in
                                Text(rowText(row))
                                    .font(.system(size: settings.fontSize, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: alignment(for: row))
                                    .multilineTextAlignment(textAlignment(for: row))
                                    .id(row.id)
                                    .accessibilityLabel(row.plainText)
                                    .accessibilityHint("Double-tap to move speech following to this passage")
                                    .contentShape(Rectangle())
                                    .onTapGesture { requestedPromptRow = row }
                            }
                            Color.clear.frame(height: geometry.size.height * 0.55)
                        }
                        .padding(.horizontal, max(24, geometry.size.width * 0.07))
                        .scaleEffect(x: settings.mirrorsPrompt ? -1 : 1, y: 1, anchor: .center)
                    }
                    .scrollIndicators(.hidden)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 5).onChanged { _ in model.userDidScroll() }
                    )
                    .onChange(of: model.scrollTarget) { _, target in
                        guard let target, !model.automaticFollowingSuspended else { return }
                        let tokensPerRow = promptTokensPerRow(for: geometry.size)
                        withAnimation(.easeInOut(duration: 0.20)) {
                            proxy.scrollTo(
                                rowID(containing: target, tokensPerRow: tokensPerRow),
                                anchor: UnitPoint(x: 0.5, y: 0.33)
                            )
                        }
                    }
                    .scaleEffect(x: 1, y: settings.flipsPromptVertically ? -1 : 1, anchor: .center)
                }
            }

            controls

            if model.automaticFollowingSuspended {
                VStack {
                    Spacer()
                    Button("Return to current position", systemImage: "scope") {
                        model.returnToCurrentPosition()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { beginManagingDisplaySleep() }
        .task { model.start() }
        .onDisappear {
            model.stop()
            restoreDisplaySleepSetting()
        }
        .onChange(of: settings.keepsDisplayAwake) { _, _ in
            updateDisplaySleepSetting()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if !pausedByUser, !model.isListening { model.resume() }
            } else {
                model.pause()
            }
            updateDisplaySleepSetting()
        }
        .alert("FollowScript needs attention", isPresented: errorBinding) {
            Button("Try again") {
                pausedByUser = false
                model.resume()
            }
            Button("Exit", role: .cancel) { onExit() }
        } message: {
            Text(model.errorMessage ?? "Speech recognition could not start.")
        }
        .alert("Audio recording needs attention", isPresented: recordingErrorBinding) {
            Button("OK") { model.clearRecordingError() }
        } message: {
            Text(model.recordingErrorMessage ?? "FollowScript could not record audio.")
        }
        .confirmationDialog(
            "Move following to this passage?",
            isPresented: repositionConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Continue from here") {
                if let requestedPromptRow {
                    model.moveFollowing(to: requestedPromptRow.id)
                }
                requestedPromptRow = nil
            }
            Button("Cancel", role: .cancel) { requestedPromptRow = nil }
        } message: {
            Text(requestedPromptRow?.plainText ?? "")
        }
#if DEBUG
        .sheet(isPresented: $showsDiagnostics) {
            DiagnosticsView(model: model)
                .presentationDetents([.medium, .large])
        }
#endif
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button("Exit", systemImage: "xmark") {
                    model.stop()
                    onExit()
                }
                Spacer()
#if DEBUG
                Button("Diagnostics", systemImage: "ladybug") { showsDiagnostics = true }
#endif
                Button(
                    settings.mirrorsPrompt ? "Use normal prompt view" : "Mirror prompt",
                    systemImage: "arrow.left.and.right"
                ) {
                    settings.mirrorsPrompt.toggle()
                }
                .accessibilityValue(settings.mirrorsPrompt ? "On" : "Off")
                .accessibilityHint("Flips only the scrolling script for a teleprompter mirror")

                Button(
                    settings.flipsPromptVertically ? "Use upright prompt" : "Flip prompt vertically",
                    systemImage: "arrow.up.and.down"
                ) {
                    settings.flipsPromptVertically.toggle()
                }
                .accessibilityValue(settings.flipsPromptVertically ? "On" : "Off")
                .accessibilityHint("Turns only the scrolling script upside down")

                Button(
                    model.isRecording ? "Stop recording" : "Record audio",
                    systemImage: model.isRecording ? "stop.circle.fill" : "record.circle"
                ) {
                    model.toggleRecording()
                }
                .foregroundStyle(model.isRecording ? .red : .primary)
                .disabled(!model.isListening && !model.isRecording)

                if let recordingURL = model.latestRecordingURL {
                    ShareLink(item: recordingURL) {
                        Label("Share latest recording", systemImage: "square.and.arrow.up")
                    }
                }

                Button(
                    model.isListening ? "Pause" : "Resume",
                    systemImage: model.isListening ? "pause.fill" : "play.fill"
                ) {
                    if model.isListening {
                        pausedByUser = true
                        model.pause()
                    } else {
                        pausedByUser = false
                        model.resume()
                    }
                }
            }

            MicrophoneLevelView(
                level: model.audioLevel,
                quality: model.microphoneLevelQuality,
                isListening: model.isListening,
                input: model.audioInput
            )

            if let warning = model.audioInputWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel(warning)
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.black.opacity(0.82))
    }

    private func rows(tokensPerRow: Int) -> [PromptRow] {
        stride(from: 0, to: model.script.tokens.count, by: tokensPerRow).map { start in
            let end = min(start + tokensPerRow - 1, model.script.tokens.count - 1)
            return PromptRow(id: start, tokens: Array(model.script.tokens[start...end]))
        }
    }

    private func rowText(_ row: PromptRow) -> AttributedString {
        var result = AttributedString()
        for token in row.tokens {
            var piece = AttributedString(token.displayText)
            if settings.highlightsActivePhrase, token.index == model.currentTokenIndex {
                piece.foregroundColor = .yellow
                piece.backgroundColor = Color.yellow.opacity(0.14)
            } else if let current = model.currentTokenIndex, token.index < current {
                piece.foregroundColor = Color.white.opacity(0.48)
            }
            result.append(piece)
        }
        return result
    }

    private func promptTokensPerRow(for size: CGSize) -> Int {
        size.height > size.width ? 4 : 6
    }

    private func rowID(containing token: Int, tokensPerRow: Int) -> Int {
        (token / tokensPerRow) * tokensPerRow
    }
    private var swiftUIAlignment: HorizontalAlignment { settings.textAlignment == .centre ? .center : .leading }
    private var frameAlignment: Alignment { settings.textAlignment == .centre ? .center : .leading }
    private var textAlignment: TextAlignment { settings.textAlignment == .centre ? .center : .leading }

    private func alignment(for row: PromptRow) -> Alignment {
        shouldCentreHighlightedText(in: row) ? .center : frameAlignment
    }

    private func textAlignment(for row: PromptRow) -> TextAlignment {
        shouldCentreHighlightedText(in: row) ? .center : textAlignment
    }

    private func shouldCentreHighlightedText(in row: PromptRow) -> Bool {
        settings.highlightsActivePhrase
            && settings.centresHighlightedText
            && row.containsToken(model.currentTokenIndex)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { _ in })
    }

    private var recordingErrorBinding: Binding<Bool> {
        Binding(
            get: { model.recordingErrorMessage != nil },
            set: { if !$0 { model.clearRecordingError() } }
        )
    }

    private var repositionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { requestedPromptRow != nil },
            set: { if !$0 { requestedPromptRow = nil } }
        )
    }

    @MainActor
    private func beginManagingDisplaySleep() {
        if previousIdleTimerDisabled == nil {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        updateDisplaySleepSetting()
    }

    @MainActor
    private func updateDisplaySleepSetting() {
        guard let previousIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = settings.keepsDisplayAwake && scenePhase == .active
            ? true
            : previousIdleTimerDisabled
    }

    @MainActor
    private func restoreDisplaySleepSetting() {
        guard let previousIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        self.previousIdleTimerDisabled = nil
    }
}

private struct MicrophoneLevelView: View {
    let level: Double
    let quality: MicrophoneLevelQuality
    let isListening: Bool
    let input: AudioInputDescriptor?

    private var colour: Color {
        guard isListening else { return .secondary }
        switch quality {
        case .quiet: return .orange
        case .good: return .green
        case .loud: return .red
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                ProgressView(value: isListening ? level : 0)
                    .tint(colour)
                    .frame(maxWidth: 180)
                Text(isListening ? quality.rawValue : "Paused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colour)
                    .frame(width: 64, alignment: .leading)
            }
            if let input {
                Label(input.name, systemImage: input.isExternal ? "cable.connector" : "iphone")
                    .font(.caption2)
                    .foregroundStyle(input.isExternal ? .green : .secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(
            [isListening ? quality.rawValue : "Paused", input?.name]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }
}

private struct PromptRow: Identifiable {
    let id: Int
    let tokens: [ScriptToken]
    var plainText: String { tokens.map(\.displayText).joined() }

    func containsToken(_ tokenIndex: Int?) -> Bool {
        guard let tokenIndex else { return false }
        return tokens.contains { $0.index == tokenIndex }
    }
}
