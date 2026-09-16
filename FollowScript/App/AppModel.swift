import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    private enum Keys {
        static let legacyScript = "currentScript"
        static let selectedPresentationID = "selectedPresentationID"
        static let migratedStandaloneScript = "migratedStandaloneScriptToPresentation"
        static let settings = "followScriptSettings"
    }

    @Published var scriptText: String {
        didSet { scriptDidChange() }
    }

    @Published private(set) var selectedProject: PresentationProject?
    @Published var presentationErrorMessage: String?

    @Published var settings: FollowScriptSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                defaults.set(data, forKey: Keys.settings)
            }
        }
    }

    @Published var presentsSettings = false

    private let defaults: UserDefaults
    private let projectsRootURL: URL?
    private var hasFinishedInitialisation = false
    private var pendingProjectSave: PresentationProject?
    private var scriptSaveTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, projectsRootURL: URL? = nil) {
        self.defaults = defaults
        self.projectsRootURL = projectsRootURL
        scriptText = ""
        selectedProject = nil
        if let data = defaults.data(forKey: Keys.settings),
           let stored = try? JSONDecoder().decode(FollowScriptSettings.self, from: data) {
            settings = stored
        } else {
            settings = FollowScriptSettings()
        }

        loadInitialPresentation()
        hasFinishedInitialisation = true
    }

    var canStart: Bool {
        selectedProject != nil
            && !scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func createPresentation(title: String, script: String = "") -> PresentationProject? {
        flushPendingChanges()
        do {
            let project = try PresentationProjectStore.createProject(
                title: title,
                script: script,
                rootURL: projectsRootURL
            )
            selectPresentation(project)
            return project
        } catch {
            presentationErrorMessage = error.localizedDescription
            return nil
        }
    }

    func selectPresentation(_ project: PresentationProject) {
        flushPendingChanges()
        selectedProject = project
        scriptText = project.script
        pendingProjectSave = nil
        defaults.set(project.id.uuidString, forKey: Keys.selectedPresentationID)
    }

    func renameSelectedPresentation(to title: String) {
        guard let selectedProject else { return }
        flushPendingChanges()
        do {
            self.selectedProject = try PresentationProjectStore.rename(
                selectedProject,
                to: title,
                rootURL: projectsRootURL
            )
        } catch {
            presentationErrorMessage = error.localizedDescription
        }
    }

    func presentationWasRenamed(_ project: PresentationProject) {
        guard selectedProject?.id == project.id else { return }
        selectedProject = project
    }

    func presentationWasDeleted(_ project: PresentationProject) {
        guard selectedProject?.id == project.id else { return }
        scriptSaveTask?.cancel()
        pendingProjectSave = nil
        selectedProject = nil
        scriptText = ""
        defaults.removeObject(forKey: Keys.selectedPresentationID)

        do {
            if let nextProject = try PresentationProjectStore.projects(rootURL: projectsRootURL).first {
                selectPresentation(nextProject)
            } else {
                _ = createPresentation(title: "Untitled Presentation")
            }
        } catch {
            presentationErrorMessage = error.localizedDescription
        }
    }

    func flushPendingChanges() {
        scriptSaveTask?.cancel()
        scriptSaveTask = nil
        guard let project = pendingProjectSave else { return }
        pendingProjectSave = nil

        do {
            _ = try PresentationProjectStore.updateScript(
                project,
                to: project.script,
                rootURL: projectsRootURL
            )
        } catch {
            pendingProjectSave = project
            presentationErrorMessage = error.localizedDescription
        }
    }

    private func loadInitialPresentation() {
        do {
            let projects = try PresentationProjectStore.projects(rootURL: projectsRootURL)
            let storedID = defaults.string(forKey: Keys.selectedPresentationID).flatMap(UUID.init(uuidString:))

            if let selected = projects.first(where: { $0.id == storedID }) {
                selectedProject = selected
                scriptText = selected.script
                return
            }

            if defaults.bool(forKey: Keys.migratedStandaloneScript), let mostRecent = projects.first {
                selectedProject = mostRecent
                scriptText = mostRecent.script
                defaults.set(mostRecent.id.uuidString, forKey: Keys.selectedPresentationID)
                return
            }

            let legacyScript = defaults.string(forKey: Keys.legacyScript) ?? Self.sampleScript
            let migrated = try PresentationProjectStore.createProject(
                title: "My Presentation",
                script: legacyScript,
                rootURL: projectsRootURL
            )
            selectedProject = migrated
            scriptText = migrated.script
            defaults.set(migrated.id.uuidString, forKey: Keys.selectedPresentationID)
            defaults.set(true, forKey: Keys.migratedStandaloneScript)
            defaults.removeObject(forKey: Keys.legacyScript)
        } catch {
            presentationErrorMessage = error.localizedDescription
        }
    }

    private func scriptDidChange() {
        guard hasFinishedInitialisation,
              let selectedProject,
              selectedProject.script != scriptText else { return }
        let updated = PresentationProject(
            id: selectedProject.id,
            title: selectedProject.title,
            script: scriptText,
            createdAt: selectedProject.createdAt
        )
        self.selectedProject = updated
        pendingProjectSave = updated
        scheduleScriptSave()
    }

    private func scheduleScriptSave() {
        scriptSaveTask?.cancel()
        scriptSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                self?.flushPendingChanges()
            } catch {
                // A newer edit owns the replacement save task.
            }
        }
    }

    static let sampleScript = """
    Welcome to FollowScript. This teleprompter moves with your voice, so you can focus on your message instead of matching a fixed scrolling speed.

    Edit or replace this sample, then tap Start Presentation. As you speak, the highlighted phrase and reading position will follow your place in the prepared script.
    """
}
