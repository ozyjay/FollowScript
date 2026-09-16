import SwiftUI

struct ScriptEditorView: View {
    @ObservedObject var model: AppModel
    @State private var presentsModePicker = false
    @State private var presentsTeleprompter = false
    @State private var selectedMode: PresentationMode = .teleprompter
    @State private var presentsFileImporter = false
    @State private var isImporting = false
    @State private var importNotice: ImportNotice?
    @State private var presentsRenamePresentation = false
    @State private var draftPresentationTitle = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.selectedProject != nil {
                    VStack(spacing: 16) {
                        TextEditor(text: $model.scriptText)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("Presentation script")

                        Button {
                            model.flushPendingChanges()
                            selectedMode = model.settings.lastPresentationMode
                            presentsModePicker = true
                        } label: {
                            Label("Start Presentation", systemImage: "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!model.canStart)
                        .accessibilityHint("Choose teleprompter, audio or video presentation")
                    }
                    .padding()
                } else {
                    ContentUnavailableView {
                        Label("No Presentation", systemImage: "rectangle.on.rectangle.slash")
                    } description: {
                        Text("Return to Library and select or create a presentation.")
                    } actions: {
                        Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(model.selectedProject?.title ?? "FollowScript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        model.flushPendingChanges()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu("More options", systemImage: "ellipsis.circle") {
                        Button("Rename presentation", systemImage: "pencil") {
                            draftPresentationTitle = model.selectedProject?.title ?? ""
                            presentsRenamePresentation = true
                        }
                        .disabled(model.selectedProject == nil)
                        Button("Import script", systemImage: "doc.badge.plus") {
                            presentsFileImporter = true
                        }
                        .disabled(isImporting || model.selectedProject == nil)
                    }
                    if isImporting {
                        ProgressView()
                            .accessibilityLabel("Importing document")
                    }
                }
            }
            .confirmationDialog("Presentation mode", isPresented: $presentsModePicker, titleVisibility: .visible) {
                ForEach(PresentationMode.allCases) { mode in
                    Button(mode.title) {
                        selectedMode = mode
                        model.settings.lastPresentationMode = mode
                        presentsTeleprompter = true
                    }
                }
            } message: {
                Text("Choose how to use this presentation. Recording modes save each take with it.")
            }
            .fullScreenCover(isPresented: $presentsTeleprompter) {
                TeleprompterView(
                    scriptText: model.scriptText,
                    mode: selectedMode,
                    project: model.selectedProject,
                    ignoresSquareBracketedText: model.settings.ignoresSquareBracketedText,
                    removesExtraWhitespace: model.settings.removesExtraWhitespace,
                    logsTimestampedTrackingInformation: model.settings.logsTimestampedTrackingInformation,
                    settings: $model.settings,
                    onExit: { presentsTeleprompter = false }
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
                        title: Text("Replace presentation script?"),
                        message: Text("Importing \(filename) will replace the script in this presentation."),
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
            .alert("Rename presentation", isPresented: $presentsRenamePresentation) {
                TextField("Presentation name", text: $draftPresentationTitle)
                Button("Save") { model.renameSelectedPresentation(to: draftPresentationTitle) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Presentation needs attention", isPresented: Binding(
                get: { model.presentationErrorMessage != nil },
                set: { if !$0 { model.presentationErrorMessage = nil } }
            )) {
                Button("OK") { model.presentationErrorMessage = nil }
            } message: {
                Text(model.presentationErrorMessage ?? "The presentation could not be saved.")
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
