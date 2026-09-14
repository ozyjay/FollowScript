import SwiftUI
import UIKit

struct TeleprompterView: View {
    @StateObject private var model: TeleprompterViewModel
    @State private var showsDiagnostics = false
    @State private var showsMicrophoneCheck = false
    @State private var showsTrackingStatus = true
    @State private var pausedByUser = false
    @State private var previousIdleTimerDisabled: Bool?
    @State private var requestedPromptRow: PromptRow?
    @Environment(\.scenePhase) private var scenePhase

    @Binding var settings: FollowScriptSettings
    let onExit: () -> Void

    init(
        scriptText: String,
        ignoresSquareBracketedText: Bool,
        removesExtraWhitespace: Bool,
        logsTimestampedTrackingInformation: Bool,
        settings: Binding<FollowScriptSettings>,
        onExit: @escaping () -> Void
    ) {
        _model = StateObject(
            wrappedValue: TeleprompterViewModel(
                scriptText: scriptText,
                ignoresSquareBracketedText: ignoresSquareBracketedText,
                removesExtraWhitespace: removesExtraWhitespace,
                logsTimestampedTrackingInformation: logsTimestampedTrackingInformation
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
        .sheet(isPresented: $showsMicrophoneCheck, onDismiss: model.cancelMicrophoneCheck) {
            MicrophoneCheckView(model: model)
                .presentationDetents([.medium, .large])
        }
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
                    showsTrackingStatus ? "Hide tracking status" : "Show tracking status",
                    systemImage: showsTrackingStatus ? "eye.slash" : "eye"
                ) {
                    showsTrackingStatus.toggle()
                }
                .accessibilityValue(showsTrackingStatus ? "Shown" : "Hidden")
                .accessibilityHint("Changes only the status display; speech following continues")

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
                Button("Check microphone and following", systemImage: "waveform.badge.magnifyingglass") {
                    showsMicrophoneCheck = true
                }
                .disabled(!model.isListening)
            }

            if showsTrackingStatus {
                TrackingStatusView(
                    recognition: model.recognitionActivity,
                    following: model.followingPresentationState
                )
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
            if settings.highlightsActivePhrase, token.index == model.nextPromptTokenIndex {
                piece.foregroundColor = .yellow
                piece.backgroundColor = Color.yellow.opacity(0.14)
            } else if settings.highlightsActivePhrase,
                      let partialRange = model.partialMatchedRange,
                      partialRange.contains(token.index) {
                piece.foregroundColor = Color.yellow.opacity(0.72)
                piece.backgroundColor = Color.yellow.opacity(0.07)
            } else if let dimmedThrough = model.dimmedThroughTokenIndex,
                      token.index <= dimmedThrough {
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
            && row.containsToken(model.nextPromptTokenIndex)
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

private struct TrackingStatusView: View {
    let recognition: RecognitionActivity
    let following: FollowingPresentationState

    private var colour: Color {
        if recognition == .noWordsRecognised { return .orange }
        switch following {
        case .following: return .green
        case .unsure: return .orange
        case .finding, .searching: return .blue
        case .paused: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: following == .following ? "checkmark.circle.fill" : "scope")
            Text(following.rawValue).font(.caption.weight(.semibold))
            Text("•").foregroundStyle(.secondary)
            Text(recognition.rawValue).font(.caption)
        }
        .foregroundStyle(colour)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(colour.opacity(0.16), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tracking status")
        .accessibilityValue("\(following.rawValue), \(recognition.rawValue)")
    }
}

private struct MicrophoneCheckView: View {
    @ObservedObject var model: TeleprompterViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                switch model.microphoneCheckPhase {
                case .idle, .measuringRoom:
                    heading("Stay quiet for a moment", symbol: "ear")
                    Text("FollowScript is measuring the room level. No audio is saved.")
                        .foregroundStyle(.secondary)
                    ProgressView()
                case .reading:
                    heading("Read this aloud", symbol: "text.bubble")
                    Text(model.calibrationPrompt)
                        .font(.title3.weight(.medium))
                        .accessibilityLabel("Calibration phrase: \(model.calibrationPrompt)")
                    statusRows
                    Button("Finish check") { model.finishMicrophoneCheck() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                case .complete:
                    heading("Check complete", symbol: "checkmark.circle")
                    statusRows
                    Text(model.microphoneCheckResult?.guidance ?? "Check complete.")
                        .font(.headline)
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                if model.microphoneGain.isAdjustable {
                    Divider()
                    VStack(alignment: .leading) {
                        Text("Microphone gain").font(.headline)
                        Slider(
                            value: Binding(
                                get: { model.microphoneGain.value },
                                set: { model.setMicrophoneGain($0) }
                            ),
                            in: 0...1
                        )
                        Text("Available for this microphone. Higher gain also increases room noise.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Microphone check")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { model.beginMicrophoneCheck() }
    }

    private func heading(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.title2.bold())
    }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            checkRow("Microphone", passed: model.microphoneCheckResult?.microphoneLevelOK)
            checkRow("Speech recognition", passed: model.microphoneCheckResult?.recognitionOK)
            checkRow("Script following", passed: model.microphoneCheckResult?.alignmentOK)
        }
    }

    private func checkRow(_ title: String, passed: Bool?) -> some View {
        Label(title, systemImage: passed.map { $0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill" } ?? "circle.dotted")
            .foregroundStyle(passed.map { $0 ? Color.green : Color.orange } ?? .secondary)
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
