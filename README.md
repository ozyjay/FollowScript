# FollowScript

FollowScript is a native iPhone speech-following teleprompter. You provide a prepared script; while you speak, the app recognises speech locally where the platform supports it, estimates your place in the script, highlights the active phrase, and scrolls only when meaningful progress has occurred.

> FollowScript follows the speaker; the speaker should not have to follow the teleprompter.

## Requirements and build

- macOS with Xcode 26.6 or newer (the project was built with iOS 26.5 SDK)
- iOS 18.0 deployment target
- A physical iPhone for meaningful microphone and live Speech verification

Open `FollowScript.xcodeproj`, select the `FollowScript` scheme and an iPhone, then Build and Run. No third-party packages, accounts, API keys or backend are required.

Command-line build:

```sh
xcodebuild -project FollowScript.xcodeproj -scheme FollowScript -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/FollowScriptDerivedData CODE_SIGNING_ALLOWED=NO build
```

## MVP

- Persistent single-script editor and persistent font, spacing, alignment and highlighting settings
- Portrait/landscape teleprompter with an active four-word phrase and a 40% reading zone
- Speech-driven, thresholded scrolling; no timer-based movement
- Manual scrolling with a six-second auto-follow pause and explicit return control
- Pause, resume, exit and user-facing permission/error states
- Framework-neutral speech stream, mock recogniser, deterministic alignment engine and debug-only diagnostics
- `SpeechAnalyzer`/`SpeechTranscriber` on iOS 26+, with an on-device `SFSpeechRecognizer` path for iOS 18–25

## Structure

```text
FollowScript/          app, models, speech, alignment and UI
FollowScriptTests/     XCTest and realistic alignment fixtures
.skills/               project-local agent workflows
docs/                  architecture and behavioural specifications
Package.swift          portable deterministic-core test harness
```

Project-local workflows are indexed in [`.skills/README.md`](.skills/README.md). They supplement [AGENTS.md](AGENTS.md).

## Alignment and speech

Recognition text is normalised and compared with candidate windows using edit similarity and longest-common-subsequence coverage. Reliable tracking uses a bounded local window with continuity preference. Sustained weak evidence enters global reacquisition; a distant jump needs several recognised words and strong confidence. See [alignment-engine.md](docs/alignment-engine.md).

Apple Speech is isolated behind `SpeechRecognitionService`. The app neither records audio to disk nor sends scripts to a service of its own. Speech behaviour remains subject to Apple framework, language-model and OS availability. See [speech-recognition.md](docs/speech-recognition.md) and [privacy.md](docs/privacy.md).

## Tests

Run the portable core suite:

```sh
swift test
```

Run the Xcode suite on an available simulator:

```sh
xcodebuild -project FollowScript.xcodeproj -scheme FollowScript -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The core suite covers source mapping, normalisation, exact reading, punctuation/case variation, omissions, insertions, fillers, recognition errors, repetition, sentence restart, low confidence, partial results, local tracking, paragraph skips and global reacquisition. More detail and the physical-iPhone checklist are in [testing.md](docs/testing.md).

## Privacy

The current script and settings are stored in `UserDefaults`. Audio buffers are consumed in memory and not saved. There are no analytics, accounts, cloud APIs or application-managed network requests. The app requests microphone and speech-recognition permissions and refuses the legacy recogniser when on-device recognition is unavailable. On iOS 26+, Apple may download a language asset before first use.

## Known limitations and roadmap

Live recognition, interruptions, long sessions, offline behaviour and thermal use still require physical-iPhone verification. Alignment is word based and does not use phonetic similarity, semantic paraphrase matching or language-specific contraction expansion. Teleprompter rows are grouped in eight-token blocks, so very large fonts scroll at row granularity. There is no script library, import pipeline, remote control, recording or cloud sync.

Useful next work is physical-device tuning, mock-driven view-model integration tests, VoiceOver/Dynamic Type UI testing, richer interruption recovery, and evidence-led alignment tuning from real recognition traces.
