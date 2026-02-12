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
        let trimmedImageModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPromptModel = config.promptEnhancementModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnhancementInstruction = config.promptEnhancementInstruction.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedImageModel = normalizedModelName(from: trimmedImageModel, fallback: AppConfig.defaultModel)
        let normalizedPromptModel = normalizedModelName(
            from: trimmedPromptModel.isEmpty ? normalizedImageModel : trimmedPromptModel,
            fallback: normalizedImageModel
        )

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

        let timeout = (10...600).contains(config.requestTimeoutSec) ? config.requestTimeoutSec : AppConfig.defaultRequestTimeoutSec
        let normalizedProxyPort = (1...65535).contains(config.proxyPort) ? config.proxyPort : defaults.proxyPort

        let normalizedNoProxyHosts = config.noProxyHosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return AppConfig(
            apiKey: trimmedKey,
            model: normalizedImageModel,
            promptEnhancementModel: normalizedPromptModel,
            promptEnhancementInstruction: trimmedEnhancementInstruction.isEmpty
                ? AppConfig.defaultPromptEnhancementInstruction
                : trimmedEnhancementInstruction,
            language: config.language,
            defaultOutputDir: outputDirectory,
            requestTimeoutSec: timeout,
            proxyType: config.proxyType,
            proxyHost: config.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines),
            proxyPort: normalizedProxyPort,
            proxyUsername: config.proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            proxyPassword: config.proxyPassword,
            proxyEnabled: config.proxyEnabled,
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

        if trimmed.lowercased().hasPrefix("models/") {
            let stripped = String(trimmed.dropFirst("models/".count))
            return stripped.isEmpty ? fallback : stripped
        }

        return trimmed
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
