# Testing

## Automated suites

The portable deterministic core harness uses the active Swift toolchain:

```sh
swift test
```

It compiles only `Models` and `Alignment`, then runs XCTest on macOS. This is the fastest alignment regression gate and needs no microphone, simulator or network.

The Xcode project contains `FollowScriptTests`, including the same core tests, mock recognition, audio-level and input-route stream tests, recording lifecycle tests, user-selected backward repositioning, a rapid pause/resume lifecycle regression, audio-format regression, iOS 26 transcriber-option coverage and document-import fixtures. The lifecycle test holds cleanup open for 100 milliseconds and verifies that the replacement session cannot start concurrently. Recording coverage verifies that pause finalises an active recording, while level tests verify the visible quality thresholds. The conversion test repeatedly transforms 48 kHz Float32 microphone-style buffers into non-empty 16 kHz signed Int16 buffers. The transcriber configuration test verifies that volatile results, alternatives and audio time ranges remain enabled while `fastResults` is excluded. Import tests cover plain text, Markdown formatting removal, DEFLATE-compressed DOCX XML and stored ODT XML. Build without signing:

```sh
xcodebuild -project FollowScript.xcodeproj -scheme FollowScript -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/FollowScriptDerivedData CODE_SIGNING_ALLOWED=NO build
```

Run the full target on an installed simulator/device, substituting an available destination:

```sh
xcodebuild -project FollowScript.xcodeproj -scheme FollowScript -destination 'platform=iOS Simulator,name=iPhone 17' test
```

`AlignmentFixtures.presentation` is a multi-paragraph presentation. Sequential recognition fragments verify stable forward progression across omissions, punctuation changes and paragraph boundaries. Smaller cases cover each edge condition precisely. Labelled replay sequences use `AlignmentReplayMetrics` to report mean/max estimated-position error, false jumps and reacquisition update count.

## What each environment proves

- `swift test`: token/source mapping and deterministic alignment only.
- Unsigned Xcode build: app/UI/Speech source compiles and links for iOS Simulator.
- Simulator XCTest: mock and app-host integration; not microphone quality.
- Physical iPhone: permissions, actual models/audio, interruptions, latency, scrolling and orientation.

## Comparing tracking latency on an iPhone

FollowScript emits Apple-native signposts in the `TrackingLatency` category for every recognition update. Use Instruments with the Points of Interest instrument and filter for the FollowScript process/category. Each update has a shared signpost identifier and four markers:

- `Recognition Result Arrival`: the result reached the main-actor tracking pipeline.
- `Alignment`: synchronous time spent in `ScriptAlignmentEngine.align`.
- `UI State Commit`: time from alignment completion until SwiftUI has processed the published tracking state on a subsequent main-actor turn. This is a practical SwiftUI commit proxy, not a measurement of completed GPU presentation or the 0.20-second scroll animation.
- `Tracking Total`: result arrival through that UI commit proxy.

Updates superseded before SwiftUI processes them are labelled `superseded=1` and should not be included in latency averages. To provide a quick console check without logging every result, the app's unified `TrackingLatency` log reports mean alignment, mean UI-commit, mean total and maximum total latency once per 20 committed updates.

For a Debug/Release comparison, use the same physical iPhone, iOS version, script, microphone route and speaking passage. Make separate clean runs for each configuration, exclude first-start language-asset installation, record thermal state if either run warms the phone, and compare the same signpost intervals and completed-update counts. Prefer the Instruments distributions over a single console summary. Release instrumentation remains enabled and uses no file, network or third-party analytics storage.

## Physical-iPhone checklist

Record device, iOS, locale, date and observations rather than merely ticking boxes.

Recorded observation: on 13 September 2026, the user confirmed that physical-iPhone live recognition worked after the PCM conversion fix and no longer triggered the signed-Int16 precondition. The device model, iOS version and locale were not recorded.

- [ ] First microphone permission and speech permission prompts
- [ ] Denial state and recovery after changing Settings
- [ ] First start, including any iOS 26 language-asset installation
- [ ] Confirm iOS 26 live input no longer triggers the signed-Int16 precondition
- [ ] Pause/resume and repeated recognition restart (retest the duplicate-tap crash fix)
- [ ] Ten-minute continuous speech and long pauses
- [ ] Partial-result latency and alignment responsiveness
- [ ] Capture `TrackingLatency` signposts for the same passage in Debug and Release; compare Alignment, UI State Commit and Tracking Total distributions
- [ ] Compare iOS 26 partial-result stability and accuracy with `fastResults` omitted, and record any latency increase
- [ ] Tracking pill distinguishes quiet input, heard speech, recognition and reacquisition accurately
- [ ] Microphone check measures ambient level, recognises its script phrase and gives useful guidance
- [ ] Gain slider appears only on a route that reports adjustable input gain
- [ ] Tentative highlighting reacts before committed scrolling without visible false flashes
- [ ] Distant reacquisition requires a distinctive phrase and ignores repeated/common wording
- [ ] iOS 26 time-indexed ranges and alternatives are populated for the selected locale
- [ ] Microphone meter responds to silence, normal speech and clipping without distracting flicker
- [ ] Connect a USB-C wireless-microphone receiver before launch; confirm its system name appears and drives recognition, metering and the saved recording
- [ ] Disconnect and reconnect the external receiver while prompting; confirm the route display updates and the fallback warning is visible
- [ ] Start, stop, share and play a recording; confirm pause, background and exit finalise it
- [ ] Horizontal, vertical and combined prompt-flip readability through the teleprompter glass in portrait and landscape
- [ ] Omissions, repeated passages, an intentional paragraph skip and speech from behind the current position
- [ ] Manual scrolling, delayed follow return and explicit return control
- [ ] Normal reading keeps the active portrait row near one-third screen height and large catch-ups move in bounded steps
- [ ] Tap an earlier and later row, cancel and confirm repositioning, and verify recognition continues from the selected passage
- [ ] Portrait/landscape rotation during recognition
- [ ] Phone call/audio-session interruption and app background/foreground
- [ ] Airplane/offline operation for the selected locale
- [ ] Large prompt sizes, VoiceOver controls and contrast
- [ ] Keep-display-awake behaviour while prompting, backgrounding and exiting
- [ ] Import representative DOCX, ODT, Markdown, RTF and Files-provider documents
- [ ] Battery and thermal behaviour for a realistic presentation

A device run exposed the former duplicate-tap crash, but the corrected lifecycle implementation has not yet been rerun on that device. Treat every unchecked item as unverified. Follow `.skills/testing/SKILL.md`; report exact commands and do not turn a build-only result into a test claim.

### Presentation modes on a physical iPhone

Check all three modes, microphone recognition latency during recording, front-camera preview, prompt exclusion from exported video, audio/video sync, repeated takes, low storage, camera denial, background interruption and external microphone route changes. Simulator builds do not establish camera or microphone behaviour.
