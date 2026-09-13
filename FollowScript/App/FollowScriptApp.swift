import SwiftUI

@main
struct FollowScriptApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ScriptEditorView(model: model)
        }
    }
}
