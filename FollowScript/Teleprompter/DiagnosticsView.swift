import SwiftUI

#if DEBUG
struct DiagnosticsView: View {
    @ObservedObject var model: TeleprompterViewModel

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("State", value: model.trackingState.rawValue)
                LabeledContent("Search", value: model.searchMode.rawValue)
                LabeledContent("Script token", value: model.currentTokenIndex.map(String.init) ?? "—")
                LabeledContent("Confidence", value: model.confidence.formatted(.number.precision(.fractionLength(2))))
                LabeledContent("Candidate", value: model.candidateScore.formatted(.number.precision(.fractionLength(2))))
                Section("Recognised speech") {
                    Text(model.recognisedText.isEmpty ? "No speech yet" : model.recognisedText)
                }
                Section("Matched phrase") {
                    Text(matchedPhrase)
                }
            }
            .navigationTitle("Diagnostics")
        }
    }

    private var matchedPhrase: String {
        guard let range = model.matchedRange else { return "—" }
        return model.script.tokens[range].map(\.original).joined(separator: " ")
    }
}
#endif
