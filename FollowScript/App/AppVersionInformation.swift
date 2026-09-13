import Foundation

struct AppVersionInformation: Equatable {
    let version: String
    let build: String

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        version = infoDictionary["CFBundleShortVersionString"] as? String ?? "—"
        build = infoDictionary["CFBundleVersion"] as? String ?? "—"
    }

    var displayText: String {
        "Version \(version) • Build \(build)"
    }
}
