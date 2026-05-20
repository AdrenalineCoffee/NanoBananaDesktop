import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func openAIGenerateTextUsesResponsesEndpointAndReturnsOutputText() async throws {
    let apiKey = "sk-openai-text-success"
    let session = makeOpenAISession()
    let client = OpenAITextAPIClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let url = try #require(request.url)
        #expect(url.path == "/v1/responses")
        #expect(request.httpMethod == "POST")

        let body = try #require(openAIRequestBody(from: request))
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["model"] as? String == "gpt-5.4")

        let input = try #require(payload["input"] as? [[String: Any]])
        let firstInput = try #require(input.first)
        let content = try #require(firstInput["content"] as? [[String: Any]])
        #expect(content.count == 1)
        #expect(content.first?["type"] as? String == "input_text")
        #expect(content.first?["text"] as? String == "Improve this prompt")

        let responseJSON: [String: Any] = ["output_text": "Improved prompt from OpenAI"]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, responseData)
    }

    let text = try await client.generateText(
        prompt: "Improve this prompt",
        model: "gpt-5.4",
        apiKey: apiKey,
        timeoutSec: 30,
        session: session,
        route: .proxy
    )

    #expect(text == "Improved prompt from OpenAI")
    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func openAIGenerateTextFromImagesSendsInputImageAndText() async throws {
    let apiKey = "sk-openai-text-image"
    let session = makeOpenAISession()
    let client = OpenAITextAPIClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let body = try #require(openAIRequestBody(from: request))
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["model"] as? String == "gpt-5.4")

        let input = try #require(payload["input"] as? [[String: Any]])
        let firstInput = try #require(input.first)
        let content = try #require(firstInput["content"] as? [[String: Any]])
        #expect(content.count == 2)

        let imagePart = try #require(content.first(where: { ($0["type"] as? String) == "input_image" }))
        let imageURL = try #require(imagePart["image_url"] as? String)
        #expect(imageURL.hasPrefix("data:image/png;base64,"))

        let textPart = try #require(content.first(where: { ($0["type"] as? String) == "input_text" }))
        #expect(textPart["text"] as? String == "Describe this image")

        let responseJSON: [String: Any] = [
            "output": [[
                "content": [[
                    "type": "output_text",
                    "text": "Image prompt extracted"
                ]]
            ]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, responseData)
    }

    let text = try await client.generateTextFromImages(
        prompt: "Describe this image",
        model: "gpt-5.4",
        apiKey: apiKey,
        images: [
            GenerationInputImage(
                fileURL: URL(fileURLWithPath: "/tmp/a.png"),
                filename: "a.png",
                mimeType: "image/png",
                data: Data("a".utf8)
            )
        ],
        timeoutSec: 30,
        session: session,
        route: .proxy
    )

    #expect(text == "Image prompt extracted")
    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func openAIGenerateTextThrowsNoTextWhenResponseHasNoText() async throws {
    let apiKey = "sk-openai-no-text"
    let session = makeOpenAISession()
    let client = OpenAITextAPIClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let responseJSON: [String: Any] = ["output": []]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, responseData)
    }

    do {
        _ = try await client.generateText(
            prompt: "test",
            model: "gpt-5.4",
            apiKey: apiKey,
            timeoutSec: 30,
            session: session,
            route: .proxy
        )
        Issue.record("Expected noTextInResponse error")
    } catch let error as AppError {
        #expect(error == .noTextInResponse)
    }

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func openAIGenerateTextFromImagesMapsUnsupportedImageModality() async throws {
    let apiKey = "sk-openai-image-unsupported"
    let session = makeOpenAISession()
    let client = OpenAITextAPIClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let json: [String: Any] = [
            "error": [
                "message": "image input modality is not enabled for this model"
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(url: try #require(request.url), statusCode: 400, httpVersion: nil, headerFields: nil)!
        return (response, responseData)
    }

    do {
        _ = try await client.generateTextFromImages(
            prompt: "Describe this image",
            model: "gpt-5.4",
            apiKey: apiKey,
            images: [
                GenerationInputImage(
                    fileURL: URL(fileURLWithPath: "/tmp/a.png"),
                    filename: "a.png",
                    mimeType: "image/png",
                    data: Data("a".utf8)
                )
            ],
            timeoutSec: 30,
            session: session,
            route: .proxy
        )
        Issue.record("Expected promptFromImageModelNotSupported error")
    } catch let error as AppError {
        guard case .promptFromImageModelNotSupported = error else {
            Issue.record("Expected promptFromImageModelNotSupported error")
            return
        }
    }

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

private func makeOpenAISession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func openAIRequestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)

    while stream.hasBytesAvailable {
        let readCount = stream.read(&buffer, maxLength: buffer.count)
        if readCount < 0 {
            return nil
        }
        if readCount == 0 {
            break
        }
        result.append(buffer, count: readCount)
    }

    return result
}
