import Foundation

enum PresentationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case teleprompter
    case audio
    case audiovisual

    var id: String { rawValue }
    var title: String {
        switch self {
        case .teleprompter: "Teleprompter"
        case .audio: "Audio recording"
        case .audiovisual: "Video recording"
        }
    }
}

struct PresentationProject: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let script: String
    let createdAt: Date
}

struct PresentationTake: Codable, Identifiable, Sendable {
    let id: UUID
    let projectID: UUID
    let mode: PresentationMode
    let startedAt: Date
    let endedAt: Date
    let mediaFilename: String
    let duration: TimeInterval
}

/// JSON metadata and media files live under Documents/Projects; no media enters app settings.
enum PresentationProjectStore {
    static func root() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let root = documents.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func createProject(script: String) throws -> PresentationProject {
        let project = PresentationProject(id: UUID(), title: "Presentation \(Date().formatted(date: .abbreviated, time: .shortened))",
                                          script: script, createdAt: Date())
        let folder = try projectFolder(project.id)
        try JSONEncoder().encode(project).write(to: folder.appendingPathComponent("project.json"), options: .atomic)
        return project
    }

    static func projectFolder(_ id: UUID) throws -> URL {
        let folder = try root().appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func mediaFiles() -> [URL] {
        guard let root = try? root(), let folders = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return folders.flatMap { folder -> [URL] in
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
            return files.filter { ["caf", "mov"].contains($0.pathExtension.lowercased()) }
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func saveTake(_ take: PresentationTake, source: URL) throws -> URL {
        let folder = try projectFolder(take.projectID)
        let destination = folder.appendingPathComponent(take.mediaFilename)
        try FileManager.default.moveItem(at: source, to: destination)
        do {
            try JSONEncoder().encode(take).write(to: folder.appendingPathComponent("\(take.id).json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }
}
