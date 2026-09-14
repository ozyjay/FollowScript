# Teleprompter behaviour

## Reading and highlighting

The prompt uses white rounded text on black, grouped into four-token rows in portrait and six-token rows in landscape. The next word to speak is bright yellow with a subtle background; this is a presentation-only cue one token beyond the alignment engine’s estimated spoken position. Words in the current partial recognition retain a softer yellow and lighter background as context without overriding the bright next-word cue. Words strictly before the estimated spoken position fade to 48% white; the estimated token itself is not dimmed because partial recognition may still be completing that word. Following words remain white as look-ahead text. Users can choose whether the row containing the next-word cue is centred; when that option is off, it follows the general left or centred text-alignment preference. Once the estimated position reaches the final token, no bright cue is shown. Users can also disable highlighting and choose 28–72 point text and 4–20 point row spacing.

The persisted “Ignore text in square brackets” option is enabled by default. Complete bracketed sections, including multiline and nested sections, are omitted from both the visible prompt and alignment input; the original editor text remains unchanged. An unmatched opening bracket remains visible so a malformed placeholder cannot hide the remainder of the script.

The persisted “Remove extra whitespace” option is also enabled by default. It collapses runs of spaces, tabs and line breaks to a single space in the visible prompt and alignment input, preventing source-document formatting from creating large visual gaps. Disabling it preserves the source spacing. The original editor text remains unchanged in either case.

Top content padding places the first row at roughly 28% of screen height. Automatic `scrollTo` uses a 33% vertical anchor, keeping the active passage in the upper-middle reading zone with more look-ahead below it. Bottom padding keeps future text readable near the end. Independent, persisted horizontal-mirror and vertical-flip options transform only the scrolling prompt for different beam-splitter teleprompter arrangements. They can be combined, while controls remain in their normal orientation. Both options can be changed from Settings or during prompting.

## Automatic following

Position comes only from `ScriptAlignmentEngine`. There is no timer scroll. Matching and scroll targets are monotonic once an initial position is acquired: earlier script wording cannot move the prompt backwards. The view model coalesces recognition bursts for one 16-millisecond display interval, then emits the newest scroll target after at least two forward tokens; this prevents multiple SwiftUI scroll mutations in one frame without delaying alignment or highlighting. Moving animation is ease-in-out over 0.20 seconds. An automatic catch-up advances by no more than eight tokens per step at 220-millisecond intervals, preventing a distant recognised position from producing one oversized animated sweep.

## Manual priority and controls

Any drag suspends automatic repositioning for six seconds while speech alignment continues internally. A visible “Return to current position” button ends suspension immediately. Automatic return targets the latest aligned token rather than a stale position.

Tapping any script row presents a confirmation before changing the following position. Continue from here makes the first token in that row the new alignment anchor and restarts recognition so its earlier cumulative transcript cannot undo the choice. This allows deliberate movement backwards or forwards while preserving forward-only automatic following during normal speech.

Pause stops recognition/audio; Resume creates a fresh stream without resetting alignment. Exit cleans up and returns to editing. Backgrounding pauses; becoming active resumes if no session is listening. Permission or recognition errors show a plain-language alert with Try Again and Exit.

Below the top controls, a compact status pill reports recognition and following separately: Listening, Hearing speech or Speech heard/no words yet alongside Finding your place, Following, Unsure or Searching ahead. The states use text and symbols as well as colour. An eye control in the teleprompter toolbar hides or restores this pill for the current prompting session without stopping speech recognition or following. A live microphone meter labels the current input as Quiet, Good or Too loud while listening; Quiet describes the current level and is not itself a tracking error. The system-provided input name appears under the meter, with external inputs visually distinguished from the iPhone microphone. If an external input disconnects while prompting, a visible warning identifies the built-in input that iOS selected instead.

The optional Microphone check measures ambient level for two seconds, then asks the user to read ten nearby script words for up to eight seconds. It reports microphone level, word recognition and script alignment separately, does not save audio, and adjusts only the in-memory Quiet guidance threshold for the current prompting session. It does not relax alignment confidence. If the active route reports that input gain is adjustable, the check exposes an advanced gain slider with a noise warning; unsupported routes show no gain control.

An accessible Record control captures the same microphone input already used by recognition, turns red while active and becomes Stop recording. Pausing, backgrounding or exiting finishes an active recording. Once stopped, the latest locally saved CAF file can be exported with the system share sheet.

The persisted “Keep display awake” option prevents iOS auto-lock only while the teleprompter is visible and the app is active. Backgrounding or exiting restores the idle-timer state that existed before the teleprompter opened. The option is off by default because preventing display sleep increases battery use.

The persisted “Log timestamped tracking info” diagnostic option is off by default. When enabled before starting the teleprompter, FollowScript emits its existing timestamped unified-log tracking decisions, recognised text and latency instrumentation for inspection in Console or Instruments. Logging remains local to the device, but may contain words from the script.

The top controls retain large tap targets and accessibility labels. Both portrait and landscape orientations are declared. Prompt text uses explicit sizes by design, while editor, settings and controls use system text styles. Device rotation, very large text and sustained noisy speech still require hands-on iPhone validation. Follow `.skills/swiftui-feature/SKILL.md` for interaction changes.
