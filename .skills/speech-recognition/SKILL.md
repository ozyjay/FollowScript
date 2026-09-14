---
name: speech-recognition
description: Change FollowScript microphone setup, permissions, Apple Speech APIs, recognition streams, interruptions, cancellation, or restart behaviour.
---

# Speech recognition

## Purpose and use

Use for files under `FollowScript/Speech` and lifecycle code consuming speech streams. Inputs are the required recognition/lifecycle behaviour and supported OS range. Outputs are protocol-isolated, cancellable local-first recognition with privacy and physical-device notes.

## Conventions

- Check the installed SDK interface before adopting new Speech APIs.
- Keep Apple types behind `SpeechRecognitionService`; tests use `MockSpeechRecognitionService`.
- Prefer `SpeechAnalyzer`/`SpeechTranscriber` on iOS 26+, with the on-device legacy API for iOS 18–25.
- Feed SpeechAnalyzer only buffers converted to `bestAvailableAudioFormat`; it does not convert microphone PCM automatically.
- Store microphone audio only for an explicit user-started local recording, and keep passive recognition buffers in memory. Require on-device recognition on the legacy path; do not silently fall back to a network recogniser.

## Workflow

1. Read `docs/speech-recognition.md` and `docs/privacy.md`.
2. Verify API signatures and availability against the selected Xcode SDK.
3. Review permission text and every audio-session start/stop path.
4. Add deterministic mock-driven coverage where possible; document what needs hardware.
5. Build, run relevant tests, and update both speech documentation and the physical-device checklist.

## Validation checklist

- Denial and unavailable states become useful app errors.
- Start, pause, restart, cancellation and background transitions clean up taps/tasks.
- Partial and final updates preserve the framework-neutral model.
- Float microphone buffers are converted to analyser-compatible PCM and covered by a sequential-buffer test.
- Privacy claims distinguish platform behaviour from observed tests.
- A real iPhone test is recorded before claiming live recognition works.

## Common failures

Audio taps left installed make restart crash; native microphone Float32 passed directly to SpeechAnalyzer fails its Int16 precondition; continuations can outlive sessions; asset downloads can delay first start; simulator recognition is not device proof; changing actor isolation can introduce races.
