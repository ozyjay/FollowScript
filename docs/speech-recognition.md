# Speech recognition

## Selected APIs

The deployment target is iOS 18. On iOS 26 and later, `SpeechAnalyzer` with `SpeechTranscriber(preset: .progressiveTranscription)` consumes `AnalyzerInput` values derived from `AVAudioEngine`. The implementation checks locale support, installs any requested Apple language asset, reserves the locale, selects `SpeechAnalyzer.bestAvailableAudioFormat`, and emits volatile/final results through the app model.

On iOS 18–25, `SFSpeechRecognizer` and `SFSpeechAudioBufferRecognitionRequest` provide partial results. `requiresOnDeviceRecognition` is true, and start fails with a user-readable state if the locale/device cannot satisfy that requirement.

Both implementations conform to `SpeechRecognitionService`; SwiftUI never sees framework types. `MockSpeechRecognitionService` can yield deterministic updates and errors.

## Permissions and pipeline

The generated Info.plist contains `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`. Start requests speech permission and microphone record permission, configures a record/measurement audio session, installs one input-node tap, then starts recognition. Audio buffers remain in memory.

SpeechAnalyzer does not transparently convert input. On the iOS 26 path, the tap receives the microphone’s natural PCM format—commonly 48 kHz Float32—and `SpeechAudioBufferConverter` uses `AVAudioConverter` to produce the analyser’s compatible format before creating `AnalyzerInput`. The current device-selected format is required to be signed 16-bit PCM; unsupported or failed conversion becomes a recoverable user-facing error instead of a Speech framework precondition failure. Converted inputs omit manual timestamps so resampling does not attach an incorrect source-rate time base.

Partial and final framework results become `SpeechRecognitionUpdate` values containing text, finality, timestamp and optional confidence. The alignment engine uses its own lexical confidence; Apple segment confidence is diagnostic input only on the legacy path.

Pause, exit and background transitions stop the engine, remove the tap, finish/cancel recognition, close continuations and deactivate the audio session. Tap removal is tracked explicitly and does not depend on `AVAudioEngine.isRunning`, because an engine may be stopped while its input-node tap still exists.

Each Apple backend assigns a monotonically increasing generation to start/stop requests. After every suspending permission, asset or analyser operation, start verifies that it still owns the current generation before touching the audio graph. A newer stop or start cancels stale work. The view model retains its recognition task during asynchronous cleanup, and Resume waits for that task to finish before launching a replacement session. Natural recognition completion still restarts after a short delay while the user wants recognition.

## On-device behaviour and limitations

The legacy path explicitly requires on-device recognition. The iOS 26 SpeechAnalyzer architecture uses downloaded Apple speech assets, but framework/OS implementation remains Apple-controlled. FollowScript has no cloud speech integration and does not send script text to any endpoint. This code-level review does not prove every OS/device combination is offline.

The source was compiled against the iOS 26.5 SDK. Physical-device traces exposed two precondition failures: an overlapping-session duplicate tap and unconverted Float32 microphone samples passed to an Int16-only analyser. Generation ownership, unconditional tracked tap removal, explicit compatible-format conversion and regression tests were added. The corrected build still requires physical-device retesting. Live accuracy, model installation, partial-result latency and interruption recovery also remain unverified. Simulator behaviour is not accepted as device verification. Follow `.skills/speech-recognition/SKILL.md` for changes.
