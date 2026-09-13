---
name: swiftui-feature
description: Add or modify FollowScript SwiftUI views, view models, navigation, settings, accessibility, or teleprompter presentation behaviour.
---

# SwiftUI feature

## Purpose and use

Use when changing screens or UI-facing state. Inputs are the desired interaction and affected state. Outputs are a focused SwiftUI change with domain logic kept outside views and updated behavioural documentation when relevant.

## Conventions

- Keep alignment and Speech framework details out of views.
- Own mutable UI state in main-actor `ObservableObject` view models and inject services at initialisation seams.
- Use semantic colours, SF Symbols, Dynamic Type for controls, VoiceOver labels and touch targets of at least 44 points.
- Preserve portrait and landscape layouts. Explicit prompt font sizes are intentional; settings and controls must remain accessible.

## Workflow

1. Read `docs/architecture.md` and, for prompting, `docs/teleprompter-behaviour.md`.
2. Identify state ownership and any test seam before editing a view.
3. Implement with native SwiftUI navigation and presentation patterns.
4. Exercise empty, error, paused and active states; inspect portrait, landscape and large text where available.
5. Build and update the behavioural document when interaction changes.

## Validation checklist

- Views contain presentation logic, not alignment or audio logic.
- Controls have meaningful labels and large targets.
- Manual scrolling is not immediately overridden.
- Orientation and Dynamic Type implications are checked.
- Device-only observations are not claimed without testing.

## Common failures

Avoid scrolling for every token, nesting unbounded text in expensive layouts, hiding errors in debug logs, or creating bindings that bypass persistence.
