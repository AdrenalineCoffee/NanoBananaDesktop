import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func kieTextClientUsesResponsesEndpointForGPT54() async throws {
    let apiKey = "kie-text-responses"
    let client = KieAITextAPIClient()
    let session = makeKieTextSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.url?.path == "/codex/v1/responses")
        let payload = try kieTextJSONObject(from: request)
        #expect(payload["model"] as? String == "gpt-5-4")
        #expect(payload["stream"] as? Bool == false)
        let input = try #require(payload["input"] as? [[String: Any]])
        let content = try #require(input.first?["content"] as? [[String: Any]])
        #expect(content.contains { ($0["type"] as? String) == "input_text" && ($0["text"] as? String) == "Improve prompt" })

        let data = try JSONSerialization.data(withJSONObject: [
            "output_text": "Improved prompt"
        ])
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            data
        )
    }

    let text = try await client.generateText(
        prompt: "Improve prompt",
        model: "kie:gpt-5-4",
        apiKey: apiKey,
        timeoutSec: 5,
        session: session,
        route: .directFallback
    )

    #expect(text == "Improved prompt")
}

@Test
func kieTextClientSendsChatCompletionsPayloadWithTypedContent() async throws {
    let apiKey = "kie-text-chat"
    let client = KieAITextAPIClient()
    let session = makeKieTextSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.url?.path == "/gpt-5-2/v1/chat/completions")
        let payload = try kieTextJSONObject(from: request)
        #expect(payload["model"] == nil)
        let messages = try #require(payload["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "user")
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.contains { ($0["type"] as? String) == "text" && ($0["text"] as? String) == "Improve prompt" })

        return try kieTextJSONResponse(
            url: request.url!,
            object: ["choices": [["message": ["content": [["type": "text", "text": "Improved chat prompt"]]]]]]
        )
    }

    let text = try await client.generateText(
        prompt: "Improve prompt",
        model: "kie:gpt-5-2",
        apiKey: apiKey,
        timeoutSec: 5,
        session: session,
        route: .directFallback
    )

    #expect(text == "Improved chat prompt")
}

@Test
func kieTextClientUsesClaudeMessagesEndpointForOpus() async throws {
    let apiKey = "kie-text-claude"
    let client = KieAITextAPIClient()
    let session = makeKieTextSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.url?.path == "/claude/v1/messages")
        let payload = try kieTextJSONObject(from: request)
        #expect(payload["model"] as? String == "claude-opus-4-7")
        #expect(payload["stream"] as? Bool == false)
        #expect(payload["max_tokens"] as? Int == 4096)
        let messages = try #require(payload["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "user")
        #expect(messages.first?["content"] as? String == "Improve prompt")

        return try kieTextJSONResponse(
            url: request.url!,
            object: ["content": [["type": "text", "text": "Improved Claude prompt"]]]
        )
    }

    let text = try await client.generateText(
        prompt: "Improve prompt",
        model: "kie:claude-opus-4-7",
        apiKey: apiKey,
        timeoutSec: 5,
        session: session,
        route: .directFallback
    )

    #expect(text == "Improved Claude prompt")
}

@Test
func kieTextClientParsesEventStreamTextChunks() async throws {
    let apiKey = "kie-text-sse"
    let client = KieAITextAPIClient()
    let session = makeKieTextSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.url?.path == "/codex/v1/responses")
        let data = """
        data: {"choices":[{"delta":{"content":"Improved"}}]}
        data: {"choices":[{"delta":{"content":" prompt"}}]}
        data: [DONE]

        """.data(using: .utf8)!
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!,
            data
        )
    }

    let text = try await client.generateText(
        prompt: "Improve prompt",
        model: "kie:gpt-5-4",
        apiKey: apiKey,
        timeoutSec: 5,
        session: session,
        route: .directFallback
    )

    #expect(text == "Improved prompt")
}

@Test
func kieTextClientUploadsImageAndSendsResponsesImageInput() async throws {
    let apiKey = "kie-text-image"
    let client = KieAITextAPIClient()
    let session = makeKieTextSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        switch request.url?.path {
        case "/api/file-base64-upload":
            return try kieTextJSONResponse(
                url: request.url!,
                object: ["code": 200, "msg": "success", "data": ["downloadUrl": "https://example.com/ref.png"]]
            )
        case "/codex/v1/responses":
            let payload = try kieTextJSONObject(from: request)
            let input = try #require(payload["input"] as? [[String: Any]])
            let content = try #require(input.first?["content"] as? [[String: Any]])
            #expect(content.contains { ($0["type"] as? String) == "input_image" && ($0["image_url"] as? String) == "https://example.com/ref.png" })
            #expect(content.contains { ($0["type"] as? String) == "input_text" && ($0["text"] as? String) == "Describe image" })
            return try kieTextJSONResponse(
                url: request.url!,
                object: ["data": ["output_text": "Prompt from Kie image"]]
            )
        default:
            throw URLError(.badURL)
        }
    }

    let text = try await client.generateTextFromImages(
        prompt: "Describe image",
        model: "kie:gpt-5-4",
        apiKey: apiKey,
        images: [
            GenerationInputImage(
                fileURL: URL(fileURLWithPath: "/tmp/ref.png"),
                filename: "ref.png",
                mimeType: "image/png",
                data: kieTextTinyPNGData
            )
        ],
        timeoutSec: 5,
        session: session,
        route: .directFallback
    )

    #expect(text == "Prompt from Kie image")
}

@Test
func kieTextClientRejectsImageInputForUnsupportedModel() async throws {
    let client = KieAITextAPIClient()
    let session = makeKieTextSession()

    do {
        _ = try await client.generateTextFromImages(
            prompt: "Describe image",
            model: "kie:codex",
            apiKey: "unused",
            images: [
                GenerationInputImage(
                    fileURL: URL(fileURLWithPath: "/tmp/ref.png"),
                    filename: "ref.png",
                    mimeType: "image/png",
                    data: kieTextTinyPNGData
                )
            ],
            timeoutSec: 5,
            session: session,
            route: .directFallback
        )
        Issue.record("Expected unsupported image input error")
    } catch let error as AppError {
        guard case .promptFromImageModelNotSupported = error else {
            Issue.record("Expected promptFromImageModelNotSupported error")
            return
        }
    }
}

private func makeKieTextSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func kieTextJSONObject(from request: URLRequest) throws -> [String: Any] {
    let body = try kieTextRequestBodyData(from: request)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func kieTextRequestBodyData(from request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        throw URLError(.badURL)
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: bufferSize)
        if readCount < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeRawData)
        }
        if readCount == 0 {
            break
        }
        data.append(buffer, count: readCount)
    }

    return data
}

private func kieTextJSONResponse(url: URL, object: [String: Any]) throws -> (HTTPURLResponse, Data) {
    let data = try JSONSerialization.data(withJSONObject: object)
    return (
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        data
    )
}

private let kieTextTinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+2YQAAAAASUVORK5CYII="
private let kieTextTinyPNGData = Data(base64Encoded: kieTextTinyPNGBase64)!
