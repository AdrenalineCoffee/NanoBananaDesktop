import AppKit
import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func generateFlowSuccessSavesImageThroughProxyRoute() async throws {
    let apiKey = "key-smoke-proxy"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let client = GeminiAPIClient()
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])

    setSingleGenerationHandler(forAPIKey: apiKey, imageBase64: tinyPNGBase64)

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            apiClient: client,
            networkClientProvider: networkProvider
        )
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.defaultOutputDir = tempDirectory.path
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.prompt = "A robot in city"
        viewModel.generate()
    }

    try await waitForGenerationToComplete(viewModel: viewModel)

    let outputPath = await MainActor.run { viewModel.lastOutputPath }
    #expect(outputPath != nil)
    #expect(FileManager.default.fileExists(atPath: outputPath ?? ""))

    let historyItems = await MainActor.run { viewModel.history }
    #expect(historyItems.count == 1)
    #expect(historyItems.first?.networkRoute == .proxy)
    #expect(historyItems.first?.mode == .generate)

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateFlowSucceedsWithoutProxyWhenProxyIsDisabled() async throws {
    let apiKey = "key-smoke-direct"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let client = GeminiAPIClient()
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])

    setSingleGenerationHandler(forAPIKey: apiKey, imageBase64: tinyPNGBase64)

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            apiClient: client,
            networkClientProvider: networkProvider
        )
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.defaultOutputDir = tempDirectory.path
        viewModel.config.proxyEnabled = false
        viewModel.config.allowDirectFallback = false
        viewModel.prompt = "A robot in city"
        viewModel.generate()
    }

    try await waitForGenerationToComplete(viewModel: viewModel)

    let outputPath = await MainActor.run { viewModel.lastOutputPath }
    #expect(outputPath != nil)
    #expect(FileManager.default.fileExists(atPath: outputPath ?? ""))

    let historyItems = await MainActor.run { viewModel.history }
    #expect(historyItems.count == 1)
    #expect(historyItems.first?.networkRoute == .directFallback)
    #expect(historyItems.first?.proxyUsed == false)

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateFlowUsesOpenAIImageEndpointWhenOpenAIModelIsSelected() async throws {
    let openAIAPIKey = "sk-openai-smoke"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])

    setOpenAIImageGenerationHandler(forAPIKey: openAIAPIKey, imageBase64: tinyPNGBase64)

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            networkClientProvider: networkProvider
        )
    }

    await MainActor.run {
        viewModel.config.openAIAPIKey = openAIAPIKey
        viewModel.config.model = "gpt-image-2"
        viewModel.config.defaultOutputDir = tempDirectory.path
        viewModel.prompt = "A robot in city"
        viewModel.generate()
    }

    try await waitForGenerationToComplete(viewModel: viewModel)

    let outputPath = await MainActor.run { viewModel.lastOutputPath }
    #expect(outputPath != nil)
    #expect(FileManager.default.fileExists(atPath: outputPath ?? ""))

    MockURLProtocol.removeHandler(forAPIKey: openAIAPIKey)
}

@Test
func generateFlowWithMultipleAttachmentsUsesEditMode() async throws {
    let apiKey = "key-multi-attachments"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let input1 = tempDirectory.appendingPathComponent("a.png")
    let input2 = tempDirectory.appendingPathComponent("b.jpg")
    try Data("first".utf8).write(to: input1)
    try Data("second".utf8).write(to: input2)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let client = GeminiAPIClient()
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])

    setSingleGenerationHandler(forAPIKey: apiKey, imageBase64: tinyPNGBase64)

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            apiClient: client,
            networkClientProvider: networkProvider
        )
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.defaultOutputDir = tempDirectory.path
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.prompt = "transfer expression"
        viewModel.attachedImages = [
            AttachedImage(fileURL: input1, displayName: "a.png", mentionToken: "@a", thumbnail: nil),
            AttachedImage(fileURL: input2, displayName: "b.jpg", mentionToken: "@b", thumbnail: nil)
        ]
        viewModel.requestMentionInsert(for: viewModel.attachedImages[0])
        viewModel.generate()
    }

    try await waitForGenerationToComplete(viewModel: viewModel)

    let pendingMention = await MainActor.run { viewModel.pendingMentionInsert }
    #expect(pendingMention == "@a")

    let historyItems = await MainActor.run { viewModel.history }
    #expect(historyItems.count == 1)
    #expect(historyItems.first?.mode == .edit)
    #expect(historyItems.first?.inputImagePaths.count == 2)

    let generatedImage = await MainActor.run { viewModel.lastGeneratedImage }
    #expect(generatedImage != nil)

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateFlowWithImageCountThreeCreatesThreeOutputsAndHistoryEntries() async throws {
    let apiKey = "key-image-count-three"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let client = GeminiAPIClient()
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])

    setMultiSingleGenerationHandler(
        forAPIKey: apiKey,
        expectedRequestCount: 3,
        imageBase64s: [tinyPNGBase64, tinyPNGBase64Alt, tinyPNGBase64SecondAlt]
    )

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            apiClient: client,
            networkClientProvider: networkProvider
        )
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.defaultOutputDir = tempDirectory.path
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.prompt = "A robot in city"
        viewModel.imageCountSelection = 3
        viewModel.generate()
    }

    try await waitForGenerationToComplete(viewModel: viewModel)

    let outputPaths = await MainActor.run { viewModel.lastOutputPaths }
    #expect(outputPaths.count == 3)
    #expect(outputPaths.allSatisfy { FileManager.default.fileExists(atPath: $0) })

    let previewImages = await MainActor.run { viewModel.lastGeneratedImages }
    #expect(previewImages.count == 3)

    let historyItems = await MainActor.run { viewModel.history }
    #expect(historyItems.count == 3)
    #expect(historyItems.allSatisfy { $0.status == .success })

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateFlowKeepsPreviousPreviewUntilNewImageArrives() async throws {
    let apiKey = "key-keep-preview"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let oldOutput = tempDirectory.appendingPathComponent("old.png")
    try tinyPNGData.write(to: oldOutput)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        Thread.sleep(forTimeInterval: 0.25)
        let url = try #require(request.url)
        #expect(url.path.contains(":generateContent") == true)
        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [
                        ["text": "single-image"],
                        ["inlineData": ["mimeType": "image/png", "data": tinyPNGBase64Alt]]
                    ]
                ]
            ]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            networkClientProvider: networkProvider
        )
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.defaultOutputDir = tempDirectory.path
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        if let image = NSImage(data: tinyPNGData) {
            viewModel.lastGeneratedImages = [image]
            viewModel.lastGeneratedImage = image
        }
        viewModel.lastOutputPaths = [oldOutput.path]
        viewModel.lastOutputPath = oldOutput.path
        viewModel.prompt = "new prompt"
        viewModel.generate()
    }

    let previewDuringGeneration = await MainActor.run { viewModel.lastGeneratedImages.count }
    let outputDuringGeneration = await MainActor.run { viewModel.lastOutputPath }
    #expect(previewDuringGeneration == 1)
    #expect(outputDuringGeneration == oldOutput.path)

    try await waitForGenerationToComplete(viewModel: viewModel)

    let outputAfterCompletion = await MainActor.run { viewModel.lastOutputPath }
    #expect(outputAfterCompletion != nil)
    #expect(outputAfterCompletion != oldOutput.path)

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateFlowFailsWhenProxyInvalidAndFallbackOff() async throws {
    let client = GeminiAPIClient()
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])

    let viewModel = try await makeIsolatedViewModel(
        apiClient: client,
        networkClientProvider: networkProvider
    )

    await MainActor.run {
        viewModel.config.apiKey = "key-any"
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = ""
        viewModel.config.allowDirectFallback = false
        viewModel.prompt = "A robot"
        viewModel.generate()
    }

    let errorMessage = await MainActor.run { viewModel.errorMessage }
    #expect(errorMessage != nil)
}

@Test
func handleDroppedImageURLsAddsAttachmentsAndKeepsMentionFlow() async throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let input1 = tempDirectory.appendingPathComponent("source-one.png")
    let input2 = tempDirectory.appendingPathComponent("source-two.jpg")
    try tinyPNGData.write(to: input1)
    try tinyPNGData.write(to: input2)

    let viewModel = try await makeIsolatedViewModel()

    await MainActor.run {
        viewModel.handleDroppedImageURLs([input1, input2])
    }

    let attachments = await MainActor.run { viewModel.attachedImages }
    #expect(attachments.count == 2)
    #expect(attachments.allSatisfy { !$0.mentionToken.isEmpty })

    await MainActor.run {
        if let firstAttachment = viewModel.attachedImages.first {
            viewModel.requestMentionInsert(for: firstAttachment)
        }
    }

    let pendingMention = await MainActor.run { viewModel.pendingMentionInsert }
    #expect(pendingMention != nil)
}

@Test
func reuseFromHistoryRestoresPromptAndAttachmentsWhenAllFilesExist() async throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let sourceA = tempDirectory.appendingPathComponent("source-a.png")
    let sourceB = tempDirectory.appendingPathComponent("source-b.jpg")
    try tinyPNGData.write(to: sourceA)
    try tinyPNGData.write(to: sourceB)

    let historyRecord = HistoryRecord(
        mode: .edit,
        prompt: "reuse this prompt",
        resolution: .k1,
        inputImagePaths: [sourceA.path, sourceB.path],
        outputImagePath: nil,
        status: .success,
        errorMessage: nil,
        durationMs: 120,
        networkRoute: .proxy,
        proxyUsed: true,
        fallbackUsed: false
    )

    let viewModel = try await makeIsolatedViewModel()

    let outcome = await MainActor.run {
        viewModel.prompt = "old prompt"
        viewModel.attachedImages = [
            AttachedImage(fileURL: sourceA, displayName: "old.png", mentionToken: "@old", thumbnail: nil)
        ]
        return viewModel.reuseFromHistory(historyRecord)
    }

    switch outcome {
    case .restoredAttachments(let count):
        #expect(count == 2)
    default:
        Issue.record("Expected restored attachments outcome")
    }

    let prompt = await MainActor.run { viewModel.prompt }
    #expect(prompt == "reuse this prompt")

    let attachments = await MainActor.run { viewModel.attachedImages }
    #expect(attachments.count == 2)
    #expect(attachments.map(\.fileURL.path) == [sourceA.path, sourceB.path])

    let successMessage = await MainActor.run { viewModel.successMessage }
    let errorMessage = await MainActor.run { viewModel.errorMessage }
    #expect(successMessage != nil)
    #expect(errorMessage == nil)
}

@Test
func reuseFromHistoryFallsBackToPromptOnlyWhenAnyFileMissing() async throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let existingFile = tempDirectory.appendingPathComponent("source-a.png")
    let missingFile = tempDirectory.appendingPathComponent("missing.png")
    try tinyPNGData.write(to: existingFile)

    let historyRecord = HistoryRecord(
        mode: .edit,
        prompt: "restore prompt only",
        resolution: .k1,
        inputImagePaths: [existingFile.path, missingFile.path],
        outputImagePath: nil,
        status: .success,
        errorMessage: nil,
        durationMs: 100,
        networkRoute: .proxy,
        proxyUsed: true,
        fallbackUsed: false
    )

    let viewModel = try await makeIsolatedViewModel()

    let outcome = await MainActor.run {
        viewModel.reuseFromHistory(historyRecord)
    }

    switch outcome {
    case .promptOnlyMissingFiles(let missingPaths):
        #expect(missingPaths.contains(missingFile.path))
    default:
        Issue.record("Expected prompt-only missing-files outcome")
    }

    let prompt = await MainActor.run { viewModel.prompt }
    let attachments = await MainActor.run { viewModel.attachedImages }
    let errorMessage = await MainActor.run { viewModel.errorMessage }
    let successMessage = await MainActor.run { viewModel.successMessage }

    #expect(prompt == "restore prompt only")
    #expect(attachments.isEmpty)
    #expect(errorMessage != nil)
    #expect(successMessage == nil)
}

@Test
func reuseFromHistoryReplacesExistingDraftNotAppend() async throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let existingAttachment = tempDirectory.appendingPathComponent("existing.png")
    try tinyPNGData.write(to: existingAttachment)

    let historyRecord = HistoryRecord(
        mode: .generate,
        prompt: "new prompt from history",
        resolution: .k1,
        inputImagePaths: [],
        outputImagePath: nil,
        status: .success,
        errorMessage: nil,
        durationMs: 80,
        networkRoute: .proxy,
        proxyUsed: true,
        fallbackUsed: false
    )

    let viewModel = try await makeIsolatedViewModel()

    let outcome = await MainActor.run {
        viewModel.prompt = "draft text"
        viewModel.attachedImages = [
            AttachedImage(
                fileURL: existingAttachment,
                displayName: "existing.png",
                mentionToken: "@existing",
                thumbnail: nil
            )
        ]
        return viewModel.reuseFromHistory(historyRecord)
    }

    #expect(outcome == .promptOnlyNoAttachments)

    let prompt = await MainActor.run { viewModel.prompt }
    let attachments = await MainActor.run { viewModel.attachedImages }
    #expect(prompt == "new prompt from history")
    #expect(attachments.isEmpty)
}

@Test
func reuseFromHistoryKeepsMentionTokensUniqueForDuplicateFilenames() async throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let firstDirectory = tempDirectory.appendingPathComponent("a", isDirectory: true)
    let secondDirectory = tempDirectory.appendingPathComponent("b", isDirectory: true)
    try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)

    let firstFile = firstDirectory.appendingPathComponent("ref.png")
    let secondFile = secondDirectory.appendingPathComponent("ref.png")
    try tinyPNGData.write(to: firstFile)
    try tinyPNGData.write(to: secondFile)

    let historyRecord = HistoryRecord(
        mode: .edit,
        prompt: "duplicate names",
        resolution: .k1,
        inputImagePaths: [firstFile.path, secondFile.path],
        outputImagePath: nil,
        status: .success,
        errorMessage: nil,
        durationMs: 100,
        networkRoute: .proxy,
        proxyUsed: true,
        fallbackUsed: false
    )

    let viewModel = try await makeIsolatedViewModel()

    let outcome = await MainActor.run {
        viewModel.reuseFromHistory(historyRecord)
    }

    switch outcome {
    case .restoredAttachments(let count):
        #expect(count == 2)
    default:
        Issue.record("Expected restored attachments outcome")
    }

    let mentionTokens = await MainActor.run { viewModel.attachedImages.map(\.mentionToken) }
    #expect(mentionTokens == ["@ref", "@ref_2"])
}

@Test
func generateFlowAllowsDirectFallbackWhenEnabled() async throws {
    let apiKey = "key-direct-fallback"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let client = GeminiAPIClient()

    let failingProxyThenDirectProvider = ProxyFirstThenDirectProvider(protocolClasses: [MockURLProtocol.self])

    setSingleGenerationHandler(forAPIKey: apiKey, imageBase64: tinyPNGBase64)

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            apiClient: client,
            networkClientProvider: failingProxyThenDirectProvider
        )
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.defaultOutputDir = tempDirectory.path
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.config.allowDirectFallback = true
        viewModel.prompt = "A robot in city"
        viewModel.generate()
    }

    try await waitForGenerationToComplete(viewModel: viewModel)

    let historyItems = await MainActor.run { viewModel.history }
    #expect(historyItems.first?.networkRoute == .directFallback)
    #expect(historyItems.first?.fallbackUsed == true)

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func modelCatalogManualRefreshLoadsImageReadyModels() async throws {
    let apiKey = "key-model-catalog-refresh"
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])
    let viewModel = try await makeIsolatedViewModel(networkClientProvider: networkProvider)

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        if request.url?.path.contains("/v1beta/models") == true {
            let json: [String: Any] = [
                "models": [
                    [
                        "name": "models/gemini-3-pro-image-preview",
                        "displayName": "Nano Banana Pro",
                        "description": "Gemini 3 Pro Image Preview",
                        "supportedGenerationMethods": ["generateContent", "countTokens"]
                    ],
                    [
                        "name": "models/gemini-2.5-flash",
                        "displayName": "Gemini Flash",
                        "description": "General model",
                        "supportedGenerationMethods": ["generateContent"]
                    ],
                    [
                        "name": "models/imagen-4.0-ultra-generate-001",
                        "displayName": "Imagen 4 Ultra",
                        "description": "Image generation model",
                        "supportedGenerationMethods": ["predict"]
                    ]
                ]
            ]
            let responseData = try JSONSerialization.data(withJSONObject: json)
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseData)
        }

        throw URLError(.unsupportedURL)
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.refreshAvailableModels(trigger: .manual)
    }

    try await waitForModelCatalogRefresh(viewModel: viewModel)

    let models = await MainActor.run { viewModel.availableImageModels }
    #expect(models.count == 1)
    #expect(models.first?.name == "gemini-3-pro-image-preview")

    let textModels = await MainActor.run { viewModel.availableTextModels }
    #expect(textModels.count == 2)
    #expect(textModels.map(\.name) == ["gemini-2.5-flash", "gemini-3-pro-image-preview"])

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func saveSettingsRefreshesModelCatalogWhenApiKeyChanges() async throws {
    let apiKey = "key-model-catalog-save"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            networkClientProvider: networkProvider
        )
    }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let json: [String: Any] = [
            "models": [
                [
                    "name": "models/gemini-3-pro-image-preview",
                    "displayName": "Nano Banana Pro",
                    "description": "Gemini 3 Pro Image Preview",
                    "supportedGenerationMethods": ["generateContent"]
                ]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    await MainActor.run {
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.config.apiKey = apiKey
        viewModel.saveSettings()
    }

    try await waitForModelCatalogRefresh(viewModel: viewModel)

    let models = await MainActor.run { viewModel.availableImageModels }
    #expect(models.count == 1)
    #expect(models.first?.name == "gemini-3-pro-image-preview")

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func checkAPIAvailabilityShowsSuccessMessageWhenCatalogIsReachable() async throws {
    let apiKey = "key-api-check-success"
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])
    let viewModel = try await makeIsolatedViewModel(networkClientProvider: networkProvider)

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.url?.path.contains("/v1beta/models") == true)
        let json: [String: Any] = [
            "models": [
                [
                    "name": "models/nano-banana-pro-preview",
                    "displayName": "Nano Banana Pro",
                    "description": "image generation",
                    "supportedGenerationMethods": ["generateContent"]
                ],
                [
                    "name": "models/gemini-3-flash-preview",
                    "displayName": "Gemini Flash",
                    "description": "general model",
                    "supportedGenerationMethods": ["generateContent"]
                ]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.checkAPIAvailability()
    }

    try await waitForAPICheckCompletion(viewModel: viewModel)

    let message = await MainActor.run { viewModel.apiAvailabilityMessage ?? "" }
    let isError = await MainActor.run { viewModel.apiAvailabilityMessageIsError }
    #expect(!message.isEmpty)
    #expect(isError == false)

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func checkAPIAvailabilityShowsGeoErrorMessage() async throws {
    let apiKey = "key-api-check-geo"
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])
    let viewModel = try await makeIsolatedViewModel(networkClientProvider: networkProvider)

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.url?.path.contains("/v1beta/models") == true)
        let json: [String: Any] = [
            "error": [
                "code": 403,
                "message": "User location is not supported for the API use."
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.checkAPIAvailability()
    }

    try await waitForAPICheckCompletion(viewModel: viewModel)

    let message = await MainActor.run { viewModel.apiAvailabilityMessage ?? "" }
    let isError = await MainActor.run { viewModel.apiAvailabilityMessageIsError }
    #expect(message.localizedCaseInsensitiveContains("location"))
    #expect(isError == true)

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func enhancePromptReplacesPromptWithModelResponse() async throws {
    let apiKey = "key-enhance-success"
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            networkClientProvider: networkProvider
        )
    }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.url?.path.contains(":generateContent") == true)
        let body = try #require(requestBody(from: request))
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try #require(payload["contents"] as? [[String: Any]])
        let firstContent = try #require(contents.first)
        let parts = try #require(firstContent["parts"] as? [[String: Any]])
        #expect(parts.count == 1)
        #expect(parts.first?["text"] as? String == "Improve prompt\n\nold prompt")

        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [["text": "Improved cinematic prompt"]]
                ]
            ]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.config.promptEnhancementModel = "gemini-2.5-flash"
        viewModel.config.promptEnhancementInstruction = "Improve prompt"
        viewModel.prompt = "old prompt"
        viewModel.enhancePrompt()
    }

    try await waitForPromptEnhancementComplete(viewModel: viewModel)

    let prompt = await MainActor.run { viewModel.prompt }
    #expect(prompt == "Improved cinematic prompt")

    let historyItems = await MainActor.run { viewModel.history }
    #expect(historyItems.isEmpty)

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func enhancePromptUsesOpenAIResponsesEndpointForGPTModel() async throws {
    let openAIKey = "sk-openai-enhance"
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            networkClientProvider: networkProvider
        )
    }

    MockURLProtocol.setHandler(forAPIKey: openAIKey) { request in
        let url = try #require(request.url)
        #expect(url.path == "/v1/responses")

        let body = try #require(requestBody(from: request))
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["model"] as? String == "gpt-5.4")

        let input = try #require(payload["input"] as? [[String: Any]])
        let firstInput = try #require(input.first)
        let content = try #require(firstInput["content"] as? [[String: Any]])
        #expect(content.count == 1)
        #expect(content.first?["type"] as? String == "input_text")
        #expect(content.first?["text"] as? String == "Improve prompt\n\nold prompt")

        let responseJSON: [String: Any] = ["output_text": "OpenAI improved prompt"]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    await MainActor.run {
        viewModel.config.openAIAPIKey = openAIKey
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.config.promptEnhancementModel = "gpt-5.4"
        viewModel.config.promptEnhancementInstruction = "Improve prompt"
        viewModel.prompt = "old prompt"
        viewModel.enhancePrompt()
    }

    try await waitForPromptEnhancementComplete(viewModel: viewModel)

    let prompt = await MainActor.run { viewModel.prompt }
    #expect(prompt == "OpenAI improved prompt")

    MockURLProtocol.removeHandler(forAPIKey: openAIKey)
}

@Test
func enhancePromptFailsWhenPromptIsEmpty() async throws {
    let viewModel = try await makeIsolatedViewModel()

    await MainActor.run {
        viewModel.config.apiKey = "key-present"
        viewModel.prompt = "   "
        viewModel.enhancePrompt()
    }

    let errorMessage = await MainActor.run { viewModel.errorMessage }
    #expect(errorMessage != nil)
}

@Test
func enhancePromptShowsOpenAIKeyErrorWhenGPTModelSelectedWithoutOpenAIKey() async throws {
    let viewModel = try await makeIsolatedViewModel()

    await MainActor.run {
        viewModel.config.apiKey = "gemini-key-present"
        viewModel.config.openAIAPIKey = "   "
        viewModel.config.promptEnhancementModel = "gpt-5.4"
        viewModel.prompt = "Prompt body"
        viewModel.enhancePrompt()
    }

    let errorMessage = await MainActor.run { viewModel.errorMessage ?? "" }
    let expected = await MainActor.run { viewModel.localized(AppError.missingOpenAIAPIKey.localizationKey) }
    #expect(errorMessage == expected)
}

@Test
func saveAndApplyPresetReplacesPromptAndParamsAndKeepsAttachments() async throws {
    let viewModel = try await makeIsolatedViewModel()
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    let attachmentURL = tempDirectory.appendingPathComponent("ref.png")
    try tinyPNGData.write(to: attachmentURL)

    let presetID = await MainActor.run { () -> UUID? in
        viewModel.prompt = "Preset prompt content"
        viewModel.config.model = "nano-banana-pro-preview"
        viewModel.resolutionSelection = .k4
        viewModel.aspectRatioSelection = .landscape16x9
        viewModel.imageCountSelection = 3
        viewModel.attachedImages = [
            AttachedImage(fileURL: attachmentURL, displayName: "ref.png", mentionToken: "@ref", thumbnail: nil)
        ]

        viewModel.presetNameDraft = "Cinema preset"
        viewModel.commitPresetFromDraft()

        return viewModel.sortedPromptPresets.first?.id
    }
    let appliedPresetID = try #require(presetID)

    await MainActor.run {
        viewModel.prompt = "Another prompt"
        viewModel.config.model = "gemini-3-pro-image-preview"
        viewModel.resolutionSelection = .k1
        viewModel.aspectRatioSelection = .auto
        viewModel.imageCountSelection = 1
        viewModel.applyPreset(id: appliedPresetID)
    }

    let prompt = await MainActor.run { viewModel.prompt }
    let model = await MainActor.run { viewModel.config.model }
    let resolution = await MainActor.run { viewModel.resolutionSelection }
    let aspect = await MainActor.run { viewModel.aspectRatioSelection }
    let imageCount = await MainActor.run { viewModel.imageCountSelection }
    let attachments = await MainActor.run { viewModel.attachedImages }

    #expect(prompt == "Preset prompt content")
    #expect(model == "nano-banana-pro-preview")
    #expect(resolution == .k4)
    #expect(aspect == .landscape16x9)
    #expect(imageCount == 3)
    #expect(attachments.count == 1)
    #expect(attachments.first?.mentionToken == "@ref")
}

@Test
func duplicatePresetTriggersOverwriteFlowAndCanReplace() async throws {
    let viewModel = try await makeIsolatedViewModel()

    await MainActor.run {
        viewModel.prompt = "Initial preset body"
        viewModel.presetNameDraft = "Reusable"
        viewModel.commitPresetFromDraft()

        viewModel.prompt = "Updated preset body"
        viewModel.presetNameDraft = "reusable"
        viewModel.commitPresetFromDraft()
    }

    let overwriteShown = await MainActor.run { viewModel.isPresetOverwriteAlertPresented }
    let pendingName = await MainActor.run { viewModel.pendingPresetOverwriteName }
    let beforeConfirmPrompt = await MainActor.run { viewModel.sortedPromptPresets.first?.prompt }
    #expect(overwriteShown == true)
    #expect(pendingName?.lowercased() == "reusable")
    #expect(beforeConfirmPrompt == "Initial preset body")

    await MainActor.run {
        viewModel.confirmPresetOverwrite()
    }

    let presets = await MainActor.run { viewModel.sortedPromptPresets }
    #expect(presets.count == 1)
    #expect(presets.first?.prompt == "Updated preset body")
    let overwriteHidden = await MainActor.run { viewModel.isPresetOverwriteAlertPresented }
    #expect(overwriteHidden == false)
}

@Test
func updatePresetChangesNameAndPromptText() async throws {
    let viewModel = try await makeIsolatedViewModel()

    let presetID = await MainActor.run { () -> UUID? in
        viewModel.prompt = "Original preset body"
        viewModel.presetNameDraft = "Reusable"
        viewModel.commitPresetFromDraft()
        return viewModel.sortedPromptPresets.first?.id
    }
    let updatedPresetID = try #require(presetID)

    await MainActor.run {
        viewModel.updatePreset(
            id: updatedPresetID,
            newName: "Reusable Updated",
            newPrompt: "Updated preset body"
        )
    }

    let presets = await MainActor.run { viewModel.sortedPromptPresets }
    #expect(presets.count == 1)
    #expect(presets.first?.id == updatedPresetID)
    #expect(presets.first?.name == "Reusable Updated")
    #expect(presets.first?.prompt == "Updated preset body")
}

@Test
func generatePromptFromImageHappyPathReplacesPromptAndTogglesProgressState() async throws {
    let apiKey = "key-smoke-prompt-from-image"
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let imageURL = tempDirectory.appendingPathComponent("source.png")
    try tinyPNGData.write(to: imageURL)

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            networkClientProvider: networkProvider
        )
    }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let body = try #require(requestBody(from: request))
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try #require(payload["contents"] as? [[String: Any]])
        let firstContent = try #require(contents.first)
        let parts = try #require(firstContent["parts"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["inlineData"] != nil)
        #expect(parts[1]["text"] as? String == "Build from image")

        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [["text": "Prompt from dropped image"]]
                ]
            ]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.config.promptEnhancementModel = "gemini-3-flash-preview"
        viewModel.config.promptFromImageInstruction = "Build from image"
        viewModel.prompt = "old prompt"
        viewModel.generatePromptFromImage(from: [imageURL])
    }

    let started = await MainActor.run { viewModel.isGeneratingPromptFromImage }
    #expect(started == true)

    try await waitForPromptFromImageComplete(viewModel: viewModel)

    let finished = await MainActor.run { viewModel.isGeneratingPromptFromImage }
    let prompt = await MainActor.run { viewModel.prompt }
    let successMessage = await MainActor.run { viewModel.successMessage }
    #expect(finished == false)
    #expect(prompt == "Prompt from dropped image")
    #expect(successMessage != nil)

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generatePromptFromImageUsesOpenAIResponsesEndpointWithInputImage() async throws {
    let openAIKey = "sk-openai-prompt-from-image"
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let imageURL = tempDirectory.appendingPathComponent("source.png")
    try tinyPNGData.write(to: imageURL)

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            networkClientProvider: networkProvider
        )
    }

    MockURLProtocol.setHandler(forAPIKey: openAIKey) { request in
        let url = try #require(request.url)
        #expect(url.path == "/v1/responses")

        let body = try #require(requestBody(from: request))
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["model"] as? String == "gpt-5.4")

        let input = try #require(payload["input"] as? [[String: Any]])
        let firstInput = try #require(input.first)
        let content = try #require(firstInput["content"] as? [[String: Any]])
        #expect(content.count == 2)

        let imagePart = try #require(content.first(where: { ($0["type"] as? String) == "input_image" }))
        let imageURLValue = try #require(imagePart["image_url"] as? String)
        #expect(imageURLValue.hasPrefix("data:image/png;base64,"))

        let textPart = try #require(content.first(where: { ($0["type"] as? String) == "input_text" }))
        #expect(textPart["text"] as? String == "Build from image")

        let responseJSON: [String: Any] = ["output_text": "Prompt from OpenAI image input"]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    await MainActor.run {
        viewModel.config.openAIAPIKey = openAIKey
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.config.promptEnhancementModel = "gpt-5.4"
        viewModel.config.promptFromImageInstruction = "Build from image"
        viewModel.prompt = "old prompt"
        viewModel.generatePromptFromImage(from: [imageURL])
    }

    try await waitForPromptFromImageComplete(viewModel: viewModel)

    let prompt = await MainActor.run { viewModel.prompt }
    #expect(prompt == "Prompt from OpenAI image input")

    MockURLProtocol.removeHandler(forAPIKey: openAIKey)
}

@Test
func generatePromptFromImageDoesNotAppendDroppedImageToAttachments() async throws {
    let apiKey = "key-smoke-prompt-from-image-no-attach"
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let imageURL = tempDirectory.appendingPathComponent("source.png")
    try tinyPNGData.write(to: imageURL)

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            networkClientProvider: networkProvider
        )
    }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [["text": "Prompt ready"]]
                ]
            ]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.attachedImages = [
            AttachedImage(fileURL: imageURL, displayName: "existing.png", mentionToken: "@existing", thumbnail: nil)
        ]
        viewModel.generatePromptFromImage(from: [imageURL])
    }

    try await waitForPromptFromImageComplete(viewModel: viewModel)

    let attachments = await MainActor.run { viewModel.attachedImages }
    #expect(attachments.count == 1)
    #expect(attachments.first?.mentionToken == "@existing")

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generatePromptFromImageShowsErrorWhenModelLacksImageInput() async throws {
    let apiKey = "key-smoke-prompt-from-image-unsupported"
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let imageURL = tempDirectory.appendingPathComponent("source.png")
    try tinyPNGData.write(to: imageURL)

    let viewModel = await MainActor.run {
        MainViewModel(
            configStore: configStore,
            historyStore: historyStore,
            networkClientProvider: networkProvider
        )
    }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let json: [String: Any] = [
            "error": [
                "code": 400,
                "message": "image input modality is not enabled for this model"
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.prompt = "unchanged prompt"
        viewModel.generatePromptFromImage(from: [imageURL])
    }

    try await waitForPromptFromImageComplete(viewModel: viewModel)

    let prompt = await MainActor.run { viewModel.prompt }
    let errorMessage = await MainActor.run { viewModel.errorMessage ?? "" }
    let localizedPrefix = await MainActor.run { viewModel.localized("error.prompt_from_image_model_not_supported") }
    #expect(prompt == "unchanged prompt")
    #expect(errorMessage.contains(localizedPrefix))

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@MainActor
private func makeIsolatedViewModel(
    apiClient: GeminiAPIClient = GeminiAPIClient(),
    networkClientProvider: NetworkClientProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])
) throws -> MainViewModel {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))

    return MainViewModel(
        configStore: configStore,
        historyStore: historyStore,
        apiClient: apiClient,
        networkClientProvider: networkClientProvider
    )
}

private struct ProxyFirstThenDirectProvider: NetworkClientProvider {
    let protocolClasses: [AnyClass]?

    func validate(config: AppConfig) -> ProxyValidationResult {
        ProxySessionFactory(protocolClasses: protocolClasses).validate(config: config)
    }

    func makeSession(config: AppConfig, route: NetworkRoute) throws -> URLSession {
        if route == .proxy {
            throw AppError.proxyConnectionFailed("Simulated proxy failure")
        }
        return try ProxySessionFactory(protocolClasses: protocolClasses).makeSession(config: config, route: .directFallback)
    }
}

private func waitForGenerationToComplete(viewModel: MainViewModel) async throws {
    for _ in 0..<120 {
        let isGenerating = await MainActor.run { viewModel.isGenerating }
        if !isGenerating {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    Issue.record("Generation did not complete in time")
}

private func waitForModelCatalogRefresh(viewModel: MainViewModel) async throws {
    for _ in 0..<120 {
        let isLoading = await MainActor.run { viewModel.isLoadingModels }
        if !isLoading {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    Issue.record("Model catalog refresh did not complete in time")
}

private func waitForPromptEnhancementComplete(viewModel: MainViewModel) async throws {
    for _ in 0..<120 {
        let isEnhancing = await MainActor.run { viewModel.isEnhancingPrompt }
        if !isEnhancing {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    Issue.record("Prompt enhancement did not complete in time")
}

private func waitForPromptFromImageComplete(viewModel: MainViewModel) async throws {
    for _ in 0..<120 {
        let isGenerating = await MainActor.run { viewModel.isGeneratingPromptFromImage }
        if !isGenerating {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    Issue.record("Prompt-from-image generation did not complete in time")
}

private func waitForAPICheckCompletion(viewModel: MainViewModel) async throws {
    for _ in 0..<120 {
        let isChecking = await MainActor.run { viewModel.isCheckingAPIAvailability }
        if !isChecking {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    Issue.record("API availability check did not complete in time")
}

private func setSingleGenerationHandler(
    forAPIKey apiKey: String,
    imageBase64: String
) {
    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let url = try #require(request.url)
        #expect(url.path.contains(":generateContent") == true)

        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [
                        ["text": "single-image"],
                        ["inlineData": ["mimeType": "image/png", "data": imageBase64]]
                    ]
                ]
            ]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }
}

private func setMultiSingleGenerationHandler(
    forAPIKey apiKey: String,
    expectedRequestCount: Int,
    imageBase64s: [String]
) {
    let fallbackBase64 = imageBase64s.first ?? tinyPNGBase64
    var requestCount = 0

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let url = try #require(request.url)
        #expect(url.path.contains(":generateContent") == true)

        requestCount += 1
        let selectedImage = requestCount <= imageBase64s.count
            ? imageBase64s[requestCount - 1]
            : fallbackBase64

        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [
                        ["text": "single-image-\(requestCount)"],
                        ["inlineData": ["mimeType": "image/png", "data": selectedImage]]
                    ]
                ]
            ]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }
}

private func setOpenAIImageGenerationHandler(
    forAPIKey apiKey: String,
    imageBase64: String
) {
    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let url = try #require(request.url)
        #expect(url.path.contains("/v1/images/generations") == true)

        let body = try #require(requestBody(from: request))
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-image-2")
        #expect(json["response_format"] == nil)
        #expect(json["output_format"] as? String == "png")

        let responseJSON: [String: Any] = [
            "data": [[
                "b64_json": imageBase64,
                "revised_prompt": "openai-image"
            ]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }
}

private func setBatchGenerationHandler(
    forAPIKey apiKey: String,
    expectedRequestCount: Int,
    imageBase64s: [String]
) {
    var statusRequests = 0

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let url = try #require(request.url)
        let path = url.path

        if path.contains(":batchGenerateContent") {
            let body = try #require(requestBody(from: request))
            let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let batch = try #require(payload["batch"] as? [String: Any])
            let inputConfig = try #require(batch["inputConfig"] as? [String: Any])
            let requestsContainer = try #require(inputConfig["requests"] as? [String: Any])
            let requests = try #require(requestsContainer["requests"] as? [[String: Any]])
            #expect(requests.count == expectedRequestCount)

            let createJSON: [String: Any] = [
                "name": "batches/\(apiKey)-operation",
                "done": false,
                "metadata": [
                    "state": "BATCH_STATE_PENDING"
                ]
            ]
            let responseData = try JSONSerialization.data(withJSONObject: createJSON)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseData)
        }

        if path.contains("/v1beta/batches/") {
            statusRequests += 1

            let responses: [[String: Any]] = imageBase64s.enumerated().map { index, base64 in
                [
                    "response": [
                        "candidates": [[
                            "content": [
                                "parts": [
                                    ["text": "image-\(index + 1)"],
                                    ["inlineData": ["mimeType": "image/png", "data": base64]]
                                ]
                            ]
                        ]]
                    ],
                    "metadata": ["key": "request-\(index + 1)"]
                ]
            }

            let state = statusRequests == 1 ? "BATCH_STATE_RUNNING" : "BATCH_STATE_SUCCEEDED"
            let done = statusRequests > 1
            let statusJSON: [String: Any] = [
                "name": "batches/\(apiKey)-operation",
                "done": done,
                "metadata": [
                    "state": state
                ],
                "response": done ? ["inlinedResponses": responses] : [:]
            ]

            let responseData = try JSONSerialization.data(withJSONObject: statusJSON)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseData)
        }

        throw URLError(.unsupportedURL)
    }
}

private let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+2YQAAAAASUVORK5CYII="
private let tinyPNGBase64Alt = tinyPNGBase64
private let tinyPNGBase64SecondAlt = tinyPNGBase64
private let tinyPNGData = Data(base64Encoded: tinyPNGBase64)!

private func requestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var result = Data()
    let bufferSize = 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read < 0 {
            return nil
        }
        if read == 0 {
            break
        }
        result.append(buffer, count: read)
    }

    return result
}
