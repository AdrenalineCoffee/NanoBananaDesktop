import Foundation

final class ConceptProjectStore {
    private let projectsDirectory: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(projectsDirectory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.projectsDirectory = try projectsDirectory ?? AppDirectories.conceptProjectsDirectory(fileManager: fileManager)
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(at: self.projectsDirectory, withIntermediateDirectories: true)
    }

    func loadLastProjectOrCreateDefault(defaultModel: String = AppConfig.defaultModel) throws -> ConceptProjectState {
        if let lastID = loadLastOpenedProjectID(),
           let loaded = try loadProject(id: lastID) {
            return loaded
        }

        let directories = try fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let projectDirectories = directories.filter { $0.hasDirectoryPath }
        let sorted = try projectDirectories.sorted { lhs, rhs in
            let lhsDate = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let rhsDate = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return lhsDate > rhsDate
        }

        for directory in sorted {
            let projectFile = directory.appendingPathComponent("project.json", isDirectory: false)
            guard fileManager.fileExists(atPath: projectFile.path) else {
                continue
            }
            let data = try Data(contentsOf: projectFile)
            let project = try decoder.decode(ConceptProject.self, from: data)
            let state = try loadProjectAssets(for: project, in: directory)
            updateLastOpenedProjectID(project.id)
            return ConceptProjectState(project: normalized(project: project, defaultModel: defaultModel), layerAssetData: state)
        }

        let project = ConceptProject.emptyDefault()
        let normalized = normalized(project: project, defaultModel: defaultModel)
        let state = ConceptProjectState(project: normalized, layerAssetData: [:])
        try save(state)
        updateLastOpenedProjectID(normalized.id)
        return state
    }

    func loadProject(id: UUID) throws -> ConceptProjectState? {
        let directory = try AppDirectories.conceptProjectDirectory(id: id, fileManager: fileManager)
        let projectFile = directory.appendingPathComponent("project.json", isDirectory: false)
        guard fileManager.fileExists(atPath: projectFile.path) else {
            return nil
        }

        let data = try Data(contentsOf: projectFile)
        let project = try decoder.decode(ConceptProject.self, from: data)
        let assets = try loadProjectAssets(for: project, in: directory)
        return ConceptProjectState(project: project, layerAssetData: assets)
    }

    func save(_ state: ConceptProjectState) throws {
        let directory = try AppDirectories.conceptProjectDirectory(id: state.project.id, fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let layersDirectory = directory.appendingPathComponent("layers", isDirectory: true)
        try fileManager.createDirectory(at: layersDirectory, withIntermediateDirectories: true)

        let normalizedProject = state.project.normalizedLayerOrdering()
        let data = try encoder.encode(normalizedProject)
        try FileIO.writeAtomically(data: data, to: directory.appendingPathComponent("project.json", isDirectory: false), fileManager: fileManager)

        let expectedFilenames = Set(normalizedProject.layers.compactMap(\.assetFilename))
        let existingFiles = (try? fileManager.contentsOfDirectory(at: layersDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for file in existingFiles where !expectedFilenames.contains(file.lastPathComponent) {
            try? fileManager.removeItem(at: file)
        }

        for layer in normalizedProject.layers {
            guard let assetFilename = layer.assetFilename else { continue }
            guard let assetData = state.layerAssetData[layer.id] else { continue }
            try FileIO.writeAtomically(
                data: assetData,
                to: layersDirectory.appendingPathComponent(assetFilename, isDirectory: false),
                fileManager: fileManager
            )
        }

        updateLastOpenedProjectID(normalizedProject.id)
    }

    func updateLastOpenedProjectID(_ id: UUID) {
        let url = projectsDirectory.appendingPathComponent("last-opened.txt", isDirectory: false)
        try? id.uuidString.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private func loadLastOpenedProjectID() -> UUID? {
        let url = projectsDirectory.appendingPathComponent("last-opened.txt", isDirectory: false)
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let id = UUID(uuidString: raw) else {
            return nil
        }
        return id
    }

    private func loadProjectAssets(for project: ConceptProject, in directory: URL) throws -> [UUID: Data] {
        let layersDirectory = directory.appendingPathComponent("layers", isDirectory: true)
        var assets: [UUID: Data] = [:]
        for layer in project.layers {
            guard let assetFilename = layer.assetFilename else { continue }
            let fileURL = layersDirectory.appendingPathComponent(assetFilename, isDirectory: false)
            guard fileManager.fileExists(atPath: fileURL.path) else { continue }
            assets[layer.id] = try Data(contentsOf: fileURL)
        }
        return assets
    }

    private func normalized(project: ConceptProject, defaultModel: String) -> ConceptProject {
        var project = project.normalizedLayerOrdering()
        let trimmedModel = project.model.trimmingCharacters(in: .whitespacesAndNewlines)
        project.model = trimmedModel.isEmpty ? defaultModel : trimmedModel
        project.imageCount = min(max(project.imageCount, 1), 4)
        return project
    }
}

private extension ConceptProject {
    func normalizedLayerOrdering() -> ConceptProject {
        var copy = self
        copy.layers = layers.enumerated().map { index, layer in
            var layerCopy = layer
            layerCopy.zIndex = layers.count - index - 1
            return layerCopy
        }
        copy.updatedAt = Date()
        return copy
    }
}
