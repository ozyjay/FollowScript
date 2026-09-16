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

    @discardableResult
    func delete(_ project: PresentationProject) -> Bool {
        PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deletePresentation", phase: "requested", identifier: project.id)
        do {
            try PresentationProjectStore.delete(project)
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deletePresentation", phase: "completed", identifier: project.id)
            refresh()
            return true
        } catch {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "deletePresentation", phase: "failed", identifier: project.id, error: error)
            errorMessage = error.localizedDescription
            return false
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
    @State private var legacyPlaybackURL: PlaybackItem?
    @State private var presentsNewPresentation = false
    @State private var presentsNewPresentationEditor = false
    @State private var draftPresentationTitle = ""

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
                                ? "Create a presentation, add its script, then present or record from it."
                                : "Try another name or phrase from a script.")
                        )
                    }
                    ForEach(filteredProjects) { project in
                        NavigationLink {
                            PresentationProjectDetailView(
                                project: project,
                                appModel: appModel,
                                onRecord: onRecordProject,
                                onChanged: library.refresh,
                                onRenamed: { renamedProject in
                                    appModel.presentationWasRenamed(renamedProject)
                                    library.refresh()
                                }, diagnosticsEnabled: {
                                    appModel.settings.logsTimestampedTrackingInformation
                                }
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.title).font(.headline)
                                    let takeCount = (try? PresentationProjectStore.takes(for: project.id).count) ?? 0
                                    Text("\(takeCount) take\(takeCount == 1 ? "" : "s")")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Text(project.createdAt, format: .dateTime.day().month().year())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if appModel.selectedProject?.id == project.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel("Selected presentation")
                                }
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) { delete(project) }
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
                            legacyRecordingRow(url)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search presentations")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("AppIconArtwork")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityHidden(true)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("New presentation", systemImage: "plus") {
                        draftPresentationTitle = ""
                        presentsNewPresentation = true
                    }
                    .accessibilityHint("Create and edit a new presentation")
                    Button("Settings", systemImage: "slider.horizontal.3") {
                        appModel.presentsSettings = true
                    }
                }
            }
            .onAppear(perform: library.refresh)
            .refreshable { library.refresh() }
            .sheet(item: $legacyPlaybackURL) { item in
                RecordingPlaybackView(url: item.url,
                                      diagnosticsEnabled: appModel.settings.logsTimestampedTrackingInformation)
            }
            .sheet(isPresented: $presentsNewPresentationEditor, onDismiss: library.refresh) {
                ScriptEditorView(model: appModel)
            }
            .sheet(isPresented: $appModel.presentsSettings) {
                SettingsView(model: appModel)
            }
            .alert("Delete presentation?", isPresented: Binding(
                get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }
            )) {
                Button("Delete presentation", role: .destructive) {
                    if let projectToDelete { delete(projectToDelete) }
                    projectToDelete = nil
                }
                Button("Cancel", role: .cancel) { projectToDelete = nil }
            } message: { Text("This removes the script and all recordings in this presentation.") }
            .alert("Delete this recording?", isPresented: Binding(
                get: { recordingToDelete != nil }, set: { if !$0 { recordingToDelete = nil } }
            )) {
                Button("Delete recording", role: .destructive) {
                    if let recordingToDelete { library.deleteLegacyRecording(recordingToDelete) }
                    recordingToDelete = nil
                }
                Button("Cancel", role: .cancel) { recordingToDelete = nil }
            } message: { Text("This recording will be removed from this device.") }
            .alert("New presentation", isPresented: $presentsNewPresentation) {
                TextField("Presentation name", text: $draftPresentationTitle)
                Button("Create") {
                    let title = draftPresentationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if appModel.createPresentation(
                        title: title.isEmpty ? "Untitled Presentation" : title
                    ) != nil {
                        Task { @MainActor in
                            await Task.yield()
                            presentsNewPresentationEditor = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Create an empty presentation, then type or import its script.")
            }
            .alert("Library needs attention", isPresented: Binding(
                get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } }
            )) { Button("OK") { library.errorMessage = nil } }
                message: { Text(library.errorMessage ?? "The file operation could not be completed.") }
            .alert("Presentation needs attention", isPresented: Binding(
                get: { appModel.presentationErrorMessage != nil },
                set: { if !$0 { appModel.presentationErrorMessage = nil } }
            )) {
                Button("OK") { appModel.presentationErrorMessage = nil }
            } message: {
                Text(appModel.presentationErrorMessage ?? "The presentation could not be saved.")
            }
        }
    }

    private func delete(_ project: PresentationProject) {
        if library.delete(project) {
            appModel.presentationWasDeleted(project)
            library.refresh()
        }
    }

    private func legacyRecordingRow(_ url: URL) -> some View {
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
            if let refreshedProject = try PresentationProjectStore.projects().first(where: { $0.id == project.id }) {
                project = refreshedProject
            }
            takes = try PresentationProjectStore.takes(for: project.id)
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "takesRefresh", phase: "completed", identifier: project.id)
        } catch {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "takesRefresh", phase: "failed", identifier: project.id, error: error)
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func rename(to title: String) -> Bool {
        PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "renamePresentation", phase: "requested", identifier: project.id)
        do {
            project = try PresentationProjectStore.rename(project, to: title)
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "renamePresentation", phase: "completed", identifier: project.id)
            return true
        } catch {
            PresentationManagementDiagnostics.event(enabled: diagnosticsEnabled(), operation: "renamePresentation", phase: "failed", identifier: project.id, error: error)
            errorMessage = error.localizedDescription
            return false
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
    @ObservedObject var appModel: AppModel
    let onRecord: (PresentationProject) -> Void
    let onChanged: () -> Void
    let onRenamed: (PresentationProject) -> Void
    let diagnosticsEnabled: () -> Bool
    @State private var showsRename = false
    @State private var draftTitle = ""
    @State private var titleSelection: TextSelection?
    @State private var takeToDelete: PresentationTake?
    @State private var playbackURL: PlaybackItem?
    @State private var presentsEditor = false

    init(project: PresentationProject, appModel: AppModel,
         onRecord: @escaping (PresentationProject) -> Void, onChanged: @escaping () -> Void,
         onRenamed: @escaping (PresentationProject) -> Void,
         diagnosticsEnabled: @escaping () -> Bool) {
        _model = StateObject(wrappedValue: PresentationProjectDetailModel(
            project: project, diagnosticsEnabled: diagnosticsEnabled
        ))
        self.appModel = appModel
        self.onRecord = onRecord
        self.onChanged = onChanged
        self.onRenamed = onRenamed
        self.diagnosticsEnabled = diagnosticsEnabled
    }

    var body: some View {
        List {
            Section("Script") {
                Text(model.project.script)
                    .lineLimit(5)
                    .foregroundStyle(.secondary)
                Button("Edit presentation", systemImage: "square.and.pencil") {
                    appModel.selectPresentation(model.project)
                    presentsEditor = true
                }
                    .frame(minHeight: 44)
                Button("Present or record", systemImage: "play.circle") { onRecord(model.project) }
                    .frame(minHeight: 44)
                    .disabled(model.project.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) {
                            if model.delete(take) { onChanged() }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if let url { LocalRecordingShareAction(url: url) }
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
                    titleSelection = TextSelection(range: draftTitle.startIndex..<draftTitle.endIndex)
                    showsRename = true
                }
            }
        }
        .onAppear(perform: model.refresh)
        .sheet(item: $playbackURL) { item in
            RecordingPlaybackView(url: item.url, recordingID: item.recordingID,
                                  diagnosticsEnabled: diagnosticsEnabled())
        }
        .sheet(isPresented: $presentsEditor, onDismiss: {
            model.refresh()
            onChanged()
        }) {
            ScriptEditorView(model: appModel)
        }
        .alert("Rename presentation", isPresented: $showsRename) {
            TextField("Name", text: $draftTitle, selection: $titleSelection)
            Button("Save") {
                if model.rename(to: draftTitle) {
                    onRenamed(model.project)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete this take?", isPresented: Binding(
            get: { takeToDelete != nil }, set: { if !$0 { takeToDelete = nil } }
        )) {
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
