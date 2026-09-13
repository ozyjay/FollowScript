# Versioning

FollowScript uses Xcode's marketing version and a Git-derived build number.

- `MARKETING_VERSION` is the user-facing release version and changes deliberately.
- `CURRENT_PROJECT_VERSION` is the number of commits reachable from the checked-out `HEAD`.

The shared FollowScript scheme runs `Scripts/set-git-build-number.sh` before each build action. The script evaluates `git rev-list --count HEAD` and writes the numeric result to the ignored `Config/GitBuildNumber.xcconfig`. `Config/Version.xcconfig` supplies that value to both Debug and Release builds and retains `1` as a valid fallback when a build does not run through the shared scheme.

Build from a full Git checkout when producing an archive. A shallow clone counts only the available history, while rebasing or rewriting history can reduce or reuse a count; confirm the resulting build number remains greater than any build previously uploaded to App Store Connect.
