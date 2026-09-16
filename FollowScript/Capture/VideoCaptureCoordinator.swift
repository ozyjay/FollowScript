import AVFoundation
import SwiftUI

/// Owns camera video only. The existing speech service remains the sole microphone owner.
@MainActor
final class VideoCaptureCoordinator: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private(set) var camera: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var captureRotationObservation: NSKeyValueObservation?
    private var startCompletion: CheckedContinuation<Date, Error>?
    private var completion: CheckedContinuation<URL, Error>?
    private var rawVideoURL: URL?
    @Published private(set) var isReady = false

    func prepare(frameRate: FollowScriptSettings.VideoFrameRate,
                 focusMode: FollowScriptSettings.VideoFocusMode) async throws {
        guard !isReady else { return }
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw VideoCaptureError.permissionDenied }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else { throw VideoCaptureError.unavailable }
        session.beginConfiguration()
        session.sessionPreset = frameRate.framesPerSecond == nil ? .high : .inputPriority
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw VideoCaptureError.unavailable
        }
        session.addInput(input)
        session.addOutput(output)
        do {
            if let framesPerSecond = frameRate.framesPerSecond {
                try configure(camera: camera, framesPerSecond: framesPerSecond)
            }
            try configure(camera: camera, focusMode: focusMode)
        } catch {
            session.removeInput(input)
            session.removeOutput(output)
            session.commitConfiguration()
            throw error
        }
        session.commitConfiguration()
        self.camera = camera
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        rotationCoordinator = coordinator
        captureRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture,
                                                         options: [.initial, .new]) { [weak self] coordinator, _ in
            Task { @MainActor [weak self] in
                self?.applyCaptureRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
            }
        }
        await Task.detached { [session] in session.startRunning() }.value
        isReady = session.isRunning
    }

    private func applyCaptureRotation(_ angle: CGFloat) {
        guard !output.isRecording else { return }
        guard let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    private func configure(camera: AVCaptureDevice, focusMode: FollowScriptSettings.VideoFocusMode) throws {
        let deviceMode: AVCaptureDevice.FocusMode
        switch focusMode {
        case .cameraDefault: return
        case .continuous: deviceMode = .continuousAutoFocus
        case .locked: deviceMode = .locked
        }
        guard camera.isFocusModeSupported(deviceMode) else {
            throw VideoCaptureError.unsupportedFocusMode(focusMode)
        }
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        camera.focusMode = deviceMode
    }

    private func configure(camera: AVCaptureDevice, framesPerSecond: Int) throws {
        let rate = Double(framesPerSecond)
        let supportedFormats = camera.formats.filter { format in
            format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= rate && rate <= $0.maxFrameRate }
        }
        let currentDimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        let currentPixels = Int(currentDimensions.width) * Int(currentDimensions.height)
        guard let format = supportedFormats.first(where: { $0 == camera.activeFormat })
            ?? supportedFormats.min(by: { lhs, rhs in
                let left = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
                let right = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
                let leftPixels = Int(left.width) * Int(left.height)
                let rightPixels = Int(right.width) * Int(right.height)
                return abs(leftPixels - currentPixels) < abs(rightPixels - currentPixels)
            }) else {
            throw VideoCaptureError.unsupportedFrameRate(framesPerSecond)
        }
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        camera.activeFormat = format
        let duration = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        camera.activeVideoMinFrameDuration = duration
        camera.activeVideoMaxFrameDuration = duration
    }

    func start() async throws -> Date {
        guard isReady, !output.isRecording else { throw VideoCaptureError.unavailable }
        if let rotationCoordinator {
            applyCaptureRotation(rotationCoordinator.videoRotationAngleForHorizonLevelCapture)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mov")
        rawVideoURL = url
        return try await withCheckedThrowingContinuation { continuation in
            startCompletion = continuation
            output.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stop() async throws -> URL {
        guard output.isRecording else { throw VideoCaptureError.notRecording }
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            output.stopRecording()
        }
    }

    func shutdown() {
        if output.isRecording { output.stopRecording() }
        session.stopRunning()
        isReady = false
        captureRotationObservation = nil
        rotationCoordinator = nil
        camera = nil
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            if let error {
                startCompletion?.resume(throwing: error)
                completion?.resume(throwing: error)
            }
            else { completion?.resume(returning: outputFileURL) }
            startCompletion = nil
            completion = nil
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                                from connections: [AVCaptureConnection]) {
        let startedAt = Date()
        Task { @MainActor in
            startCompletion?.resume(returning: startedAt)
            startCompletion = nil
        }
    }
}

enum VideoCaptureError: LocalizedError {
    case permissionDenied, unavailable, notRecording, unsupportedFrameRate(Int)
    case unsupportedFocusMode(FollowScriptSettings.VideoFocusMode)
    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Camera access is required for video recording."
        case .unavailable: "The camera is unavailable."
        case .notRecording: "No video recording is active."
        case .unsupportedFrameRate(let rate): "The front camera does not support \(rate) fps. Choose another frame rate in Settings."
        case .unsupportedFocusMode(let mode): "The front camera does not support \(mode.title.lowercased()). Choose another focus mode in Settings."
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var capture: VideoCaptureCoordinator
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = capture.session
        view.updateCamera(capture.camera)
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.updateCamera(capture.camera)
    }
}

final class PreviewView: UIView {
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private weak var currentCamera: AVCaptureDevice?
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    func updateCamera(_ camera: AVCaptureDevice?) {
        guard currentCamera !== camera else {
            if let rotationCoordinator {
                applyPreviewRotation(rotationCoordinator.videoRotationAngleForHorizonLevelPreview)
            }
            return
        }
        previewRotationObservation = nil
        rotationCoordinator = nil
        currentCamera = camera
        guard let camera else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        previewRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview,
                                                         options: [.initial, .new]) { [weak self] coordinator, _ in
            self?.applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}

/// Combines the camera-only movie with the audio written by the recognition microphone tap.
@MainActor
enum VideoTakeMuxer {
    static func combine(video: URL, audio: URL, audioStartedAt: Date, videoStartedAt: Date) async throws -> URL {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let movieTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let soundTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoCaptureError.unavailable
        }
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        try movieTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        movieTrack.preferredTransform = try await videoTrack.load(.preferredTransform)
        // The microphone begins before the camera. Trim that leading audio instead of
        // treating the start of both independent files as the same instant.
        let offset = videoStartedAt.timeIntervalSince(audioStartedAt)
        let audioTrim = CMTime(seconds: max(0, offset), preferredTimescale: 600)
        let audioPlacement = CMTime(seconds: max(0, -offset), preferredTimescale: 600)
        let availableAudio = CMTimeSubtract(audioDuration, audioTrim)
        let availableVideo = CMTimeSubtract(videoDuration, audioPlacement)
        let soundDuration = CMTimeMinimum(availableAudio, availableVideo)
        guard soundDuration.isValid, soundDuration > .zero else { throw VideoCaptureError.unavailable }
        try soundTrack.insertTimeRange(CMTimeRange(start: audioTrim, duration: soundDuration),
                                       of: audioTrack, at: audioPlacement)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mov")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoCaptureError.unavailable
        }
        try await exporter.export(to: destination, as: .mov)
        return destination
    }
}
