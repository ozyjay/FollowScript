import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class RecordingPlaybackModel: ObservableObject {
    private struct PreviousAudioSession {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    let url: URL
    let isVideo: Bool
    private let recordingID: UUID?
    private let diagnosticsEnabled: Bool
    @Published private(set) var videoPlayer: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    private var audioPlayer: AVAudioPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var audioClockTask: Task<Void, Never>?
    private var previousAudioSession: PreviousAudioSession?
    private var didStartPlayback = false

    init(url: URL, recordingID: UUID? = nil, diagnosticsEnabled: Bool = false) {
        self.url = url
        self.recordingID = recordingID
        self.diagnosticsEnabled = diagnosticsEnabled
        isVideo = url.pathExtension.lowercased() == "mov"
    }

    func prepare() async {
        PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled, operation: "playTake", phase: "requested", identifier: recordingID)
        do {
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
                throw RecordingPlaybackError.fileMissing
            }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0 else { throw RecordingPlaybackError.emptyFile }
            guard ["caf", "m4a", "mov"].contains(url.pathExtension.lowercased()) else {
                throw RecordingPlaybackError.unsupportedFormat
            }

            let session = AVAudioSession.sharedInstance()
            previousAudioSession = PreviousAudioSession(
                category: session.category, mode: session.mode, options: session.categoryOptions
            )
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            if isVideo {
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.isPlayable),
                      !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
                    throw RecordingPlaybackError.unplayableVideo
                }
                let loadedDuration = try await asset.load(.duration).seconds
                try Task.checkCancellation()
                guard loadedDuration.isFinite, loadedDuration > 0 else {
                    throw RecordingPlaybackError.unplayableVideo
                }
                duration = loadedDuration
                let item = AVPlayerItem(asset: asset)
                statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    let failed = item.status == .failed
                    let failure = item.error ?? RecordingPlaybackError.unplayableVideo
                    let detail = item.error?.localizedDescription
                    Task { @MainActor [weak self] in
                        guard failed, let self else { return }
                        PresentationManagementDiagnostics.event(
                            enabled: self.diagnosticsEnabled, operation: "playTake", phase: "failed",
                            identifier: self.recordingID,
                            error: failure
                        )
                        self.isPlaying = false
                        self.errorMessage = detail ?? RecordingPlaybackError.unplayableVideo.localizedDescription
                    }
                }
                let player = AVPlayer(playerItem: item)
                timeObserver = player.addPeriodicTimeObserver(
                    forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
                ) { [weak self] time in
                    let seconds = time.seconds
                    Task { @MainActor [weak self] in
                        guard let self, seconds.isFinite else { return }
                        self.currentTime = seconds
                        if seconds >= self.duration - 0.1 { self.isPlaying = false }
                    }
                }
                videoPlayer = player
                player.play()
                isPlaying = true
            } else {
                let player = try AVAudioPlayer(contentsOf: url)
                guard player.prepareToPlay(), player.duration > 0 else {
                    throw RecordingPlaybackError.unplayableAudio
                }
                audioPlayer = player
                duration = player.duration
                guard player.play() else { throw RecordingPlaybackError.unplayableAudio }
                isPlaying = true
                startAudioClock()
            }
            didStartPlayback = true
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled, operation: "playTake", phase: "started", identifier: recordingID)
        } catch is CancellationError {
            stop()
        } catch {
            stop()
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled, operation: "playTake", phase: "failed", identifier: recordingID, error: error)
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayPause() {
        guard errorMessage == nil else { return }
        if isPlaying {
            videoPlayer?.pause()
            audioPlayer?.pause()
            isPlaying = false
            audioClockTask?.cancel()
        } else {
            if currentTime >= duration - 0.1 { seek(to: 0) }
            if let videoPlayer {
                videoPlayer.play()
                isPlaying = true
            } else if let audioPlayer {
                isPlaying = audioPlayer.play()
                if isPlaying { startAudioClock() }
                else { errorMessage = RecordingPlaybackError.unplayableAudio.localizedDescription }
            }
        }
    }

    func seek(to seconds: TimeInterval) {
        let position = min(max(0, seconds), duration)
        currentTime = position
        if let audioPlayer { audioPlayer.currentTime = position }
        videoPlayer?.seek(to: CMTime(seconds: position, preferredTimescale: 600))
    }

    func stop() {
        if didStartPlayback {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled, operation: "playTake", phase: "ended", identifier: recordingID)
            didStartPlayback = false
        }
        audioClockTask?.cancel()
        audioClockTask = nil
        if let videoPlayer, let timeObserver { videoPlayer.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObservation = nil
        videoPlayer?.pause()
        videoPlayer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        if let previousAudioSession {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(previousAudioSession.category,
                                     mode: previousAudioSession.mode,
                                     options: previousAudioSession.options)
            self.previousAudioSession = nil
        }
    }

    private func startAudioClock() {
        audioClockTask?.cancel()
        audioClockTask = Task { [weak self] in
            while let self, self.isPlaying, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let player = self.audioPlayer else { break }
                self.currentTime = player.currentTime
                if !player.isPlaying { self.isPlaying = false; break }
            }
        }
    }
}

private enum RecordingPlaybackError: LocalizedError {
    case fileMissing, emptyFile, unsupportedFormat, unplayableAudio, unplayableVideo

    var errorDescription: String? {
        switch self {
        case .fileMissing: "This take is no longer on the device."
        case .emptyFile: "This take has no recorded media."
        case .unsupportedFormat: "FollowScript cannot play this file format."
        case .unplayableAudio: "The audio in this take could not be opened."
        case .unplayableVideo: "The video in this take could not be opened."
        }
    }
}

struct RecordingPlaybackView: View {
    @StateObject private var model: RecordingPlaybackModel
    @Environment(\.dismiss) private var dismiss

    init(url: URL, recordingID: UUID? = nil, diagnosticsEnabled: Bool = false) {
        _model = StateObject(wrappedValue: RecordingPlaybackModel(
            url: url, recordingID: recordingID, diagnosticsEnabled: diagnosticsEnabled
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.isVideo, model.errorMessage == nil {
                    playbackControls
                        .padding(20)
                    if let player = model.videoPlayer {
                        VideoPlaybackSurface(player: player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black)
                            .ignoresSafeArea(edges: .bottom)
                    } else {
                        ProgressView("Opening video")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black)
                    }
                } else {
                    Group {
                        if let error = model.errorMessage {
                            ContentUnavailableView("Cannot play take", systemImage: "exclamationmark.triangle",
                                                   description: Text(error))
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 80))
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.errorMessage == nil {
                        playbackControls
                    }
                }
            }
            .padding(model.isVideo && model.errorMessage == nil ? 0 : 20)
            .navigationTitle(model.isVideo ? "Video take" : "Audio take")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await model.prepare() }
            .onDisappear { model.stop() }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button(model.isPlaying ? "Pause" : "Play",
                   systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                model.togglePlayPause()
            }
            .buttonStyle(.borderedProminent)
            .frame(minWidth: 44, minHeight: 44)

            Slider(value: Binding(
                get: { model.currentTime },
                set: { model.seek(to: $0) }
            ), in: 0...max(model.duration, 0.1))
            .disabled(model.duration == 0)
            .accessibilityLabel("Playback position")
            Text("\(timeLabel(model.currentTime)) / \(timeLabel(model.duration))")
                .font(.caption.monospacedDigit())
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let wholeSeconds = Int(max(0, seconds))
        return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }
}

private struct VideoPlaybackSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> VideoPlaybackView {
        let view = VideoPlaybackView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: VideoPlaybackView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class VideoPlaybackView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
