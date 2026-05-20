import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func kieTextClientSendsChatCompletionsPayload() async throws {
    let apiKey = "kie-text-chat"
    let client = KieAITextAPIClient()
    let session = makeKieTextSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.url?.path == "/gpt-5-4/v1/chat/completions")
        let payload = try kieTextJSONObject(from: request)
        #expect(payload["model"] as? String == "gpt-5-4")
        let messages = try #require(payload["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "user")
        #expect(messages.first?["content"] as? String == "Improve prompt")

        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": "Improved prompt"]]]
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
func kieTextClientUploadsImageAndSendsImageURLContent() async throws {
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
        case "/gpt-5-4/v1/chat/completions":
            let payload = try kieTextJSONObject(from: request)
            let messages = try #require(payload["messages"] as? [[String: Any]])
            let content = try #require(messages.first?["content"] as? [[String: Any]])
            #expect(content.contains { ($0["type"] as? String) == "image_url" })
            #expect(content.contains { ($0["type"] as? String) == "text" && ($0["text"] as? String) == "Describe image" })
            return try kieTextJSONResponse(
                url: request.url!,
                object: ["choices": [["message": ["content": "Prompt from Kie image"]]]]
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
