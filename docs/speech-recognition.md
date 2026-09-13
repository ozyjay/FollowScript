# Speech recognition

## Selected APIs

The deployment target is iOS 18. On iOS 26 and later, `SpeechAnalyzer` with `SpeechTranscriber(preset: .progressiveTranscription)` consumes `AnalyzerInput` values from `AVAudioEngine`. The implementation checks locale support, installs any requested Apple language asset, reserves the locale, and emits volatile/final results through the app model.

On iOS 18–25, `SFSpeechRecognizer` and `SFSpeechAudioBufferRecognitionRequest` provide partial results. `requiresOnDeviceRecognition` is true, and start fails with a user-readable state if the locale/device cannot satisfy that requirement.

Both implementations conform to `SpeechRecognitionService`; SwiftUI never sees framework types. `MockSpeechRecognitionService` can yield deterministic updates and errors.

## Permissions and pipeline

The generated Info.plist contains `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`. Start requests speech permission and microphone record permission, configures a record/measurement audio session, installs one input-node tap, then starts recognition. Audio buffers remain in memory.

Partial and final framework results become `SpeechRecognitionUpdate` values containing text, finality, timestamp and optional confidence. The alignment engine uses its own lexical confidence; Apple segment confidence is diagnostic input only on the legacy path.

Pause, exit and background transitions stop the engine, remove the tap, finish/cancel recognition, close continuations and deactivate the audio session. Resume creates a new session. Natural recognition completion restarts after a short delay while the user still wants recognition.

## On-device behaviour and limitations

The legacy path explicitly requires on-device recognition. The iOS 26 SpeechAnalyzer architecture uses downloaded Apple speech assets, but framework/OS implementation remains Apple-controlled. FollowScript has no cloud speech integration and does not send script text to any endpoint. This code-level review does not prove every OS/device combination is offline.

The source was compiled against the iOS 26.5 SDK. Live microphone input, model installation, partial-result latency, interruptions and restart have not yet been observed on a physical iPhone. Simulator behaviour is not accepted as verification. Follow `.skills/speech-recognition/SKILL.md` for changes.
