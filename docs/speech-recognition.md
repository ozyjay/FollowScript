# Speech recognition

## Selected APIs

The deployment target is iOS 18. On iOS 26 and later, `SpeechAnalyzer` with an explicitly configured `SpeechTranscriber` consumes `AnalyzerInput` values derived from `AVAudioEngine`. The transcriber requests volatile progressive results, alternative transcriptions and audio time ranges, but omits `fastResults` to favour more stable and accurate partial recognition over the preset's lowest-latency bias. The implementation checks locale support, installs any requested Apple language asset, reserves the locale, selects `SpeechAnalyzer.bestAvailableAudioFormat`, and emits volatile/final results through the app model.

On iOS 18–25, `SFSpeechRecognizer` and `SFSpeechAudioBufferRecognitionRequest` provide partial results. `requiresOnDeviceRecognition` is true, and start fails with a user-readable state if the locale/device cannot satisfy that requirement.

Both implementations conform to `SpeechRecognitionService`; SwiftUI never sees framework types. `MockSpeechRecognitionService` can yield deterministic recognition and audio-level updates.

## Permissions and pipeline

The generated Info.plist contains `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`. Start requests speech permission and microphone record permission, configures a record/measurement audio session, installs one input-node tap, then starts recognition. That same tap supplies a throttled RMS input-level meter and, only when the user presses Record, a local CAF audio file. No second tap or competing audio session is created.

After activating the session, each backend reports the current input route using the system-provided port name and distinguishes the built-in microphone from external inputs such as a USB-C wireless-microphone receiver. The teleprompter displays that name alongside the level meter. An `AVAudioSession.routeChangeNotification` monitor updates the display and shows an immediate warning if an external microphone disconnects and iOS falls back to a built-in input. FollowScript does not force a preferred input: iOS remains responsible for choosing among connected routes.

The meter maps approximately -60 dB to -12 dB onto a zero-to-one scale and labels the result Quiet, Good or Too loud. These thresholds are practical guidance rather than a guarantee of recognition accuracy. The optional microphone check samples ambient level without storing audio and adjusts the Quiet threshold in memory for that prompting session. Recording stops automatically when prompting is paused, backgrounded, interrupted or exited. Finished files are placed in the app's Documents/Recordings folder and can be exported with the system share sheet.

After the audio session becomes active, each backend reports whether the selected route supports `AVAudioSession` input gain. Gain control is exposed only where `isInputGainSettable` is true; unsupported microphones do not show a non-functional slider. Gain changes remain behind `SpeechRecognitionService`, are clamped to the platform's zero-to-one range, and may amplify room noise as well as speech.

SpeechAnalyzer does not transparently convert input. On the iOS 26 path, the tap receives the microphone’s natural PCM format—commonly 48 kHz Float32—and `SpeechAudioBufferConverter` uses `AVAudioConverter` to produce the analyser’s compatible format before creating `AnalyzerInput`. The current device-selected format is required to be signed 16-bit PCM; unsupported or failed conversion becomes a recoverable user-facing error instead of a Speech framework precondition failure. Converted inputs omit manual timestamps so resampling does not attach an incorrect source-rate time base.

## Streaming transcription context

`SpeechTranscriber` results are time-ranged phrases rather than one guaranteed cumulative transcript. With volatile results enabled, Apple may emit several revisions for the same audio range before that range is finalised, and later speech can arrive as separate short final phrases. `SpeechRecognitionSegmentAssembler` therefore reconstructs a short rolling chronological context before alignment.

For each iOS 26 result, the assembler uses `result.range`, `result.isFinal` and `result.resultsFinalizationTime`:

- a newer volatile result replaces an earlier volatile result whose audio range overlaps it;
- a final result replaces earlier revisions over the same range;
- `resultsFinalizationTime` promotes retained earlier segments to final even when Apple never re-emits that range with `isFinal == true`;
- adjacent final and active volatile phrases are concatenated in audio order;
- alternatives for the current phrase receive the same preceding context, so primary and alternative hypotheses remain comparable;
- at most 32 result segments are retained in memory, while `ScriptAlignmentEngine` still applies its existing final 16-token recognition window;
- the assembler resets whenever the recognition session is torn down, so context never leaks across pause/restart sessions.

This turns raw sequences such as `"ICT Project"`, `"One, Analysis"`, `"and"`, `"Design."` into rolling alignment context equivalent to `"ICT Project One, Analysis and Design."`. It does not concatenate by string prefix and it does not alter the alignment engine's monotonic-position or distant-jump safeguards.

`SpeechRecognitionUpdate.text` and `.alternatives` contain the assembled alignment context on iOS 26. `rawText` and `rawAlternatives` preserve the exact current framework result for diagnostics. The legacy recogniser already reports a cumulative formatted transcription, so its assembled and raw values are identical and it does not use the segment assembler.

Partial and final framework results become `SpeechRecognitionUpdate` values containing primary text, optional alternatives, finality, receipt time, optional audio time range and optional confidence. The iOS 26 path supplies the assembled context range ending at the latest transcriber result; the legacy path derives the latest segment's audio range and confidence. Alignment prefers audio-stream time for movement constraints and otherwise uses receipt time.

The iOS 26 SDK also exposes `AnalysisContext.contextualStrings`. FollowScript does not yet pass script text into the recognition service, so contextual vocabulary is intentionally deferred rather than creating a hidden script/audio dependency. A follow-up should add an explicit bounded nearby-vocabulary method, refresh it after committed movement, and measure proper-noun gains and repeated-phrase bias. The explicit no-fast-results configuration still needs physical-device comparison to quantify partial-result stability, accuracy and added latency.

Pause, exit and background transitions stop the engine, remove the tap, finish/cancel recognition, close continuations and deactivate the audio session. Tap removal is tracked explicitly and does not depend on `AVAudioEngine.isRunning`, because an engine may be stopped while its input-node tap still exists.

Each Apple backend assigns a monotonically increasing generation to start/stop requests. After every suspending permission, asset or analyser operation, start verifies that it still owns the current generation before touching the audio graph. A newer stop or start cancels stale work. The view model retains its recognition task during asynchronous cleanup, and Resume waits for that task to finish before launching a replacement session. Natural recognition completion still restarts after a short delay while the user wants recognition.

## On-device behaviour and limitations

The legacy path explicitly requires on-device recognition. The iOS 26 SpeechAnalyzer architecture uses downloaded Apple speech assets, but framework/OS implementation remains Apple-controlled. FollowScript has no cloud speech integration and does not send script text to any endpoint. This code-level review does not prove every OS/device combination is offline.

The source was compiled against the iOS 26.5 SDK. Physical-device traces exposed two precondition failures: an overlapping-session duplicate tap and unconverted Float32 microphone samples passed to an Int16-only analyser. Generation ownership, unconditional tracked tap removal, explicit compatible-format conversion and regression tests were added. On 13 September 2026, the user confirmed that live physical-iPhone recognition worked after the PCM fix without the signed-Int16 failure; device model, OS version and locale were not recorded. Later device traces showed that SpeechTranscriber commonly finalises adjacent phrases separately; the time-ranged segment assembler was added in response. Pause/resume lifecycle retesting, live assembled-context behaviour, model installation, interruption recovery and USB-C receiver routing remain unverified. Simulator behaviour is not accepted as device verification. Follow `.skills/speech-recognition/SKILL.md` for changes.
