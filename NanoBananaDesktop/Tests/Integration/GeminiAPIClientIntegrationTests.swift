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
func generateImagesBatchCreatesRequestedCountAndParsesAllImages() async throws {
    let apiKey = "key-batch-multi"
    let session = makeSession()
    let client = GeminiAPIClient()
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
            #expect(requests.count == 3)

            let createJSON: [String: Any] = [
                "name": "batches/batch-multi",
                "done": false,
                "metadata": ["state": "BATCH_STATE_PENDING"]
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
            let done = statusRequests > 1
            let state = done ? "BATCH_STATE_SUCCEEDED" : "BATCH_STATE_RUNNING"
            let responses: [[String: Any]] = [
                [
                    "response": [
                        "candidates": [[
                            "content": [
                                "parts": [["inlineData": ["mimeType": "image/png", "data": "YWJj"]]]
                            ]
                        ]]
                    ]
                ],
                [
                    "response": [
                        "candidates": [[
                            "content": [
                                "parts": [["inlineData": ["mimeType": "image/png", "data": "ZGVm"]]]
                            ]
                        ]]
                    ]
                ],
                [
                    "response": [
                        "candidates": [[
                            "content": [
                                "parts": [["inlineData": ["mimeType": "image/png", "data": "Z2hp"]]]
                            ]
                        ]]
                    ]
                ]
            ]

            let statusJSON: [String: Any] = [
                "name": "batches/batch-multi",
                "done": done,
                "metadata": ["state": state],
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

    let request = GenerationRequest(
        mode: .generate,
        prompt: "test batch",
        model: AppConfig.defaultModel,
        apiKey: apiKey,
        resolution: .k1,
        aspectRatio: .square,
        inputImages: [],
        imageCount: 3
    )

    let result = try await client.generateImagesBatch(
        request: request,
        timeoutSec: 30,
        session: session,
        route: .proxy
    )

    #expect(result.images.count == 3)
    #expect(result.imageDatas == [Data("abc".utf8), Data("def".utf8), Data("ghi".utf8)])

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

@Test
func generateTextFromImagesSendsInlineDataThenTextPrompt() async throws {
    let apiKey = "key-text-image-payload"
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
        #expect(parts[2]["text"] as? String == "Describe this image")

        let json: [String: Any] = [
            "candidates": [[
                "content": [
                    "parts": [["text": "Detailed prompt result"]]
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

    let output = try await client.generateTextFromImages(
        prompt: "Describe this image",
        model: "gemini-3-flash-preview",
        apiKey: apiKey,
        images: [
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
        ],
        timeoutSec: 30,
        session: session,
        route: .proxy
    )

    #expect(output == "Detailed prompt result")
    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateTextFromImagesThrowsWhenResponseHasNoTextPart() async throws {
    let apiKey = "key-text-image-no-text"
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
        _ = try await client.generateTextFromImages(
            prompt: "Describe this image",
            model: "gemini-3-flash-preview",
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
        Issue.record("Expected noTextInResponse error")
    } catch let error as AppError {
        #expect(error == .noTextInResponse)
    }

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func generateTextFromImagesMapsUnsupportedImageModalityToPromptModelError() async throws {
    let apiKey = "key-text-image-unsupported"
    let session = makeSession()
    let client = GeminiAPIClient()

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

    do {
        _ = try await client.generateTextFromImages(
            prompt: "Describe this image",
            model: "gemini-3-flash-preview",
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
