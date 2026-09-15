# Privacy

FollowScript requests microphone access and Apple speech-recognition authorisation solely to estimate the speaker’s current position in their prepared script.

## Stored locally

- The current script is stored in app `UserDefaults`.
- Font size, line spacing, alignment, highlighting, highlighted-text centring, prompt-flip, display-awake and bracketed-placeholder preferences are stored in `UserDefaults`.
- Audio is stored in the app's Documents/Recordings folder only when the user explicitly starts recording. Finished recordings remain local unless the user exports them through the system share sheet.

## Not stored or added

- Microphone audio used for speech following and level metering is otherwise processed from in-memory buffers and is not written to disk.
- Recognised speech is held in view-model memory for the active session and debug display; it is not intentionally persisted.
- There are no accounts, analytics SDKs, advertising identifiers, backend services, external LLMs or third-party speech APIs.
- FollowScript does not implement script upload, cloud synchronisation or application-managed network transmission.

## Files import

The system Files picker can provide a user-selected document from On My iPhone, iCloud Drive or an installed File Provider. FollowScript obtains security-scoped read access only while importing, releases it immediately afterwards, and does not retain a bookmark or copy of the source file. Extracted plain text replaces the current locally stored script only after user confirmation.

## Apple Speech processing

On iOS 18–25 the app sets `requiresOnDeviceRecognition` and refuses to start when that is unavailable. On iOS 26+, SpeechAnalyzer uses Apple-provided language assets and may download an asset on first use. Apple controls its frameworks, system permissions, model availability and OS behaviour; the project therefore does not claim a stronger guarantee for every device/language than those APIs provide.

The iOS 26.5 SDK integration has been compiled, but offline and live device behaviour remain unverified until the physical-device checklist in [testing.md](testing.md) is completed.

Recording is opt-in per presentation. Teleprompter-only mode retains no audio or video. Audio and audiovisual takes are local media files under Documents/Projects, with JSON metadata alongside them; transient camera and audio files are removed after a successful video join. The camera preview is visual only and the teleprompter text is not included in the saved movie.
