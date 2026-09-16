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
    static func root(_ override: URL? = nil) throws -> URL {
        if let override {
            try FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let root = documents.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func createProject(
        title: String? = nil,
        script: String,
        rootURL: URL? = nil
    ) throws -> PresentationProject {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = PresentationProject(
            id: UUID(),
            title: trimmedTitle.flatMap { $0.isEmpty ? nil : $0 }
                ?? "Presentation \(Date().formatted(date: .abbreviated, time: .shortened))",
            script: script,
            createdAt: Date()
        )
        try write(project, rootURL: rootURL)
        return project
    }

    static func updateScript(
        _ project: PresentationProject,
        to script: String,
        rootURL: URL? = nil
    ) throws -> PresentationProject {
        let updated = PresentationProject(
            id: project.id,
            title: project.title,
            script: script,
            createdAt: project.createdAt
        )
        try write(updated, rootURL: rootURL)
        return updated
    }

    private static func write(_ project: PresentationProject, rootURL: URL?) throws {
        let folder = try projectFolder(project.id, rootURL: rootURL)
        try JSONEncoder().encode(project).write(
            to: folder.appendingPathComponent("project.json"),
            options: .atomic
        )
    }

    static func projectFolder(_ id: UUID, rootURL: URL? = nil) throws -> URL {
        let folder = try root(rootURL).appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func mediaFiles() -> [URL] {
        guard let root = try? root(), let folders = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return folders.flatMap { folder -> [URL] in
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
            return files.filter { ["caf", "m4a", "mov"].contains($0.pathExtension.lowercased()) }
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func saveTake(_ take: PresentationTake, source: URL, rootURL: URL? = nil) throws -> URL {
        let folder = try projectFolder(take.projectID, rootURL: rootURL)
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

extension PresentationProjectStore {
    static func projects(rootURL: URL? = nil) throws -> [PresentationProject] {
        let folders = try FileManager.default.contentsOfDirectory(
            at: root(rootURL), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return folders.compactMap { folder in
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")),
                  let project = try? JSONDecoder().decode(PresentationProject.self, from: data),
                  folder.lastPathComponent == project.id.uuidString else { return nil }
            return project
        }.sorted { $0.createdAt > $1.createdAt }
    }

    static func takes(for projectID: UUID, rootURL: URL? = nil) throws -> [PresentationTake] {
        let files = try FileManager.default.contentsOfDirectory(
            at: projectFolder(projectID, rootURL: rootURL), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return files.filter { $0.pathExtension == "json" && $0.lastPathComponent != "project.json" }
            .compactMap { file in
                guard let data = try? Data(contentsOf: file),
                      let take = try? JSONDecoder().decode(PresentationTake.self, from: data),
                      take.projectID == projectID,
                      file.deletingPathExtension().lastPathComponent == take.id.uuidString,
                      (try? mediaURL(for: take, rootURL: rootURL).checkResourceIsReachable()) == true else { return nil }
                return take
            }.sorted { $0.startedAt > $1.startedAt }
    }

    static func mediaURL(for take: PresentationTake, rootURL: URL? = nil) throws -> URL {
        guard take.mediaFilename == URL(fileURLWithPath: take.mediaFilename).lastPathComponent,
              ["caf", "m4a", "mov"].contains(URL(fileURLWithPath: take.mediaFilename).pathExtension.lowercased()) else {
            throw PresentationLibraryError.invalidMediaFilename
        }
        return try projectFolder(take.projectID, rootURL: rootURL).appendingPathComponent(take.mediaFilename)
    }

    static func rename(_ project: PresentationProject, to title: String, rootURL: URL? = nil) throws -> PresentationProject {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PresentationLibraryError.emptyTitle }
        let updated = PresentationProject(id: project.id, title: trimmed, script: project.script,
                                          createdAt: project.createdAt)
        try write(updated, rootURL: rootURL)
        return updated
    }

    static func delete(_ take: PresentationTake, rootURL: URL? = nil) throws {
        let folder = try projectFolder(take.projectID, rootURL: rootURL)
        let metadata = folder.appendingPathComponent("\(take.id).json")
        let media = try mediaURL(for: take, rootURL: rootURL)
        // Remove metadata first so a partially deleted take is not offered for playback.
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.removeItem(at: media)
    }

    static func delete(_ project: PresentationProject, rootURL: URL? = nil) throws {
        try FileManager.default.removeItem(at: projectFolder(project.id, rootURL: rootURL))
    }
}

enum PresentationLibraryError: LocalizedError {
    case emptyTitle, invalidMediaFilename
    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Enter a name for this presentation."
        case .invalidMediaFilename: "This recording has an invalid file name."
        }
    }
}
