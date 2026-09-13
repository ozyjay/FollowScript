import SwiftUI

struct ScriptEditorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $model.scriptText)
                    .font(.body)
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Script")

                Button {
                    model.presentsTeleprompter = true
                } label: {
                    Label("Start Teleprompter", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canStart)
                .accessibilityHint("Starts listening and follows your place in the prepared script")
            }
            .padding()
            .navigationTitle("FollowScript")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Presentation settings", systemImage: "textformat") {
                        model.presentsSettings = true
                    }
                }
            }
            .sheet(isPresented: $model.presentsSettings) {
                SettingsView(model: model)
            }
            .fullScreenCover(isPresented: $model.presentsTeleprompter) {
                TeleprompterView(
                    scriptText: model.scriptText,
                    settings: $model.settings,
                    onExit: { model.presentsTeleprompter = false }
                )
            }
        }
    }
}
