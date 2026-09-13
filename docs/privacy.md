# Privacy

FollowScript requests microphone access and Apple speech-recognition authorisation solely to estimate the speaker’s current position in their prepared script.

## Stored locally

- The current script is stored in app `UserDefaults`.
- Font size, line spacing, alignment and highlighting preference are stored in `UserDefaults`.

## Not stored or added

- Microphone audio is processed from in-memory buffers and is not written to disk.
- Recognised speech is held in view-model memory for the active session and debug display; it is not intentionally persisted.
- There are no accounts, analytics SDKs, advertising identifiers, backend services, external LLMs or third-party speech APIs.
- FollowScript does not implement script upload, cloud synchronisation or application-managed network transmission.

## Apple Speech processing

On iOS 18–25 the app sets `requiresOnDeviceRecognition` and refuses to start when that is unavailable. On iOS 26+, SpeechAnalyzer uses Apple-provided language assets and may download an asset on first use. Apple controls its frameworks, system permissions, model availability and OS behaviour; the project therefore does not claim a stronger guarantee for every device/language than those APIs provide.

The iOS 26.5 SDK integration has been compiled, but offline and live device behaviour remain unverified until the physical-device checklist in [testing.md](testing.md) is completed.
