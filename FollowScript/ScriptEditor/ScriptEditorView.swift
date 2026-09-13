import SwiftUI

struct ScriptEditorView: View {
    @ObservedObject var model: AppModel
    @State private var presentsFileImporter = false
    @State private var isImporting = false
    @State private var importNotice: ImportNotice?

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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isImporting {
                        ProgressView()
                            .accessibilityLabel("Importing document")
                    }
                    Button("Import script", systemImage: "doc.badge.plus") {
                        presentsFileImporter = true
                    }
                    .disabled(isImporting)
                    .accessibilityHint("Choose a document from Files to replace the current script")

                    Button("Presentation settings", systemImage: "slider.horizontal.3") {
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
            .fileImporter(
                isPresented: $presentsFileImporter,
                allowedContentTypes: ScriptFileImporter.supportedContentTypes
            ) { result in
                if case .success(let url) = result {
                    importDocument(from: url)
                } else if case .failure(let error) = result {
                    importNotice = .error(error.localizedDescription)
                }
            }
            .alert(item: $importNotice) { notice in
                switch notice.kind {
                case .confirmation(let text, let filename):
                    Alert(
                        title: Text("Replace current script?"),
                        message: Text("Importing \(filename) will replace the text currently in the editor."),
                        primaryButton: .destructive(Text("Replace")) {
                            model.scriptText = text
                        },
                        secondaryButton: .cancel()
                    )
                case .error(let message):
                    Alert(
                        title: Text("Couldn’t Import Document"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }

    private func importDocument(from url: URL) {
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            do {
                let text = try await ScriptFileImporter.importText(from: url)
                if model.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    model.scriptText = text
                } else {
                    importNotice = .confirmation(text: text, filename: url.lastPathComponent)
                }
            } catch {
                importNotice = .error(error.localizedDescription)
            }
        }
    }
}

private struct ImportNotice: Identifiable {
    enum Kind {
        case confirmation(text: String, filename: String)
        case error(String)
    }

    let id = UUID()
    let kind: Kind

    static func confirmation(text: String, filename: String) -> ImportNotice {
        ImportNotice(kind: .confirmation(text: text, filename: filename))
    }

    static func error(_ message: String) -> ImportNotice {
        ImportNotice(kind: .error(message))
    }
}
