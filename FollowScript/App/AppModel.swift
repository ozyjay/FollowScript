import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    private enum Keys {
        static let script = "currentScript"
        static let settings = "followScriptSettings"
    }

    @Published var scriptText: String {
        didSet { defaults.set(scriptText, forKey: Keys.script) }
    }

    @Published var settings: FollowScriptSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                defaults.set(data, forKey: Keys.settings)
            }
        }
    }

    @Published var presentsTeleprompter = false
    @Published var presentsSettings = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scriptText = defaults.string(forKey: Keys.script) ?? Self.sampleScript
        if let data = defaults.data(forKey: Keys.settings),
           let stored = try? JSONDecoder().decode(FollowScriptSettings.self, from: data) {
            settings = stored
        } else {
            settings = FollowScriptSettings()
        }
    }

    var canStart: Bool {
        !scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let sampleScript = """
    Welcome to FollowScript. This teleprompter moves with your voice, so you can focus on your message instead of matching a fixed scrolling speed.

    Edit or replace this sample, then tap Start Teleprompter. As you speak, the highlighted phrase and reading position will follow your place in the prepared script.
    """
}
