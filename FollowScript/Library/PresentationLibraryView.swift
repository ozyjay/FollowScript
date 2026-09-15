import SwiftUI

@MainActor
final class PresentationLibraryModel: ObservableObject {
    @Published private(set) var projects: [PresentationProject] = []
    @Published private(set) var legacyRecordings: [URL] = []
    @Published var errorMessage: String?
    private let diagnosticsEnabled: () -> Bool

    init(diagnosticsEnabled: @escaping () -> Bool = { false }) {
        self.diagnosticsEnabled = diagnosticsEnabled
    }

    func refresh() {
        do {
            projects = try PresentationProjectStore.projects()
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "libraryRefresh", phase: "completed")
        } catch {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "libraryRefresh", phase: "failed", error: error)
            errorMessage = error.localizedDescription
        }
        legacyRecordings = LocalRecordingStore.recordings()
    }

    func rename(_ project: PresentationProject, to title: String) {
        PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "renamePresentation", phase: "requested", identifier: project.id)
        do {
            _ = try PresentationProjectStore.rename(project, to: title)
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "renamePresentation", phase: "completed", identifier: project.id)
            refresh()
        } catch {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "renamePresentation", phase: "failed", identifier: project.id, error: error)
            errorMessage = error.localizedDescription
        }
    }

    func saveScript(_ script: String) {
        PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "savePresentation", phase: "requested")
        do {
            let project = try PresentationProjectStore.createProject(script: script)
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "savePresentation", phase: "completed", identifier: project.id)
            refresh()
        } catch {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "savePresentation", phase: "failed", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ project: PresentationProject) {
        PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deletePresentation", phase: "requested", identifier: project.id)
        do {
            try PresentationProjectStore.delete(project)
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deletePresentation", phase: "completed", identifier: project.id)
            refresh()
        } catch {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deletePresentation", phase: "failed", identifier: project.id, error: error)
            errorMessage = error.localizedDescription
        }
    }

    func deleteLegacyRecording(_ url: URL) {
        PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deleteEarlierRecording", phase: "requested")
        do {
            try FileManager.default.removeItem(at: url)
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deleteEarlierRecording", phase: "completed")
            refresh()
        } catch {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deleteEarlierRecording", phase: "failed", error: error)
            errorMessage = error.localizedDescription
        }
    }
}

struct PresentationLibraryView: View {
    @ObservedObject var appModel: AppModel
    let onRecordProject: (PresentationProject) -> Void
    @StateObject private var library: PresentationLibraryModel
    @State private var searchText = ""
    @State private var projectToDelete: PresentationProject?
    @State private var recordingToDelete: URL?
    @State private var projectToLoad: PresentationProject?
    @State private var projectToRecord: PresentationProject?
    @State private var legacyPlaybackURL: PlaybackItem?
    @Environment(\.dismiss) private var dismiss

    init(appModel: AppModel, onRecordProject: @escaping (PresentationProject) -> Void) {
        self.appModel = appModel
        self.onRecordProject = onRecordProject
        _library = StateObject(wrappedValue: PresentationLibraryModel(
            diagnosticsEnabled: { appModel.settings.logsTimestampedTrackingInformation }
        ))
    }

    private var filteredProjects: [PresentationProject] {
        guard !searchText.isEmpty else { return library.projects }
        return library.projects.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.script.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Presentations") {
                    if filteredProjects.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No saved presentations" : "No matches",
                            systemImage: searchText.isEmpty ? "folder" : "magnifyingglass",
                            description: Text(searchText.isEmpty
                                ? "Record audio or video to save a presentation and its takes here."
                                : "Try another name or phrase from a script.")
                        )
                    }
                    ForEach(filteredProjects) { project in
                        NavigationLink {
                            PresentationProjectDetailView(project: project, onUseScript: {
                                projectToLoad = project
                            }, onRecord: {
                                projectToRecord = project
                            }, onChanged: library.refresh,
                               diagnosticsEnabled: { appModel.settings.logsTimestampedTrackingInformation })
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.title).font(.headline)
                                let takeCount = (try? PresentationProjectStore.takes(for: project.id).count) ?? 0
                                Text("\(takeCount) take\(takeCount == 1 ? "" : "s")")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(project.createdAt, format: .dateTime.day().month().year())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) { projectToDelete = project }
                        }
                        .contextMenu {
                            Button("Delete presentation", systemImage: "trash", role: .destructive) {
                                projectToDelete = project
                            }
                        }
                    }
                }
                if !library.legacyRecordings.isEmpty {
                    Section("Earlier audio recordings") {
                        ForEach(library.legacyRecordings, id: \.self) { url in
                            Button {
                                legacyPlaybackURL = PlaybackItem(url: url)
                            } label: {
                                Label(url.deletingPathExtension().lastPathComponent, systemImage: "play.circle")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the audio player")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { recordingToDelete = url }
                                LocalRecordingShareAction(url: url)
                            }
                            .contextMenu {
                                LocalRecordingShareAction(url: url)
                                Button("Delete recording", systemImage: "trash", role: .destructive) {
                                    recordingToDelete = url
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search presentations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save script", systemImage: "doc.badge.plus") {
                        library.saveScript(appModel.scriptText)
                    }
                    .disabled(appModel.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint("Create a saved presentation without recording a take")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear(perform: library.refresh)
            .refreshable { library.refresh() }
            .sheet(item: $legacyPlaybackURL) { item in
                RecordingPlaybackView(url: item.url,
                                      diagnosticsEnabled: appModel.settings.logsTimestampedTrackingInformation)
            }
            .confirmationDialog("Delete presentation?", isPresented: Binding(
                get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete presentation", role: .destructive) {
                    if let projectToDelete { library.delete(projectToDelete) }
                    projectToDelete = nil
                }
                Button("Cancel", role: .cancel) { projectToDelete = nil }
            } message: { Text("This removes the script and all recordings in this presentation.") }
            .confirmationDialog("Delete this recording?", isPresented: Binding(
                get: { recordingToDelete != nil }, set: { if !$0 { recordingToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete recording", role: .destructive) {
                    if let recordingToDelete { library.deleteLegacyRecording(recordingToDelete) }
                    recordingToDelete = nil
                }
                Button("Cancel", role: .cancel) { recordingToDelete = nil }
            } message: { Text("This recording will be removed from this device.") }
            .confirmationDialog("Replace the script in the editor?", isPresented: Binding(
                get: { projectToLoad != nil }, set: { if !$0 { projectToLoad = nil } }
            )) {
                Button("Use saved script") {
                    if let projectToLoad {
                        appModel.scriptText = projectToLoad.script
                        appModel.selectedProject = projectToLoad
                    }
                    projectToLoad = nil
                    dismiss()
                }
            } message: { Text("Your current editor text will be replaced by this saved script.") }
            .confirmationDialog("Use this presentation for another take?", isPresented: Binding(
                get: { projectToRecord != nil }, set: { if !$0 { projectToRecord = nil } }
            )) {
                Button("Choose recording mode") {
                    if let projectToRecord { onRecordProject(projectToRecord) }
                    projectToRecord = nil
                    dismiss()
                }
            } message: { Text("The saved script will replace your current editor text.") }
            .alert("Library needs attention", isPresented: Binding(
                get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } }
            )) { Button("OK") { library.errorMessage = nil } }
                message: { Text(library.errorMessage ?? "The file operation could not be completed.") }
        }
    }
}

@MainActor
final class PresentationProjectDetailModel: ObservableObject {
    @Published private(set) var project: PresentationProject
    @Published private(set) var takes: [PresentationTake] = []
    @Published var errorMessage: String?
    private let diagnosticsEnabled: () -> Bool

    init(project: PresentationProject, diagnosticsEnabled: @escaping () -> Bool = { false }) {
        self.project = project
        self.diagnosticsEnabled = diagnosticsEnabled
    }

    func refresh() {
        do {
            takes = try PresentationProjectStore.takes(for: project.id)
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "takesRefresh", phase: "completed", identifier: project.id)
        } catch {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "takesRefresh", phase: "failed", identifier: project.id, error: error)
            errorMessage = error.localizedDescription
        }
    }

    func rename(to title: String) {
        PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "renamePresentation", phase: "requested", identifier: project.id)
        do {
            project = try PresentationProjectStore.rename(project, to: title)
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "renamePresentation", phase: "completed", identifier: project.id)
        } catch {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "renamePresentation", phase: "failed", identifier: project.id, error: error)
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func delete(_ take: PresentationTake) -> Bool {
        PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deleteTake", phase: "requested", identifier: take.id)
        do {
            try PresentationProjectStore.delete(take)
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deleteTake", phase: "completed", identifier: take.id)
            refresh()
            return true
        } catch {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deleteTake", phase: "failed", identifier: take.id, error: error)
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct PresentationProjectDetailView: View {
    @StateObject private var model: PresentationProjectDetailModel
    let onUseScript: () -> Void
    let onRecord: () -> Void
    let onChanged: () -> Void
    let diagnosticsEnabled: () -> Bool
    @State private var showsRename = false
    @State private var draftTitle = ""
    @State private var takeToDelete: PresentationTake?
    @State private var playbackURL: PlaybackItem?

    init(project: PresentationProject, onUseScript: @escaping () -> Void,
         onRecord: @escaping () -> Void, onChanged: @escaping () -> Void,
         diagnosticsEnabled: @escaping () -> Bool) {
        _model = StateObject(wrappedValue: PresentationProjectDetailModel(
            project: project, diagnosticsEnabled: diagnosticsEnabled
        ))
        self.onUseScript = onUseScript
        self.onRecord = onRecord
        self.onChanged = onChanged
        self.diagnosticsEnabled = diagnosticsEnabled
    }

    var body: some View {
        List {
            Section("Script") {
                Text(model.project.script)
                    .lineLimit(5)
                    .foregroundStyle(.secondary)
                Button("Use this script in editor", systemImage: "text.document") { onUseScript() }
                    .frame(minHeight: 44)
                Button("Record another take", systemImage: "record.circle") { onRecord() }
                    .frame(minHeight: 44)
            }
            Section("Takes") {
                if model.takes.isEmpty {
                    Text("No completed takes yet").foregroundStyle(.secondary)
                }
                ForEach(model.takes) { take in
                    let url = try? PresentationProjectStore.mediaURL(for: take)
                    Button {
                        if let url { playbackURL = PlaybackItem(url: url, recordingID: take.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: take.mode == .audio ? "waveform" : "video")
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(take.mode.title).font(.headline)
                                Text(take.startedAt, format: .dateTime.day().month().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(Duration.seconds(take.duration).formatted(.time(pattern: .minuteSecond)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(take.mode.title) from \(take.startedAt.formatted())")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) { takeToDelete = take }
                        if let url {
                            LocalRecordingShareAction(url: url)
                        }
                    }
                    .contextMenu {
                        if let url { LocalRecordingShareAction(url: url) }
                        Button("Delete take", systemImage: "trash", role: .destructive) {
                            takeToDelete = take
                        }
                    }
                }
            }
        }
        .navigationTitle(model.project.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rename", systemImage: "pencil") {
                    draftTitle = model.project.title
                    showsRename = true
                }
            }
        }
        .onAppear(perform: model.refresh)
        .sheet(item: $playbackURL) { item in
            RecordingPlaybackView(url: item.url, recordingID: item.recordingID,
                                  diagnosticsEnabled: diagnosticsEnabled())
        }
        .alert("Rename presentation", isPresented: $showsRename) {
            TextField("Name", text: $draftTitle)
            Button("Save") { model.rename(to: draftTitle); onChanged() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this take?", isPresented: Binding(
            get: { takeToDelete != nil }, set: { if !$0 { takeToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete take", role: .destructive) {
                if let takeToDelete, model.delete(takeToDelete) { onChanged() }
                takeToDelete = nil
            }
            Button("Cancel", role: .cancel) { takeToDelete = nil }
        } message: { Text("This recording will be removed from this device.") }
        .alert("Presentation needs attention", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) { Button("OK") { model.errorMessage = nil } }
            message: { Text(model.errorMessage ?? "The file operation could not be completed.") }
    }
}

private struct PlaybackItem: Identifiable {
    let url: URL
    var recordingID: UUID? = nil
    var id: String { url.absoluteString }
}


private struct LocalRecordingShareAction: View {
    let url: URL

    var body: some View {
        ShareLink(item: LocalRecordingFile(url: url),
                  preview: SharePreview(url.lastPathComponent)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}
