---
name: testing
description: Add FollowScript tests, update fixtures, run builds, diagnose failures, or perform regression and physical-device validation.
---

# Testing

## Purpose and use

Use whenever adding tests or validating a change. Inputs are the behaviour and affected target. Outputs are meaningful deterministic assertions plus an honest command/result report.

## Workflow

1. Choose the narrowest meaningful seam: `swift test` for portable alignment, Xcode tests for app integration, physical iPhone for microphone and presentation behaviour.
2. Add a regression test before fixing a reproducible bug where practical.
3. Run `swift test` for core changes.
4. Run `xcodebuild -project FollowScript.xcodeproj -scheme FollowScript -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/FollowScriptDerivedData CODE_SIGNING_ALLOWED=NO build`.
5. Run Xcode tests on an available simulator/device. If unavailable, report that clearly; a build is not a test run.
6. Record physical-device checks using `docs/testing.md`.

## Validation checklist

- Assertions verify behaviour rather than implementation wording.
- Temporal alignment uses sequential updates.
- Fixtures remain realistic and deterministic.
- Failures are investigated rather than hidden by broad tolerances.
- Commands, counts and limitations are reported exactly.

## Common failures

CoreSimulator may be unavailable in restricted environments; a “Designed for iPhone” test host may require valid signing. Use the portable SwiftPM harness for the deterministic core, but do not imply that it verifies UI or microphone integration.
