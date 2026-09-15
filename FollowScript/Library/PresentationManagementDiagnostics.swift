import Foundation
import os

/// Opt-in lifecycle events for local presentation operations. Never log script or media content.
enum PresentationManagementDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FollowScript",
        category: "PresentationManagement"
    )

    static func event(
        enabled: Bool,
        operation: String,
        phase: String,
        identifier: UUID? = nil,
        error: Error? = nil
    ) {
        guard enabled else { return }
        let id = identifier?.uuidString ?? "none"
        if let error {
            let nsError = error as NSError
            logger.error(
                "operation=\(operation, privacy: .public) phase=\(phase, privacy: .public) id=\(id, privacy: .public) error_domain=\(nsError.domain, privacy: .public) error_code=\(nsError.code)"
            )
        } else {
            logger.info(
                "operation=\(operation, privacy: .public) phase=\(phase, privacy: .public) id=\(id, privacy: .public)"
            )
        }
    }
}
