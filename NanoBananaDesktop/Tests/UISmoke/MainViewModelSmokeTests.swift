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

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [["inlineData": ["mimeType": "image/png", "data": tinyPNGBase64]]]
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

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [["inlineData": ["mimeType": "image/png", "data": tinyPNGBase64]]]
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
func generateFlowFailsWhenProxyInvalidAndFallbackOff() async throws {
    let client = GeminiAPIClient()
    let networkProvider = ProxySessionFactory(protocolClasses: [MockURLProtocol.self])

    let viewModel = await MainActor.run {
        MainViewModel(apiClient: client, networkClientProvider: networkProvider)
    }

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

    let viewModel = await MainActor.run {
        MainViewModel()
    }

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
func generateFlowAllowsDirectFallbackWhenEnabled() async throws {
    let apiKey = "key-direct-fallback"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    let client = GeminiAPIClient()

    let failingProxyThenDirectProvider = ProxyFirstThenDirectProvider(protocolClasses: [MockURLProtocol.self])

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [["inlineData": ["mimeType": "image/png", "data": tinyPNGBase64]]]
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
    let viewModel = await MainActor.run {
        MainViewModel(networkClientProvider: networkProvider)
    }

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
    #expect(textModels.map(\.name) == ["gemini-3-pro-image-preview", "gemini-2.5-flash"])

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
func enhancePromptFailsWhenPromptIsEmpty() async throws {
    let viewModel = await MainActor.run {
        MainViewModel()
    }

    await MainActor.run {
        viewModel.config.apiKey = "key-present"
        viewModel.prompt = "   "
        viewModel.enhancePrompt()
    }

    let errorMessage = await MainActor.run { viewModel.errorMessage }
    #expect(errorMessage != nil)
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

private let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+2YQAAAAASUVORK5CYII="
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
