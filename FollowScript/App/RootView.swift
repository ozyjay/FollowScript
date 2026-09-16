import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var hasFinishedLaunching = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if hasFinishedLaunching {
                ScriptEditorView(model: model)
            } else {
                AppLoadingView()
            }
        }
        .task {
            guard !hasFinishedLaunching else { return }

            do {
                try await Task.sleep(for: .milliseconds(2_500))
                hasFinishedLaunching = true
            } catch {
                // A cancelled launch task belongs to a view that is no longer visible.
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.flushPendingChanges()
            }
        }
    }
}

private struct AppLoadingView: View {
    private let versionInformation = AppVersionInformation()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.06, blue: 0.12),
                    Color(red: 0.04, green: 0.13, blue: 0.25),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Image("AppIconArtwork")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 184, height: 184)
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .shadow(color: .yellow.opacity(0.28), radius: 28)
                    .accessibilityHidden(true)

                VStack(spacing: 9) {
                    Text("FollowScript")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(versionInformation.displayText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }

                ProgressView()
                    .tint(.yellow)
                    .controlSize(.large)
                    .accessibilityHidden(true)
            }
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Loading FollowScript, version \(versionInformation.version), build \(versionInformation.build)."
        )
    }
}
