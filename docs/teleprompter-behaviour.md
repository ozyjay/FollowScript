# Teleprompter behaviour

## Reading and highlighting

The prompt uses white rounded text on black, grouped into eight-token rows. The current token is yellow with a subtle background; its row is always centred in the reading area, while the following words remain white and visible as look-ahead text. Earlier text fades to 48% white. Users can disable highlighting and choose 28–72 point text, 4–20 point row spacing, and left or centred alignment for the surrounding rows.

Top content padding places the first row at roughly 34% of screen height. Automatic `scrollTo` uses a 40% vertical anchor, inside the desired 35–45% reading zone. Bottom padding keeps future text readable near the end. Independent, persisted horizontal-mirror and vertical-flip options transform only the scrolling prompt for different beam-splitter teleprompter arrangements. They can be combined, while controls remain in their normal orientation. Both options can be changed from Settings or during prompting.

## Automatic following

Position comes only from `ScriptAlignmentEngine`. There is no timer scroll. Matching and scroll targets are monotonic once an initial position is acquired: earlier script wording cannot move the prompt backwards. The view model emits a new scroll target after at least six forward tokens; moving animation is ease-in-out over 0.45 seconds. Row grouping and the threshold deliberately avoid movement on every partial token.

## Manual priority and controls

Any drag suspends automatic repositioning for six seconds while speech alignment continues internally. A visible “Return to current position” button ends suspension immediately. Automatic return targets the latest aligned token rather than a stale position.

Pause stops recognition/audio; Resume creates a fresh stream without resetting alignment. Exit cleans up and returns to editing. Backgrounding pauses; becoming active resumes if no session is listening. Permission or recognition errors show a plain-language alert with Try Again and Exit.

The persisted “Keep display awake” option prevents iOS auto-lock only while the teleprompter is visible and the app is active. Backgrounding or exiting restores the idle-timer state that existed before the teleprompter opened. The option is off by default because preventing display sleep increases battery use.

The top controls retain large tap targets and accessibility labels. Both portrait and landscape orientations are declared. Prompt text uses explicit sizes by design, while editor, settings and controls use system text styles. Device rotation, very large text and sustained noisy speech still require hands-on iPhone validation. Follow `.skills/swiftui-feature/SKILL.md` for interaction changes.
