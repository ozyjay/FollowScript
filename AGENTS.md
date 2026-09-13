# FollowScript agent guidance

## Purpose and priorities

FollowScript is a local-first iPhone teleprompter that estimates the speaker’s place in a prepared script. The product rule is: FollowScript follows the speaker; the speaker does not follow the teleprompter.

Prioritise reliability, privacy, responsive interaction, testability, maintainability, then visual polish.

## Architecture

Keep speech recognition, deterministic script alignment, UI state and SwiftUI presentation separable. `ScriptAlignmentEngine` must remain independent of microphone and framework types. UI-facing mutable state belongs on the main actor; asynchronous audio and recognition use Swift concurrency. Avoid global mutable state and singleton-heavy design.

Use modern idiomatic Swift and SwiftUI, meaningful names, focused types and functions, and Australian English in documentation and comments where natural. Do not swallow errors, introduce unexplained constants, or force unwrap unless safety is both demonstrable and documented. Prefer Apple frameworks; document why the platform is insufficient before adding a package.

Do not add external speech, analytics or script-processing services without an explicit project decision.

## Tests and documentation

Alignment changes require deterministic coverage, including a regression test when fixing a bug. Update the relevant document when architecture or behaviour changes. Before declaring work complete, build the relevant target, run relevant tests, report exact results, and identify device-only behaviour that remains unverified.

Avoid unrelated refactoring. Prefer incremental, reviewable changes.

## Project-local skills

Reusable workflows are in `.skills/`; see `.skills/README.md` for discovery and routing. Inspect the relevant skill before changing its area:

- `alignment-engine` for tokenisation and matching;
- `swiftui-feature` for views, view models and accessibility;
- `speech-recognition` for Speech/AVFoundation work;
- `testing` for test and validation changes;
- `documentation` for maintained project guidance.

Skills supplement this file and never override system, user or repository instructions. Update them when a recurring workflow or convention genuinely changes.
