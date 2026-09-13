import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Presentation") {
                    VStack(alignment: .leading) {
                        Text("Font size: \(Int(model.settings.fontSize))")
                        Slider(value: $model.settings.fontSize, in: 28...72, step: 2)
                    }
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading) {
                        Text("Line spacing: \(Int(model.settings.lineSpacing))")
                        Slider(value: $model.settings.lineSpacing, in: 4...20, step: 2)
                    }
                    .accessibilityElement(children: .combine)

                    Picker("Text alignment", selection: $model.settings.textAlignment) {
                        ForEach(FollowScriptSettings.TextAlignmentOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Toggle("Highlight active phrase", isOn: $model.settings.highlightsActivePhrase)

                    Toggle("Mirror prompt horizontally", isOn: $model.settings.mirrorsPrompt)

                    Toggle("Flip prompt vertically", isOn: $model.settings.flipsPromptVertically)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
