import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func configStoreCreatesDefaultsWhenFileMissing() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let configURL = tempDir.appendingPathComponent("config.json")
    let store = try AppConfigStore(configURL: configURL)
    let result = store.load(currentWorkingDirectory: tempDir)

    let expectedDefaultPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures", isDirectory: true)
        .appendingPathComponent("NanoBanana_img", isDirectory: true)
        .path

    #expect(result.config.model == AppConfig.defaultModel)
    #expect(result.config.promptEnhancementModel == AppConfig.defaultPromptEnhancementModel)
    #expect(result.config.promptEnhancementInstruction == AppConfig.defaultPromptEnhancementInstruction)
    #expect(result.config.proxyEnabled == true)
    #expect(result.config.allowDirectFallback == false)
    #expect(result.config.networkPolicyVersion == AppConfig.defaultNetworkPolicyVersion)
    #expect(result.config.defaultOutputDir == expectedDefaultPath)
    #expect(result.recoveredFromCorruption == false)
    #expect(FileManager.default.fileExists(atPath: configURL.path))
}

@Test
func configStoreMigratesLegacyPicturesDirectoryToNanoBananaImg() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let legacyPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures", isDirectory: true)
        .appendingPathComponent("NanoBanana", isDirectory: true)
        .path
    let configURL = tempDir.appendingPathComponent("config.json")
    let oldSchemaJSON = """
    {
      "apiKey": "abc",
      "model": "gemini-3-pro-image-preview",
      "language": "en",
      "defaultOutputDir": "\(legacyPath)",
      "requestTimeoutSec": 120
    }
    """
    try oldSchemaJSON.data(using: .utf8)?.write(to: configURL)

    let store = try AppConfigStore(configURL: configURL)
    let result = store.load(currentWorkingDirectory: tempDir)

    let expectedPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures", isDirectory: true)
        .appendingPathComponent("NanoBanana_img", isDirectory: true)
        .path

    #expect(result.recoveredFromCorruption == false)
    #expect(result.config.defaultOutputDir == expectedPath)
    #expect(result.config.promptEnhancementModel == AppConfig.defaultPromptEnhancementModel)
    #expect(result.config.promptEnhancementInstruction == AppConfig.defaultPromptEnhancementInstruction)
    #expect(result.config.proxyEnabled == true)
    #expect(result.config.proxyType == .http)
    #expect(result.config.proxyPort == 8080)
}

@Test
func configStoreRecoversFromCorruptedJSON() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let configURL = tempDir.appendingPathComponent("config.json")
    try "{bad-json".data(using: .utf8)?.write(to: configURL)

    let store = try AppConfigStore(configURL: configURL)
    let result = store.load(currentWorkingDirectory: tempDir)

    #expect(result.recoveredFromCorruption == true)
    #expect(result.config.model == AppConfig.defaultModel)
}

@Test
func historyStoreKeepsOnlyLatestTwentyItems() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let historyURL = tempDir.appendingPathComponent("history.json")
    let store = try HistoryStore(historyURL: historyURL, maxRecords: 20)

    for index in 0..<25 {
        let record = HistoryRecord(
            timestamp: Date().addingTimeInterval(TimeInterval(index)),
            mode: .generate,
            prompt: "prompt-\(index)",
            resolution: .k1,
            inputImagePaths: [],
            outputImagePath: "/tmp/\(index).png",
            status: .success,
            errorMessage: nil,
            durationMs: 100,
            networkRoute: .proxy,
            proxyUsed: true,
            fallbackUsed: false,
            proxySummary: "http://proxy.local:8080"
        )
        try store.append(record)
    }

    let loaded = store.load()
    #expect(loaded.count == 20)
}

@Test
func configStorePersistsCustomModelName() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let configURL = tempDir.appendingPathComponent("config.json")
    let store = try AppConfigStore(configURL: configURL)
    var config = store.load(currentWorkingDirectory: tempDir).config
    config.model = "custom-image-model"
    config.promptEnhancementModel = "custom-text-model"
    config.promptEnhancementInstruction = "Refine this prompt"
    try store.save(config)

    let reloaded = store.load(currentWorkingDirectory: tempDir).config
    #expect(reloaded.model == "custom-image-model")
    #expect(reloaded.promptEnhancementModel == "custom-text-model")
    #expect(reloaded.promptEnhancementInstruction == "Refine this prompt")
}
