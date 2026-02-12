import Foundation

struct AppConfig: Codable, Equatable {
    static let defaultModel = "gemini-3-pro-image-preview"
    static let defaultPromptEnhancementInstruction = "Улучши мой запрос для генерации изображения в Nano Banana Pro и пришли только исключительно улучшенный запрос без дополнительных слов"
    static let defaultRequestTimeoutSec = 120
    static let defaultNetworkPolicyVersion = 1

    var apiKey: String
    var model: String
    var promptEnhancementModel: String
    var promptEnhancementInstruction: String
    var language: AppLanguage
    var defaultOutputDir: String
    var requestTimeoutSec: Int

    var proxyType: ProxyType
    var proxyHost: String
    var proxyPort: Int
    var proxyUsername: String
    var proxyPassword: String
    var proxyEnabled: Bool
    var allowDirectFallback: Bool
    var noProxyHosts: [String]
    var networkPolicyVersion: Int

    var proxySettings: ProxySettings {
        ProxySettings(
            type: proxyType,
            host: proxyHost,
            port: proxyPort,
            username: proxyUsername,
            password: proxyPassword,
            enabled: proxyEnabled,
            allowDirectFallback: allowDirectFallback,
            noProxyHosts: noProxyHosts
        )
    }

    static func defaultValue(
        currentWorkingDirectory: URL? = AppConfig.inferWorkingDirectory(),
        fileManager: FileManager = .default
    ) -> AppConfig {
        let outputDirectory = defaultOutputDirectory(currentWorkingDirectory: currentWorkingDirectory, fileManager: fileManager)
        return AppConfig(
            apiKey: "",
            model: defaultModel,
            promptEnhancementModel: defaultModel,
            promptEnhancementInstruction: defaultPromptEnhancementInstruction,
            language: .systemDefault(),
            defaultOutputDir: outputDirectory.path,
            requestTimeoutSec: defaultRequestTimeoutSec,
            proxyType: .http,
            proxyHost: "",
            proxyPort: 8080,
            proxyUsername: "",
            proxyPassword: "",
            proxyEnabled: true,
            allowDirectFallback: false,
            noProxyHosts: [],
            networkPolicyVersion: defaultNetworkPolicyVersion
        )
    }

    static func defaultOutputDirectory(currentWorkingDirectory: URL?, fileManager: FileManager) -> URL {
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("NanoBanana_img", isDirectory: true)
    }

    static func inferWorkingDirectory(fileManager: FileManager = .default) -> URL? {
        if let envPWD = ProcessInfo.processInfo.environment["PWD"], !envPWD.isEmpty {
            let url = URL(fileURLWithPath: envPWD, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }

        let current = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        return current.path == "/" ? nil : current
    }

    enum CodingKeys: String, CodingKey {
        case apiKey
        case model
        case promptEnhancementModel
        case promptEnhancementInstruction
        case language
        case defaultOutputDir
        case requestTimeoutSec
        case proxyType
        case proxyHost
        case proxyPort
        case proxyUsername
        case proxyPassword
        case proxyEnabled
        case allowDirectFallback
        case noProxyHosts
        case networkPolicyVersion
    }

    init(
        apiKey: String,
        model: String,
        promptEnhancementModel: String,
        promptEnhancementInstruction: String,
        language: AppLanguage,
        defaultOutputDir: String,
        requestTimeoutSec: Int,
        proxyType: ProxyType,
        proxyHost: String,
        proxyPort: Int,
        proxyUsername: String,
        proxyPassword: String,
        proxyEnabled: Bool,
        allowDirectFallback: Bool,
        noProxyHosts: [String],
        networkPolicyVersion: Int
    ) {
        self.apiKey = apiKey
        self.model = model
        self.promptEnhancementModel = promptEnhancementModel
        self.promptEnhancementInstruction = promptEnhancementInstruction
        self.language = language
        self.defaultOutputDir = defaultOutputDir
        self.requestTimeoutSec = requestTimeoutSec
        self.proxyType = proxyType
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.proxyUsername = proxyUsername
        self.proxyPassword = proxyPassword
        self.proxyEnabled = proxyEnabled
        self.allowDirectFallback = allowDirectFallback
        self.noProxyHosts = noProxyHosts
        self.networkPolicyVersion = networkPolicyVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let defaults = AppConfig.defaultValue()

        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? defaults.apiKey
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        promptEnhancementModel = try container.decodeIfPresent(String.self, forKey: .promptEnhancementModel) ?? model
        promptEnhancementInstruction = try container.decodeIfPresent(String.self, forKey: .promptEnhancementInstruction) ?? defaults.promptEnhancementInstruction
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? defaults.language
        defaultOutputDir = try container.decodeIfPresent(String.self, forKey: .defaultOutputDir) ?? defaults.defaultOutputDir
        requestTimeoutSec = try container.decodeIfPresent(Int.self, forKey: .requestTimeoutSec) ?? defaults.requestTimeoutSec

        proxyType = try container.decodeIfPresent(ProxyType.self, forKey: .proxyType) ?? defaults.proxyType
        proxyHost = try container.decodeIfPresent(String.self, forKey: .proxyHost) ?? defaults.proxyHost
        proxyPort = try container.decodeIfPresent(Int.self, forKey: .proxyPort) ?? defaults.proxyPort
        proxyUsername = try container.decodeIfPresent(String.self, forKey: .proxyUsername) ?? defaults.proxyUsername
        proxyPassword = try container.decodeIfPresent(String.self, forKey: .proxyPassword) ?? defaults.proxyPassword
        proxyEnabled = try container.decodeIfPresent(Bool.self, forKey: .proxyEnabled) ?? defaults.proxyEnabled
        allowDirectFallback = try container.decodeIfPresent(Bool.self, forKey: .allowDirectFallback) ?? defaults.allowDirectFallback

        if let decodedNoProxyHosts = try container.decodeIfPresent([String].self, forKey: .noProxyHosts) {
            noProxyHosts = decodedNoProxyHosts
        } else if let decodedNoProxyHostsString = try container.decodeIfPresent(String.self, forKey: .noProxyHosts) {
            noProxyHosts = decodedNoProxyHostsString
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            noProxyHosts = defaults.noProxyHosts
        }

        networkPolicyVersion = try container.decodeIfPresent(Int.self, forKey: .networkPolicyVersion) ?? defaults.networkPolicyVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(model, forKey: .model)
        try container.encode(promptEnhancementModel, forKey: .promptEnhancementModel)
        try container.encode(promptEnhancementInstruction, forKey: .promptEnhancementInstruction)
        try container.encode(language, forKey: .language)
        try container.encode(defaultOutputDir, forKey: .defaultOutputDir)
        try container.encode(requestTimeoutSec, forKey: .requestTimeoutSec)

        try container.encode(proxyType, forKey: .proxyType)
        try container.encode(proxyHost, forKey: .proxyHost)
        try container.encode(proxyPort, forKey: .proxyPort)
        try container.encode(proxyUsername, forKey: .proxyUsername)
        try container.encode(proxyPassword, forKey: .proxyPassword)
        try container.encode(proxyEnabled, forKey: .proxyEnabled)
        try container.encode(allowDirectFallback, forKey: .allowDirectFallback)
        try container.encode(noProxyHosts, forKey: .noProxyHosts)
        try container.encode(networkPolicyVersion, forKey: .networkPolicyVersion)
    }
}
