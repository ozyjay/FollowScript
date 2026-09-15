import AVKit
import SwiftUI

@MainActor
final class PresentationLibraryModel: ObservableObject {
    @Published private(set) var projects: [PresentationProject] = []
    @Published private(set) var legacyRecordings: [URL] = []
    @Published var errorMessage: String?

    func refresh() {
        do { projects = try PresentationProjectStore.projects() }
        catch { errorMessage = error.localizedDescription }
        legacyRecordings = LocalRecordingStore.recordings()
    }

    func rename(_ project: PresentationProject, to title: String) {
        do { _ = try PresentationProjectStore.rename(project, to: title); refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func saveScript(_ script: String) {
        do { _ = try PresentationProjectStore.createProject(script: script); refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ project: PresentationProject) {
        do { try PresentationProjectStore.delete(project); refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteLegacyRecording(_ url: URL) {
        do { try FileManager.default.removeItem(at: url); refresh() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct PresentationLibraryView: View {
    @ObservedObject var appModel: AppModel
    let onRecordProject: (PresentationProject) -> Void
    @StateObject private var library = PresentationLibraryModel()
    @State private var searchText = ""
    @State private var projectToDelete: PresentationProject?
    @State private var recordingToDelete: URL?
    @State private var projectToLoad: PresentationProject?
    @State private var projectToRecord: PresentationProject?
    @State private var legacyPlaybackURL: PlaybackItem?
    @Environment(\.dismiss) private var dismiss

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
                            }, onChanged: library.refresh)
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
                        .swipeActions {
                            Button("Delete", role: .destructive) { projectToDelete = project }
                        }
                    }
                }
                if !library.legacyRecordings.isEmpty {
                    Section("Earlier audio recordings") {
                        ForEach(library.legacyRecordings, id: \.self) { url in
                            HStack {
                                Button {
                                    legacyPlaybackURL = PlaybackItem(url: url)
                                } label: {
                                    Label(url.deletingPathExtension().lastPathComponent, systemImage: "play.circle")
                                        .lineLimit(1)
                                }
                                Spacer()
                                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                    .accessibilityLabel("Share \(url.lastPathComponent)")
                            }
                            .frame(minHeight: 44)
                            .swipeActions {
                                Button("Delete", role: .destructive) { recordingToDelete = url }
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
                RecordingPlayerView(url: item.url)
            }
            .confirmationDialog("Delete presentation and all its takes?", isPresented: Binding(
                get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }
            )) {
                Button("Delete presentation", role: .destructive) {
                    if let projectToDelete { library.delete(projectToDelete) }
                    projectToDelete = nil
                }
            } message: { Text("This removes the script and all recordings in this presentation.") }
            .confirmationDialog("Delete this recording?", isPresented: Binding(
                get: { recordingToDelete != nil }, set: { if !$0 { recordingToDelete = nil } }
            )) {
                Button("Delete recording", role: .destructive) {
                    if let recordingToDelete { library.deleteLegacyRecording(recordingToDelete) }
                    recordingToDelete = nil
                }
            }
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

    init(project: PresentationProject) { self.project = project }

    func refresh() {
        do { takes = try PresentationProjectStore.takes(for: project.id) }
        catch { errorMessage = error.localizedDescription }
    }

    func rename(to title: String) {
        do { project = try PresentationProjectStore.rename(project, to: title) }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ take: PresentationTake) {
        do { try PresentationProjectStore.delete(take); refresh() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct PresentationProjectDetailView: View {
    @StateObject private var model: PresentationProjectDetailModel
    let onUseScript: () -> Void
    let onRecord: () -> Void
    let onChanged: () -> Void
    @State private var showsRename = false
    @State private var draftTitle = ""
    @State private var takeToDelete: PresentationTake?
    @State private var playbackURL: PlaybackItem?

    init(project: PresentationProject, onUseScript: @escaping () -> Void,
         onRecord: @escaping () -> Void, onChanged: @escaping () -> Void) {
        _model = StateObject(wrappedValue: PresentationProjectDetailModel(project: project))
        self.onUseScript = onUseScript
        self.onRecord = onRecord
        self.onChanged = onChanged
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
                    HStack(spacing: 12) {
                        Button {
                            if let url { playbackURL = PlaybackItem(url: url) }
                        } label: {
                            Label(take.mode == .audio ? "Play audio" : "Play video",
                                  systemImage: take.mode == .audio ? "waveform" : "video")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityLabel("Play \(take.mode.title) from \(take.startedAt.formatted())")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(take.mode.title).font(.headline)
                            Text(take.startedAt, format: .dateTime.day().month().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                            Text(Duration.seconds(take.duration).formatted(.time(pattern: .minuteSecond)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let url {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                .accessibilityLabel("Share this take")
                        }
                    }
                    .frame(minHeight: 52)
                    .swipeActions {
                        Button("Delete", role: .destructive) { takeToDelete = take }
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
        .sheet(item: $playbackURL) { item in RecordingPlayerView(url: item.url) }
        .alert("Rename presentation", isPresented: $showsRename) {
            TextField("Name", text: $draftTitle)
            Button("Save") { model.rename(to: draftTitle); onChanged() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this take?", isPresented: Binding(
            get: { takeToDelete != nil }, set: { if !$0 { takeToDelete = nil } }
        )) {
            Button("Delete take", role: .destructive) {
                if let takeToDelete { model.delete(takeToDelete) }
                takeToDelete = nil
                onChanged()
            }
        } message: { Text("The recording will be removed from this device.") }
        .alert("Presentation needs attention", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) { Button("OK") { model.errorMessage = nil } }
            message: { Text(model.errorMessage ?? "The file operation could not be completed.") }
    }
}

private struct RecordingPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let player { VideoPlayer(player: player) }
                else { ProgressView() }
            }
            .navigationTitle(url.pathExtension.lowercased() == "caf" ? "Audio take" : "Video take")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
            .onAppear {
                player = AVPlayer(url: url)
                player?.play()
            }
            .onDisappear { player?.pause(); player = nil }
        }
    }
}

private struct PlaybackItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
