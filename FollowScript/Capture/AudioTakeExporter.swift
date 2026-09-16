import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

enum AudioTakeExportError: LocalizedError {
    case invalidSource, exporterUnavailable, voiceEnhancementFailed, invalidOutput, cleanupFailed

    var errorDescription: String? {
        switch self {
        case .invalidSource: "The recorded audio could not be opened for AAC conversion."
        case .exporterUnavailable: "AAC conversion is not available for this recording."
        case .voiceEnhancementFailed: "FollowScript could not enhance this voice recording."
        case .invalidOutput: "AAC conversion did not produce a playable audio file."
        case .cleanupFailed: "AAC conversion failed and its unfinished file could not be removed."
        }
    }
}

/// Converts a completed PCM take; it never runs on the live microphone tap.
@MainActor
enum AudioTakeExporter {
    static func exportAAC(from source: URL, enhancingVoice: Bool = false) async throws -> URL {
        guard source.isFileURL, source.pathExtension.lowercased() == "caf",
              FileManager.default.fileExists(atPath: source.path) else {
            throw AudioTakeExportError.invalidSource
        }
        let enhancedSource = enhancingVoice ? try renderEnhancedVoice(from: source) : nil
        defer {
            if let enhancedSource { try? FileManager.default.removeItem(at: enhancedSource) }
        }
        let asset = AVURLAsset(url: enhancedSource ?? source)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty,
              await AVAssetExportSession.compatibility(
                ofExportPreset: AVAssetExportPresetAppleM4A, with: asset, outputFileType: .m4a
              ),
              let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioTakeExportError.exporterUnavailable
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID()).m4a")
        do {
            try await exporter.export(to: destination, as: .m4a)
            let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let exportedAsset = AVURLAsset(url: destination)
            guard size > 0,
                  let track = try await exportedAsset.loadTracks(withMediaType: .audio).first,
                  try await track.load(.formatDescriptions).contains(where: {
                      CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC
                  }) else {
                throw AudioTakeExportError.invalidOutput
            }
            return destination
        } catch {
            if FileManager.default.fileExists(atPath: destination.path) {
                do { try FileManager.default.removeItem(at: destination) }
                catch { throw AudioTakeExportError.cleanupFailed }
            }
            throw error
        }
    }

    /// Produces a temporary processed PCM file. The captured source is never modified.
    private static func renderEnhancedVoice(from source: URL) throws -> URL {
        let inputFile: AVAudioFile
        do { inputFile = try AVAudioFile(forReading: source) }
        catch { throw AudioTakeExportError.voiceEnhancementFailed }

        let format = inputFile.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioTakeExportError.voiceEnhancementFailed
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID())-enhanced.caf")
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let equaliser = AVAudioUnitEQ(numberOfBands: 1)
        let compressor = AVAudioUnitEffect(
            audioComponentDescription: AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
        )

        equaliser.bands[0].filterType = .highPass
        equaliser.bands[0].frequency = 80
        equaliser.bands[0].bandwidth = 0.5
        equaliser.bands[0].bypass = false
        let parameters: [(AudioUnitParameterID, AudioUnitParameterValue)] = [
            (kDynamicsProcessorParam_Threshold, -20),
            (kDynamicsProcessorParam_HeadRoom, 5),
            (kDynamicsProcessorParam_ExpansionRatio, 1),
            (kDynamicsProcessorParam_AttackTime, 0.015),
            (kDynamicsProcessorParam_ReleaseTime, 0.18),
            (kDynamicsProcessorParam_OverallGain, 2)
        ]
        for (parameter, value) in parameters {
            guard AudioUnitSetParameter(
                compressor.audioUnit,
                parameter,
                kAudioUnitScope_Global,
                0,
                value,
                0
            ) == noErr else { throw AudioTakeExportError.voiceEnhancementFailed }
        }

        engine.attach(player)
        engine.attach(equaliser)
        engine.attach(compressor)
        engine.connect(player, to: equaliser, format: format)
        engine.connect(equaliser, to: compressor, format: format)
        engine.connect(compressor, to: engine.mainMixerNode, format: format)

        let maximumFrames: AVAudioFrameCount = 4_096
        do {
            try engine.enableManualRenderingMode(
                .offline,
                format: format,
                maximumFrameCount: maximumFrames
            )
            let outputFile = try AVAudioFile(forWriting: destination, settings: format.settings)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: maximumFrames
            ) else { throw AudioTakeExportError.voiceEnhancementFailed }

            player.scheduleFile(inputFile, at: nil)
            try engine.start()
            player.play()

            var stalledRenders = 0
            while engine.manualRenderingSampleTime < inputFile.length {
                let remaining = inputFile.length - engine.manualRenderingSampleTime
                let frames = min(maximumFrames, AVAudioFrameCount(remaining))
                switch try engine.renderOffline(frames, to: buffer) {
                case .success:
                    stalledRenders = 0
                    try outputFile.write(from: buffer)
                case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
                    stalledRenders += 1
                    guard stalledRenders < 20 else {
                        throw AudioTakeExportError.voiceEnhancementFailed
                    }
                case .error:
                    throw AudioTakeExportError.voiceEnhancementFailed
                @unknown default:
                    throw AudioTakeExportError.voiceEnhancementFailed
                }
            }
            player.stop()
            engine.stop()
            return destination
        } catch {
            engine.stop()
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            throw error is AudioTakeExportError ? error : AudioTakeExportError.voiceEnhancementFailed
        }
    }
}
