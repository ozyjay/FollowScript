import AVFoundation
import SwiftUI

/// Owns camera video only. The existing speech service remains the sole microphone owner.
@MainActor
final class VideoCaptureCoordinator: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
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
        await Task.detached { [session] in session.startRunning() }.value
        isReady = session.isRunning
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

    func start() throws {
        guard isReady, !output.isRecording else { throw VideoCaptureError.unavailable }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mov")
        rawVideoURL = url
        output.startRecording(to: url, recordingDelegate: self)
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
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            if let error { completion?.resume(throwing: error) }
            else { completion?.resume(returning: outputFileURL) }
            completion = nil
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
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// Combines the camera-only movie with the audio written by the recognition microphone tap.
@MainActor
enum VideoTakeMuxer {
    static func combine(video: URL, audio: URL) async throws -> URL {
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
        try soundTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(videoDuration, audioDuration)),
                                       of: audioTrack, at: .zero)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mov")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoCaptureError.unavailable
        }
        try await exporter.export(to: destination, as: .mov)
        return destination
    }
}
