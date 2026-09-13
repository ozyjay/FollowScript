# Testing

## Automated suites

The portable deterministic core harness uses the active Swift toolchain:

```sh
swift test
```

It compiles only `Models` and `Alignment`, then runs XCTest on macOS. This is the fastest alignment regression gate and needs no microphone, simulator or network.

The Xcode project contains `FollowScriptTests`, including the same core tests, mock recognition stream tests, a rapid pause/resume lifecycle regression and an audio-format regression. The lifecycle test holds cleanup open for 100 milliseconds and verifies that the replacement session cannot start concurrently. The conversion test repeatedly transforms 48 kHz Float32 microphone-style buffers into non-empty 16 kHz signed Int16 buffers. Build without signing:

```sh
xcodebuild -project FollowScript.xcodeproj -scheme FollowScript -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/FollowScriptDerivedData CODE_SIGNING_ALLOWED=NO build
```

Run the full target on an installed simulator/device, substituting an available destination:

```sh
xcodebuild -project FollowScript.xcodeproj -scheme FollowScript -destination 'platform=iOS Simulator,name=iPhone 17' test
```

`AlignmentFixtures.presentation` is a multi-paragraph presentation. Sequential recognition fragments verify stable forward progression across omissions, punctuation changes and paragraph boundaries. Smaller cases cover each edge condition precisely.

## What each environment proves

- `swift test`: token/source mapping and deterministic alignment only.
- Unsigned Xcode build: app/UI/Speech source compiles and links for iOS Simulator.
- Simulator XCTest: mock and app-host integration; not microphone quality.
- Physical iPhone: permissions, actual models/audio, interruptions, latency, scrolling and orientation.

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
- [ ] Mirrored prompt readability through the teleprompter glass in portrait and landscape
- [ ] Omissions, restarts, repeated passages and an intentional paragraph skip
- [ ] Manual scrolling, delayed follow return and explicit return control
- [ ] Portrait/landscape rotation during recognition
- [ ] Phone call/audio-session interruption and app background/foreground
- [ ] Airplane/offline operation for the selected locale
- [ ] Large prompt sizes, VoiceOver controls and contrast
- [ ] Battery and thermal behaviour for a realistic presentation

A device run exposed the former duplicate-tap crash, but the corrected lifecycle implementation has not yet been rerun on that device. Treat every unchecked item as unverified. Follow `.skills/testing/SKILL.md`; report exact commands and do not turn a build-only result into a test claim.
