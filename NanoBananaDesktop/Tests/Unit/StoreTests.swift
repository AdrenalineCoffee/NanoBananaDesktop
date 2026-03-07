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
    #expect(result.config.promptFromImageInstruction == AppConfig.defaultPromptFromImageInstruction)
    #expect(result.config.proxyEnabled == false)
    #expect(result.config.allowDirectFallback == false)
    #expect(result.config.networkPolicyVersion == AppConfig.defaultNetworkPolicyVersion)
    #expect(result.config.defaultOutputDir == expectedDefaultPath)
    #expect(result.config.requestTimeoutSec == AppConfig.defaultRequestTimeoutSec)
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
    #expect(result.config.promptFromImageInstruction == AppConfig.defaultPromptFromImageInstruction)
    #expect(result.config.proxyEnabled == false)
    #expect(result.config.proxyType == .http)
    #expect(result.config.proxyPort == 8080)
    #expect(result.config.requestTimeoutSec == AppConfig.defaultRequestTimeoutSec)
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
func configStoreMigratesMissingPromptFromImageInstructionToDefault() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let configURL = tempDir.appendingPathComponent("config.json")
    let oldSchemaJSON = """
    {
      "apiKey": "abc",
      "model": "nano-banana-pro-preview",
      "promptEnhancementModel": "gemini-3-flash-preview",
      "promptEnhancementInstruction": "Improve prompt",
      "language": "en",
      "defaultOutputDir": "/tmp",
      "requestTimeoutSec": 120
    }
    """
    try oldSchemaJSON.data(using: .utf8)?.write(to: configURL)

    let store = try AppConfigStore(configURL: configURL)
    let result = store.load(currentWorkingDirectory: tempDir)
    #expect(result.config.promptFromImageInstruction == AppConfig.defaultPromptFromImageInstruction)
    #expect(result.config.requestTimeoutSec == AppConfig.defaultRequestTimeoutSec)
}

@Test
func configStoreMigratesLegacyPromptFromImageInstructionToNewDefault() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let configURL = tempDir.appendingPathComponent("config.json")
    let legacyInstruction = AppConfig.legacyDefaultPromptFromImageInstruction
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")

    let legacyConfigJSON = """
    {
      "apiKey": "abc",
      "model": "nano-banana-pro-preview",
      "promptEnhancementModel": "gemini-3-flash-preview",
      "promptEnhancementInstruction": "Improve prompt",
      "promptFromImageInstruction": "\(legacyInstruction)",
      "language": "en",
      "defaultOutputDir": "/tmp",
      "requestTimeoutSec": 180
    }
    """
    try legacyConfigJSON.data(using: .utf8)?.write(to: configURL)

    let store = try AppConfigStore(configURL: configURL)
    let result = store.load(currentWorkingDirectory: tempDir)
    #expect(result.config.promptFromImageInstruction == AppConfig.defaultPromptFromImageInstruction)
}

@Test
func configStoreMigratesLegacyTimeout120To180() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let configURL = tempDir.appendingPathComponent("config.json")
    let oldSchemaJSON = """
    {
      "apiKey": "abc",
      "model": "nano-banana-pro-preview",
      "promptEnhancementModel": "gemini-3-flash-preview",
      "promptEnhancementInstruction": "Improve prompt",
      "promptFromImageInstruction": "Describe image",
      "language": "en",
      "defaultOutputDir": "/tmp",
      "requestTimeoutSec": 120
    }
    """
    try oldSchemaJSON.data(using: .utf8)?.write(to: configURL)

    let store = try AppConfigStore(configURL: configURL)
    let result = store.load(currentWorkingDirectory: tempDir)

    #expect(result.config.requestTimeoutSec == AppConfig.defaultRequestTimeoutSec)
}

@Test
func configStoreKeepsCustomTimeoutUnchanged() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let configURL = tempDir.appendingPathComponent("config.json")
    let customTimeoutJSON = """
    {
      "apiKey": "abc",
      "model": "nano-banana-pro-preview",
      "promptEnhancementModel": "gemini-3-flash-preview",
      "promptEnhancementInstruction": "Improve prompt",
      "promptFromImageInstruction": "Describe image",
      "language": "en",
      "defaultOutputDir": "/tmp",
      "requestTimeoutSec": 240
    }
    """
    try customTimeoutJSON.data(using: .utf8)?.write(to: configURL)

    let store = try AppConfigStore(configURL: configURL)
    let result = store.load(currentWorkingDirectory: tempDir)

    #expect(result.config.requestTimeoutSec == 240)
}

@Test
func configStoreDisablesProxyWhenLegacyConfigHasEmptyHost() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let configURL = tempDir.appendingPathComponent("config.json")
    let legacyConfigJSON = """
    {
      "apiKey": "abc",
      "model": "nano-banana-pro-preview",
      "promptEnhancementModel": "gemini-3-flash-preview",
      "promptEnhancementInstruction": "Improve prompt",
      "promptFromImageInstruction": "Describe image",
      "language": "en",
      "defaultOutputDir": "/tmp",
      "requestTimeoutSec": 180,
      "proxyEnabled": true,
      "proxyHost": ""
    }
    """
    try legacyConfigJSON.data(using: .utf8)?.write(to: configURL)

    let store = try AppConfigStore(configURL: configURL)
    let result = store.load(currentWorkingDirectory: tempDir)

    #expect(result.config.proxyEnabled == false)
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
    config.promptFromImageInstruction = "Describe this image as a generation prompt"
    try store.save(config)

    let reloaded = store.load(currentWorkingDirectory: tempDir).config
    #expect(reloaded.model == "custom-image-model")
    #expect(reloaded.promptEnhancementModel == "custom-text-model")
    #expect(reloaded.promptEnhancementInstruction == "Refine this prompt")
    #expect(reloaded.promptFromImageInstruction == "Describe this image as a generation prompt")
}

@Test
func configStoreLoadsPresetListFromConfig() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let configURL = tempDir.appendingPathComponent("config.json")
    let store = try AppConfigStore(configURL: configURL)
    var config = store.load(currentWorkingDirectory: tempDir).config
    config.promptPresets = [
        PromptPreset(
            name: "Product Hero",
            prompt: "A hero product shot",
            imageModel: "nano-banana-pro-preview",
            resolutionSelection: .k4,
            aspectRatioSelection: .landscape16x9,
            imageCount: 2
        )
    ]
    try store.save(config)

    let reloaded = store.load(currentWorkingDirectory: tempDir).config
    #expect(reloaded.promptPresets.count == 1)
    #expect(reloaded.promptPresets.first?.name == "Product Hero")
    #expect(reloaded.promptPresets.first?.resolutionSelection == .k4)
    #expect(reloaded.promptPresets.first?.aspectRatioSelection == .landscape16x9)
    #expect(reloaded.promptPresets.first?.imageCount == 2)
}

@Test
func configStoreNormalizesPresetDuplicatesAndInvalidPresetRows() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let configURL = tempDir.appendingPathComponent("config.json")
    let rawJSON = """
    {
      "apiKey": "abc",
      "model": "nano-banana-pro-preview",
      "promptEnhancementModel": "gemini-3-flash-preview",
      "promptEnhancementInstruction": "Improve prompt",
      "promptFromImageInstruction": "Describe image",
      "language": "en",
      "defaultOutputDir": "/tmp",
      "requestTimeoutSec": 180,
      "promptPresets": [
        {
          "id": "2a6d6f40-4d4a-4f7f-90a9-4a7cc2d54891",
          "name": "Hero",
          "prompt": "First value",
          "imageModel": "models/nano-banana-pro-preview",
          "resolutionSelection": "k1",
          "aspectRatioSelection": "auto",
          "imageCount": 1,
          "updatedAt": "2026-03-01T10:00:00Z"
        },
        {
          "id": "3e332661-c1e9-4f71-8e8b-5e7e479f2612",
          "name": "hero",
          "prompt": "Second value",
          "imageModel": "nano-banana-pro-preview",
          "resolutionSelection": "k2",
          "aspectRatioSelection": "landscape16x9",
          "imageCount": 3,
          "updatedAt": "2026-03-02T10:00:00Z"
        },
        {
          "id": "a588261f-4894-4cd2-b59c-56fed0f501f5",
          "name": "",
          "prompt": "Should be ignored",
          "imageModel": "nano-banana-pro-preview",
          "resolutionSelection": "k1",
          "aspectRatioSelection": "auto",
          "imageCount": 1,
          "updatedAt": "2026-03-02T10:00:00Z"
        },
        {
          "id": "0db5d89e-63eb-4bb9-a0e4-9416140a9388",
          "name": "Broken",
          "prompt": "",
          "imageModel": "nano-banana-pro-preview",
          "resolutionSelection": "k1",
          "aspectRatioSelection": "auto",
          "imageCount": 1,
          "updatedAt": "2026-03-02T10:00:00Z"
        }
      ]
    }
    """
    try rawJSON.data(using: .utf8)?.write(to: configURL)

    let store = try AppConfigStore(configURL: configURL)
    let result = store.load(currentWorkingDirectory: tempDir)

    #expect(result.config.promptPresets.count == 1)
    #expect(result.config.promptPresets.first?.name == "hero")
    #expect(result.config.promptPresets.first?.prompt == "Second value")
    #expect(result.config.promptPresets.first?.resolutionSelection == .k2)
}
