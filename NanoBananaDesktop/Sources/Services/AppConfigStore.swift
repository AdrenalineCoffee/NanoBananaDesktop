import Foundation

struct AppConfigLoadResult {
    let config: AppConfig
    let recoveredFromCorruption: Bool
}

final class AppConfigStore {
    private let configURL: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(configURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.configURL = try configURL ?? AppDirectories.configFileURL(fileManager: fileManager)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load(currentWorkingDirectory: URL? = AppConfig.inferWorkingDirectory()) -> AppConfigLoadResult {
        guard fileManager.fileExists(atPath: configURL.path) else {
            let defaults = AppConfig.defaultValue(currentWorkingDirectory: currentWorkingDirectory, fileManager: fileManager)
            try? save(defaults)
            return AppConfigLoadResult(config: defaults, recoveredFromCorruption: false)
        }

        do {
            let data = try Data(contentsOf: configURL)
            let decoded = try decoder.decode(AppConfig.self, from: data)
            let normalized = normalizedConfig(decoded, currentWorkingDirectory: currentWorkingDirectory)
            if normalized != decoded {
                try? save(normalized)
            }
            return AppConfigLoadResult(config: normalized, recoveredFromCorruption: false)
        } catch {
            backupCorruptedConfigIfNeeded()
            let defaults = AppConfig.defaultValue(currentWorkingDirectory: currentWorkingDirectory, fileManager: fileManager)
            try? save(defaults)
            return AppConfigLoadResult(config: defaults, recoveredFromCorruption: true)
        }
    }

    func save(_ config: AppConfig) throws {
        let normalized = normalizedConfig(config, currentWorkingDirectory: AppConfig.inferWorkingDirectory(fileManager: fileManager))
        do {
            let data = try encoder.encode(normalized)
            try FileIO.writeAtomically(data: data, to: configURL, fileManager: fileManager)
        } catch {
            throw AppError.ioError(error.localizedDescription)
        }
    }

    private func normalizedConfig(_ config: AppConfig, currentWorkingDirectory: URL?) -> AppConfig {
        let defaults = AppConfig.defaultValue(currentWorkingDirectory: currentWorkingDirectory, fileManager: fileManager)

        let trimmedKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIKey = config.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAICompatibleKey = config.openAICompatibleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKieKey = config.kieAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOpenAICompatibleBaseURL = normalizedBaseURLString(
            config.openAICompatibleBaseURL,
            fallback: AppConfig.defaultOpenAICompatibleBaseURL
        )
        let trimmedImageModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPromptModel = config.promptEnhancementModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPromptFromImageInstruction = config.promptFromImageInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConceptPromptAdditions = config.conceptPromptAdditions.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnhancementInstruction = config.promptEnhancementInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPromptPresets = normalizedPromptPresets(config.promptPresets)

        var normalizedImageModel = normalizedModelName(from: trimmedImageModel, fallback: AppConfig.defaultModel)
        if normalizedImageModel == AppConfig.legacyDefaultImageModel {
            normalizedImageModel = AppConfig.defaultModel
        }

        var normalizedPromptModel = normalizedModelName(
            from: trimmedPromptModel,
            fallback: AppConfig.defaultPromptEnhancementModel
        )
        if normalizedPromptModel == AppConfig.legacyDefaultImageModel {
            normalizedPromptModel = AppConfig.defaultPromptEnhancementModel
        }

        let normalizedEnhancementInstruction: String
        if trimmedEnhancementInstruction.isEmpty
            || trimmedEnhancementInstruction == AppConfig.legacyDefaultPromptEnhancementInstruction {
            normalizedEnhancementInstruction = AppConfig.defaultPromptEnhancementInstruction
        } else {
            normalizedEnhancementInstruction = trimmedEnhancementInstruction
        }

        let normalizedPromptFromImageInstruction: String
        if trimmedPromptFromImageInstruction.isEmpty
            || trimmedPromptFromImageInstruction == AppConfig.legacyDefaultPromptFromImageInstruction {
            normalizedPromptFromImageInstruction = AppConfig.defaultPromptFromImageInstruction
        } else {
            normalizedPromptFromImageInstruction = trimmedPromptFromImageInstruction
        }

        let normalizedConceptPromptAdditions: String
        if trimmedConceptPromptAdditions.isEmpty
            || trimmedConceptPromptAdditions == AppConfig.legacyDefaultConceptPromptAdditions {
            normalizedConceptPromptAdditions = AppConfig.defaultConceptPromptAdditions
        } else {
            normalizedConceptPromptAdditions = trimmedConceptPromptAdditions
        }

        let migratedDefaultPath = AppConfig.defaultOutputDirectory(
            currentWorkingDirectory: currentWorkingDirectory,
            fileManager: fileManager
        ).path
        let legacyDefaultPath = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("NanoBanana", isDirectory: true)
            .path
        let candidateOutput = config.defaultOutputDir.trimmingCharacters(in: .whitespacesAndNewlines)

        let outputDirectory: String
        if candidateOutput.isEmpty || !candidateOutput.hasPrefix("/") {
            outputDirectory = migratedDefaultPath
        } else if candidateOutput == legacyDefaultPath {
            outputDirectory = migratedDefaultPath
        } else {
            outputDirectory = candidateOutput
        }

        let timeout: Int
        if config.requestTimeoutSec == AppConfig.legacyDefaultRequestTimeoutSec {
            timeout = AppConfig.defaultRequestTimeoutSec
        } else if (10...600).contains(config.requestTimeoutSec) {
            timeout = config.requestTimeoutSec
        } else {
            timeout = AppConfig.defaultRequestTimeoutSec
        }

        let normalizedProxyHost = config.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProxyEnabled = config.proxyEnabled && !normalizedProxyHost.isEmpty
        let normalizedProxyPort = (1...65535).contains(config.proxyPort) ? config.proxyPort : defaults.proxyPort

        let normalizedNoProxyHosts = config.noProxyHosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return AppConfig(
            apiKey: trimmedKey,
            openAIAPIKey: trimmedOpenAIKey,
            openAICompatibleAPIKey: trimmedOpenAICompatibleKey,
            openAICompatibleBaseURL: normalizedOpenAICompatibleBaseURL,
            kieAPIKey: trimmedKieKey,
            geminiEnabled: config.geminiEnabled,
            openAIEnabled: config.openAIEnabled,
            openAICompatibleEnabled: config.openAICompatibleEnabled,
            kieEnabled: config.kieEnabled,
            model: normalizedImageModel,
            promptEnhancementModel: normalizedPromptModel,
            promptFromImageInstruction: normalizedPromptFromImageInstruction,
            conceptPromptAdditions: normalizedConceptPromptAdditions,
            generationCompletionNotificationsEnabled: config.generationCompletionNotificationsEnabled,
            promptEnhancementInstruction: normalizedEnhancementInstruction,
            promptPresets: normalizedPromptPresets,
            language: config.language,
            defaultOutputDir: outputDirectory,
            requestTimeoutSec: timeout,
            proxyType: config.proxyType,
            proxyHost: normalizedProxyHost,
            proxyPort: normalizedProxyPort,
            proxyUsername: config.proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            proxyPassword: config.proxyPassword,
            proxyEnabled: normalizedProxyEnabled,
            allowDirectFallback: config.allowDirectFallback,
            noProxyHosts: normalizedNoProxyHosts,
            networkPolicyVersion: max(config.networkPolicyVersion, AppConfig.defaultNetworkPolicyVersion)
        )
    }

    private func normalizedModelName(from candidate: String, fallback: String) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallback
        }

        let provider = ModelProvider.inferImageProvider(from: trimmed)
        let apiModelName = ModelProvider.apiModelName(from: trimmed)
        if apiModelName.lowercased().hasPrefix("models/") {
            let stripped = String(apiModelName.dropFirst("models/".count))
            return stripped.isEmpty
                ? fallback
                : ModelProvider.encodedModelName(provider: provider, modelName: stripped)
        }

        return trimmed
    }

    private func normalizedBaseURLString(_ candidate: String, fallback: String) -> String {
        var trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = fallback
        }

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        return trimmed.isEmpty ? fallback : trimmed
    }

    private func normalizedPromptPresets(_ presets: [PromptPreset]) -> [PromptPreset] {
        var dedupByName: [String: PromptPreset] = [:]

        for preset in presets {
            let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let prompt = preset.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !prompt.isEmpty else {
                continue
            }

            let normalizedModel = normalizedModelName(from: preset.imageModel, fallback: AppConfig.defaultModel)
            let normalizedPreset = PromptPreset(
                id: preset.id,
                name: name,
                prompt: prompt,
                imageModel: normalizedModel,
                resolutionSelection: preset.resolutionSelection,
                aspectRatioSelection: preset.aspectRatioSelection,
                imageCount: preset.imageCount,
                updatedAt: preset.updatedAt
            )

            let key = name.lowercased()
            if let existing = dedupByName[key] {
                if normalizedPreset.updatedAt >= existing.updatedAt {
                    dedupByName[key] = normalizedPreset
                }
            } else {
                dedupByName[key] = normalizedPreset
            }
        }

        return dedupByName.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func backupCorruptedConfigIfNeeded() {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupURL = configURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(timestamp).json")

        try? fileManager.moveItem(at: configURL, to: backupURL)
    }
}
