import SwiftUI
import UIKit

struct TeleprompterView: View {
    @StateObject private var model: TeleprompterViewModel
    @State private var showsDiagnostics = false
    @State private var showsMicrophoneCheck = false
    @State private var showsInterfaceChrome = true
    @State private var pausedByUser = false
    @State private var previousIdleTimerDisabled: Bool?
    @State private var requestedPromptToken: Int?
    @Environment(\.scenePhase) private var scenePhase

    @Binding var settings: FollowScriptSettings
    let onExit: () -> Void

    init(
        scriptText: String,
        mode: PresentationMode,
        ignoresSquareBracketedText: Bool,
        removesExtraWhitespace: Bool,
        logsTimestampedTrackingInformation: Bool,
        settings: Binding<FollowScriptSettings>,
        onExit: @escaping () -> Void
    ) {
        _model = StateObject(
            wrappedValue: TeleprompterViewModel(
                scriptText: scriptText,
                mode: mode,
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
            if model.mode == .audiovisual {
                CameraPreview(session: model.videoCapture.session).ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: swiftUIAlignment, spacing: 0) {
                            Color.clear.frame(height: geometry.size.height * 0.28)
                            PromptFlowLayout(
                                lineSpacing: settings.lineSpacing,
                                centresAllLines: settings.textAlignment == .centre,
                                centresHighlightedLine: settings.highlightsActivePhrase
                                    && settings.centresHighlightedText
                            ) {
                                ForEach(model.script.tokens) { token in
                                    Text(tokenText(token))
                                    .font(.system(size: settings.fontSize, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white)
                                    .layoutValue(
                                        key: HighlightedPromptTokenKey.self,
                                        value: token.index == model.nextPromptTokenIndex
                                    )
                                    .id(token.index)
                                    .accessibilityLabel(token.original)
                                    .accessibilityHint(
                                        showsInterfaceChrome
                                            ? "Double-tap to move speech following to this passage"
                                            : "Double-tap to show teleprompter controls"
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if showsInterfaceChrome {
                                            requestedPromptToken = token.index
                                        } else {
                                            withAnimation { showsInterfaceChrome = true }
                                        }
                                    }
                                }
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
                        let retainedToken = max(0, target - 2)
                        withAnimation(.easeInOut(duration: 0.20)) {
                            proxy.scrollTo(
                                retainedToken,
                                anchor: UnitPoint(x: 0.5, y: 0.38)
                            )
                        }
                    }
                    .scaleEffect(x: 1, y: settings.flipsPromptVertically ? -1 : 1, anchor: .center)
                }
            }

            if showsInterfaceChrome {
                controls
                    .transition(.opacity)
            }

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
        .task {
            if model.mode == .audiovisual { await model.prepareVideo() }
            model.start()
        }
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
                if let requestedPromptToken {
                    model.moveFollowing(to: requestedPromptToken)
                }
                requestedPromptToken = nil
            }
            Button("Cancel", role: .cancel) { requestedPromptToken = nil }
        } message: {
            Text(promptContext(around: requestedPromptToken))
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
                Button("Hide teleprompter controls", systemImage: "eye.slash") {
                    withAnimation { showsInterfaceChrome = false }
                }
                .accessibilityHint("Tap the script to restore controls; speech following continues")

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

                if model.mode != .teleprompter {
                Button(
                    model.isRecording ? "Stop recording" : (model.mode == .audio ? "Record audio" : "Record video"),
                    systemImage: model.isRecording ? "stop.circle.fill" : "record.circle"
                ) {
                    Task { await model.toggleRecording() }
                }
                .foregroundStyle(model.isRecording ? .red : .primary)
                .disabled(!model.isListening && !model.isRecording)
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

            TrackingStatusView(
                recognition: model.recognitionActivity,
                following: model.followingPresentationState
            )

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

    private func tokenText(_ token: ScriptToken) -> AttributedString {
        var result = AttributedString(token.displayText)
        if settings.highlightsActivePhrase, token.index == model.nextPromptTokenIndex {
            result.foregroundColor = .yellow
            result.backgroundColor = Color.yellow.opacity(0.14)
        } else if settings.highlightsActivePhrase,
                  let partialRange = model.partialMatchedRange,
                  partialRange.contains(token.index) {
            result.foregroundColor = Color.yellow.opacity(0.72)
            result.backgroundColor = Color.yellow.opacity(0.07)
        } else if let spokenThrough = model.spokenThroughTokenIndex,
                  token.index <= spokenThrough {
            result.foregroundColor = Color(red: 0.35, green: 0.65, blue: 1)
        }
        return result
    }

    private var swiftUIAlignment: HorizontalAlignment { settings.textAlignment == .centre ? .center : .leading }

    private func promptContext(around tokenIndex: Int?) -> String {
        guard let tokenIndex else { return "" }
        let lowerBound = max(0, tokenIndex - 3)
        let upperBound = min(model.script.tokens.count, tokenIndex + 7)
        return model.script.tokens[lowerBound..<upperBound].map(\.original).joined(separator: " ")
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
            get: { requestedPromptToken != nil },
            set: { if !$0 { requestedPromptToken = nil } }
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

private struct PromptFlowLayout: Layout {
    let lineSpacing: CGFloat
    let centresAllLines: Bool
    let centresHighlightedLine: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, point) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var lines: [Range<Int>] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var lineStart = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                lines.append(lineStart..<index)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
                lineStart = index
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
        if lineStart < subviews.count { lines.append(lineStart..<subviews.count) }

        for line in lines {
            guard let lastIndex = line.last else { continue }
            let lastSize = subviews[lastIndex].sizeThatFits(.unspecified)
            let lineWidth = positions[lastIndex].x + lastSize.width
            let hasHighlight = line.contains { index in
                subviews[index][HighlightedPromptTokenKey.self]
            }
            if centresAllLines || (centresHighlightedLine && hasHighlight) {
                let offset = max(0, (width - lineWidth) / 2)
                for index in line { positions[index].x += offset }
            }
        }
        return (CGSize(width: width, height: y + lineHeight), positions)
    }
}

private struct HighlightedPromptTokenKey: LayoutValueKey {
    static let defaultValue = false
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
