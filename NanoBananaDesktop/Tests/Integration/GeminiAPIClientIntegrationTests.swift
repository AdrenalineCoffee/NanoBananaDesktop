import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func generateImageReturnsDecodedImageData() async throws {
    let apiKey = "key-success"
    let session = makeSession()
    let client = GeminiAPIClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.httpMethod == "POST")

        if let body = requestBody(from: request),
           let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            #expect(payload["config"] != nil || payload["generationConfig"] != nil)
        }

        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [
                        ["text": "done"],
                        ["inlineData": ["mimeType": "image/png", "data": "YWJj"]]
                    ]
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

    let request = GenerationRequest(
        mode: .generate,
        prompt: "test",
        model: AppConfig.defaultModel,
        apiKey: apiKey,
        resolution: .k1,
        aspectRatio: .square,
        inputImages: []
    )

    let result = try await client.generateImage(
        request: request,
        timeoutSec: 30,
        session: session,
        route: .proxy
    )
    #expect(result.imageData == Data("abc".utf8))
    #expect(result.modelText == "done")

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateImageSendsAllInputImagesBeforeTextPart() async throws {
    let apiKey = "key-multi"
    let session = makeSession()
    let client = GeminiAPIClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let body = try #require(requestBody(from: request))
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try #require(payload["contents"] as? [[String: Any]])
        let firstContent = try #require(contents.first)
        let parts = try #require(firstContent["parts"] as? [[String: Any]])
        #expect(parts.count == 3)
        #expect(parts[0]["inlineData"] != nil)
        #expect(parts[1]["inlineData"] != nil)
        #expect(parts[2]["text"] as? String == "transfer face")

        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [["inlineData": ["mimeType": "image/png", "data": "YWJj"]]]
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

    let request = GenerationRequest(
        mode: .edit,
        prompt: "transfer face",
        model: AppConfig.defaultModel,
        apiKey: apiKey,
        resolution: .k1,
        aspectRatio: .square,
        inputImages: [
            GenerationInputImage(
                fileURL: URL(fileURLWithPath: "/tmp/a.png"),
                filename: "a.png",
                mimeType: "image/png",
                data: Data("a".utf8)
            ),
            GenerationInputImage(
                fileURL: URL(fileURLWithPath: "/tmp/b.png"),
                filename: "b.png",
                mimeType: "image/png",
                data: Data("b".utf8)
            )
        ]
    )

    _ = try await client.generateImage(
        request: request,
        timeoutSec: 30,
        session: session,
        route: .proxy
    )

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateImageIncludesAspectRatioInImageConfig() async throws {
    let apiKey = "key-aspect"
    let session = makeSession()
    let client = GeminiAPIClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let body = try #require(requestBody(from: request))
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let config = (payload["config"] as? [String: Any]) ?? (payload["generationConfig"] as? [String: Any])
        let imageConfig = try #require(config?["imageConfig"] as? [String: Any])
        #expect(imageConfig["aspectRatio"] as? String == "16:9")

        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [["inlineData": ["mimeType": "image/png", "data": "YWJj"]]]
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

    let request = GenerationRequest(
        mode: .generate,
        prompt: "cinematic portrait",
        model: AppConfig.defaultModel,
        apiKey: apiKey,
        resolution: .k2,
        aspectRatio: .landscape16x9,
        inputImages: []
    )

    _ = try await client.generateImage(
        request: request,
        timeoutSec: 30,
        session: session,
        route: .proxy
    )

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateImageMapsQuotaError() async throws {
    let apiKey = "key-quota"
    let session = makeSession()
    let client = GeminiAPIClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let json: [String: Any] = [
            "error": [
                "code": 403,
                "message": "Quota exceeded"
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

    let request = GenerationRequest(
        mode: .generate,
        prompt: "test",
        model: AppConfig.defaultModel,
        apiKey: apiKey,
        resolution: .k1,
        aspectRatio: .square,
        inputImages: []
    )

    do {
        _ = try await client.generateImage(
            request: request,
            timeoutSec: 30,
            session: session,
            route: .proxy
        )
        Issue.record("Expected quota error")
    } catch let error as AppError {
        #expect(error == .quotaExceeded)
    }

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateImageMapsProxyAuthError() async throws {
    let apiKey = "key-proxy-auth"
    let session = makeSession()
    let client = GeminiAPIClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let json: [String: Any] = [
            "error": [
                "code": 407,
                "message": "Proxy Authentication Required"
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 407,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    let request = GenerationRequest(
        mode: .generate,
        prompt: "test",
        model: AppConfig.defaultModel,
        apiKey: apiKey,
        resolution: .k1,
        aspectRatio: .square,
        inputImages: []
    )

    do {
        _ = try await client.generateImage(
            request: request,
            timeoutSec: 30,
            session: session,
            route: .proxy
        )
        Issue.record("Expected proxy auth error")
    } catch let error as AppError {
        guard case .proxyAuthFailed = error else {
            Issue.record("Expected proxy auth error")
            return
        }
    }

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateTextReturnsFirstTextPart() async throws {
    let apiKey = "key-text-success"
    let session = makeSession()
    let client = GeminiAPIClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.httpMethod == "POST")

        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [
                        ["text": "Improved prompt"],
                        ["text": "Extra text"]
                    ]
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

    let result = try await client.generateText(
        prompt: "Improve this",
        model: "gemini-2.5-flash",
        apiKey: apiKey,
        timeoutSec: 30,
        session: session,
        route: .proxy
    )

    #expect(result == "Improved prompt")
    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateTextThrowsWhenNoTextPartInResponse() async throws {
    let apiKey = "key-text-no-parts"
    let session = makeSession()
    let client = GeminiAPIClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [["inlineData": ["mimeType": "image/png", "data": "YWJj"]]]
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

    do {
        _ = try await client.generateText(
            prompt: "Improve this",
            model: "gemini-2.5-flash",
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

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

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
        let readCount = stream.read(&buffer, maxLength: bufferSize)
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
