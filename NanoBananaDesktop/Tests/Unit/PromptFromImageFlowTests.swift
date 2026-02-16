import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func generatePromptFromImageUsesFirstValidImageAndReplacesPrompt() async throws {
    let apiKey = "key-prompt-from-image-success"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let invalidFile = tempDirectory.appendingPathComponent("notes.txt")
    let imageFile = tempDirectory.appendingPathComponent("source.png")
    try Data("not-image".utf8).write(to: invalidFile)
    try tinyPNGData.write(to: imageFile)

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
        let body = try #require(requestBody(from: request))
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try #require(payload["contents"] as? [[String: Any]])
        let firstContent = try #require(contents.first)
        let parts = try #require(firstContent["parts"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["inlineData"] != nil)
        #expect(parts[1]["text"] as? String == "Build prompt from image")

        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [["text": "Cinematic banana portrait prompt"]]
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
        viewModel.config.promptFromImageInstruction = "Build prompt from image"
        viewModel.prompt = "old prompt"
        viewModel.generatePromptFromImage(from: [invalidFile, imageFile])
    }

    try await waitForPromptFromImageComplete(viewModel: viewModel)

    let prompt = await MainActor.run { viewModel.prompt }
    let successMessage = await MainActor.run { viewModel.successMessage }
    let errorMessage = await MainActor.run { viewModel.errorMessage }
    let attachments = await MainActor.run { viewModel.attachedImages }

    #expect(prompt == "Cinematic banana portrait prompt")
    #expect(successMessage != nil)
    #expect(errorMessage == nil)
    #expect(attachments.isEmpty)

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generatePromptFromImageFailsWithoutValidDroppedFileAndSkipsNetworkCall() async throws {
    let apiKey = "key-prompt-from-image-invalid-drop"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let invalidFile = tempDirectory.appendingPathComponent("notes.txt")
    try Data("not-image".utf8).write(to: invalidFile)

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

    let networkWasCalled = LockedFlag()
    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        networkWasCalled.setTrue()
        throw URLError(.badServerResponse)
    }

    await MainActor.run {
        viewModel.config.apiKey = apiKey
        viewModel.config.proxyEnabled = true
        viewModel.config.proxyHost = "proxy.local"
        viewModel.config.proxyPort = 8080
        viewModel.prompt = "keep this prompt"
        viewModel.generatePromptFromImage(from: [invalidFile])
    }

    let prompt = await MainActor.run { viewModel.prompt }
    let isGenerating = await MainActor.run { viewModel.isGeneratingPromptFromImage }
    let errorMessage = await MainActor.run { viewModel.errorMessage }

    #expect(prompt == "keep this prompt")
    #expect(isGenerating == false)
    #expect(errorMessage != nil)
    #expect(networkWasCalled.value == false)

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generatePromptFromImageShowsLocalizedErrorWhenModelDoesNotSupportImageInput() async throws {
    let apiKey = "key-prompt-from-image-unsupported"
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let imageFile = tempDirectory.appendingPathComponent("source.png")
    try tinyPNGData.write(to: imageFile)

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
        viewModel.config.promptEnhancementModel = "gemini-3-flash-preview"
        viewModel.prompt = "original prompt"
        viewModel.generatePromptFromImage(from: [imageFile])
    }

    try await waitForPromptFromImageComplete(viewModel: viewModel)

    let prompt = await MainActor.run { viewModel.prompt }
    let errorMessage = await MainActor.run { viewModel.errorMessage ?? "" }
    let localizedPrefix = await MainActor.run { viewModel.localized("error.prompt_from_image_model_not_supported") }

    #expect(prompt == "original prompt")
    #expect(errorMessage.contains(localizedPrefix))

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

private func waitForPromptFromImageComplete(viewModel: MainViewModel) async throws {
    for _ in 0..<120 {
        let isGenerating = await MainActor.run { viewModel.isGeneratingPromptFromImage }
        if !isGenerating {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    Issue.record("Prompt-from-image flow did not complete in time")
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func setTrue() {
        lock.lock()
        _value = true
        lock.unlock()
    }
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
