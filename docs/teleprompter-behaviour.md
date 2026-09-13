# Teleprompter behaviour

## Reading and highlighting

The prompt uses white rounded text on black, grouped into eight-token rows. The current token and next three tokens form the active phrase and are yellow with a subtle background; earlier text fades to 48% white. Users can disable highlighting and choose 28–72 point text, 4–20 point row spacing, and left or centred alignment.

Top content padding places the first row at roughly 34% of screen height. Automatic `scrollTo` uses a 40% vertical anchor, inside the desired 35–45% reading zone. Bottom padding keeps future text readable near the end. A persisted horizontal mirror option flips only the scrolling prompt for use with a beam-splitter teleprompter; controls remain in their normal orientation and the option can be changed from Settings or during prompting.

## Automatic following

Position comes only from `ScriptAlignmentEngine`. There is no timer scroll. The view model emits a new scroll target after at least six forward tokens or more than five backward tokens; moving animation is ease-in-out over 0.45 seconds. Row grouping and thresholds deliberately avoid movement on every partial token.

## Manual priority and controls

Any drag suspends automatic repositioning for six seconds while speech alignment continues internally. A visible “Return to current position” button ends suspension immediately. Automatic return targets the latest aligned token rather than a stale position.

Pause stops recognition/audio; Resume creates a fresh stream without resetting alignment. Exit cleans up and returns to editing. Backgrounding pauses; becoming active resumes if no session is listening. Permission or recognition errors show a plain-language alert with Try Again and Exit.

The top controls retain large tap targets and accessibility labels. Both portrait and landscape orientations are declared. Prompt text uses explicit sizes by design, while editor, settings and controls use system text styles. Device rotation, very large text and sustained noisy speech still require hands-on iPhone validation. Follow `.skills/swiftui-feature/SKILL.md` for interaction changes.
