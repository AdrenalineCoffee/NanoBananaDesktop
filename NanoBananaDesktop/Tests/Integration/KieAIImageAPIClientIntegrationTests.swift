import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func kieGenerateImageUploadsInputCreatesTaskPollsAndDownloadsResult() async throws {
    let apiKey = "kie-success"
    let client = KieAIImageAPIClient()
    let session = kieMockSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let path = request.url?.path ?? ""
        switch path {
        case "/api/file-base64-upload":
            #expect(request.httpMethod == "POST")
            let payload = try kieJSONObject(from: request)
            #expect((payload["base64Data"] as? String)?.hasPrefix("data:image/png;base64,") == true)
            #expect(payload["uploadPath"] as? String == "images/base64")
            #expect(payload["fileName"] as? String == "input.png")
            return try kieJSONResponse(
                url: request.url!,
                object: [
                    "code": 200,
                    "msg": "success",
                    "data": ["downloadUrl": "https://example.com/input.png"]
                ]
            )
        case "/api/v1/jobs/createTask":
            #expect(request.httpMethod == "POST")
            let payload = try kieJSONObject(from: request)
            #expect(payload["model"] as? String == "nano-banana-pro")
            let input = try #require(payload["input"] as? [String: Any])
            #expect(input["prompt"] as? String == "add a bag")
            #expect(input["aspect_ratio"] as? String == "1:1")
            #expect(input["resolution"] as? String == "1K")
            #expect(input["output_format"] as? String == "png")
            #expect(input["image_input"] as? [String] == ["https://example.com/input.png"])
            return try kieJSONResponse(
                url: request.url!,
                object: [
                    "code": 200,
                    "msg": "success",
                    "data": ["taskId": "task-1"]
                ]
            )
        case "/api/v1/jobs/recordInfo":
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            #expect(components?.queryItems?.first(where: { $0.name == "taskId" })?.value == "task-1")
            let resultJson = try kieJSONString(["resultUrls": ["https://example.com/out.png?key=\(apiKey)"]])
            return try kieJSONResponse(
                url: request.url!,
                object: [
                    "code": 200,
                    "msg": "success",
                    "data": ["state": "success", "resultJson": resultJson]
                ]
            )
        case "/out.png":
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                kieTinyPNGData
            )
        default:
            throw URLError(.badURL)
        }
    }

    let request = GenerationRequest(
        mode: .edit,
        prompt: "add a bag",
        model: "nano-banana-pro",
        apiKey: apiKey,
        resolution: .k1,
        aspectRatio: .square,
        inputImages: [
            GenerationInputImage(
                fileURL: URL(fileURLWithPath: "/tmp/input.png"),
                filename: "input.png",
                mimeType: "image/png",
                data: kieTinyPNGData
            )
        ],
        imageCount: 1
    )

    let result = try await client.generateImage(
        request: request,
        timeoutSec: 5,
        session: session,
        route: .directFallback
    )

    #expect(result.images.count == 1)
    #expect(result.images[0].imageData == kieTinyPNGData)
}

@Test
func kieNanoBananaProWithoutInputSendsEmptyImageInputAndMapsCredits() async throws {
    let apiKey = "kie-pro-no-input"
    let client = KieAIImageAPIClient()
    let session = kieMockSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        switch request.url?.path {
        case "/api/v1/jobs/createTask":
            let payload = try kieJSONObject(from: request)
            #expect(payload["model"] as? String == "nano-banana-pro")
            let input = try #require(payload["input"] as? [String: Any])
            #expect(input["prompt"] as? String == "make product render")
            #expect(input["image_input"] as? [String] == [])
            #expect(input["aspect_ratio"] as? String == "16:9")
            #expect(input["resolution"] as? String == "2K")
            #expect(input["output_format"] as? String == "png")
            return try kieJSONResponse(
                url: request.url!,
                object: ["code": 200, "msg": "success", "data": ["taskId": "task-pro"]]
            )
        case "/api/v1/jobs/recordInfo":
            let resultJson = try kieJSONString(["resultUrls": ["https://example.com/out.png?key=\(apiKey)"]])
            return try kieJSONResponse(
                url: request.url!,
                object: [
                    "code": 200,
                    "msg": "success",
                    "data": ["state": "success", "resultJson": resultJson, "creditsConsumed": "123.5"]
                ]
            )
        case "/out.png":
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                kieTinyPNGData
            )
        default:
            throw URLError(.badURL)
        }
    }

    let request = GenerationRequest(
        mode: .generate,
        prompt: "make product render",
        model: "nano-banana-pro",
        apiKey: apiKey,
        resolution: .k2,
        aspectRatio: .landscape16x9,
        inputImages: [],
        imageCount: 1
    )

    let result = try await client.generateImage(
        request: request,
        timeoutSec: 5,
        session: session,
        route: .directFallback
    )

    #expect(result.images.count == 1)
    #expect(result.cost?.unit == .kieCredits)
    #expect(result.cost?.total == 123.5)
    #expect(result.images.first?.cost?.total == 123.5)
}

@Test
func kieGoogleNanoBananaUsesImageSizePayload() async throws {
    let apiKey = "kie-google-nano"
    let client = KieAIImageAPIClient()
    let session = kieMockSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        switch request.url?.path {
        case "/api/v1/jobs/createTask":
            let payload = try kieJSONObject(from: request)
            #expect(payload["model"] as? String == "google/nano-banana")
            let input = try #require(payload["input"] as? [String: Any])
            #expect(input["prompt"] as? String == "simple render")
            #expect(input["image_size"] as? String == "square_hd")
            #expect(input["output_format"] as? String == "png")
            #expect(input["aspect_ratio"] == nil)
            #expect(input["resolution"] == nil)
            #expect(input["image_input"] == nil)
            return try kieJSONResponse(
                url: request.url!,
                object: ["code": 200, "msg": "success", "data": ["taskId": "task-google"]]
            )
        case "/api/v1/jobs/recordInfo":
            let resultJson = try kieJSONString(["resultUrls": ["https://example.com/out.png?key=\(apiKey)"]])
            return try kieJSONResponse(
                url: request.url!,
                object: ["code": 200, "msg": "success", "data": ["state": "success", "resultJson": resultJson]]
            )
        case "/out.png":
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                kieTinyPNGData
            )
        default:
            throw URLError(.badURL)
        }
    }

    let request = GenerationRequest(
        mode: .generate,
        prompt: "simple render",
        model: "google/nano-banana",
        apiKey: apiKey,
        resolution: .k4,
        aspectRatio: .square,
        inputImages: [],
        imageCount: 1
    )

    let result = try await client.generateImage(
        request: request,
        timeoutSec: 5,
        session: session,
        route: .directFallback
    )

    #expect(result.images.count == 1)
}

@Test
func kieGoogleNanoBananaEditUsesImageUrlsPayload() async throws {
    let apiKey = "kie-google-nano-edit"
    let client = KieAIImageAPIClient()
    let session = kieMockSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        switch request.url?.path {
        case "/api/file-base64-upload":
            return try kieJSONResponse(
                url: request.url!,
                object: ["code": 200, "msg": "success", "data": ["downloadUrl": "https://example.com/input.png"]]
            )
        case "/api/v1/jobs/createTask":
            let payload = try kieJSONObject(from: request)
            #expect(payload["model"] as? String == "google/nano-banana-edit")
            let input = try #require(payload["input"] as? [String: Any])
            #expect(input["image_urls"] as? [String] == ["https://example.com/input.png"])
            #expect(input["image_size"] as? String == "landscape_16_9")
            #expect(input["output_format"] as? String == "png")
            #expect(input["aspect_ratio"] == nil)
            #expect(input["resolution"] == nil)
            return try kieJSONResponse(
                url: request.url!,
                object: ["code": 200, "msg": "success", "data": ["taskId": "task-edit"]]
            )
        case "/api/v1/jobs/recordInfo":
            let resultJson = try kieJSONString(["resultUrls": ["https://example.com/out.png?key=\(apiKey)"]])
            return try kieJSONResponse(
                url: request.url!,
                object: ["code": 200, "msg": "success", "data": ["state": "success", "resultJson": resultJson]]
            )
        case "/out.png":
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                kieTinyPNGData
            )
        default:
            throw URLError(.badURL)
        }
    }

    let request = GenerationRequest(
        mode: .edit,
        prompt: "edit image",
        model: "google/nano-banana-edit",
        apiKey: apiKey,
        resolution: .k1,
        aspectRatio: .landscape16x9,
        inputImages: [
            GenerationInputImage(
                fileURL: URL(fileURLWithPath: "/tmp/input.png"),
                filename: "input.png",
                mimeType: "image/png",
                data: kieTinyPNGData
            )
        ],
        imageCount: 1
    )

    let result = try await client.generateImage(
        request: request,
        timeoutSec: 5,
        session: session,
        route: .directFallback
    )

    #expect(result.images.count == 1)
}

@Test
func kieGenerateImageMapsFailedTaskToKieTaskError() async throws {
    let apiKey = "kie-failed"
    let client = KieAIImageAPIClient()
    let session = kieMockSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        switch request.url?.path {
        case "/api/file-base64-upload":
            return try kieJSONResponse(
                url: request.url!,
                object: [
                    "code": 200,
                    "msg": "success",
                    "data": ["downloadUrl": "https://example.com/input.png"]
                ]
            )
        case "/api/v1/jobs/createTask":
            return try kieJSONResponse(
                url: request.url!,
                object: [
                    "code": 200,
                    "msg": "success",
                    "data": ["taskId": "task-failed"]
                ]
            )
        case "/api/v1/jobs/recordInfo":
            return try kieJSONResponse(
                url: request.url!,
                object: [
                    "code": 200,
                    "msg": "success",
                    "data": [
                        "state": "failed",
                        "failCode": "MODEL_ERROR",
                        "failMsg": "render failed"
                    ]
                ]
            )
        default:
            throw URLError(.badURL)
        }
    }

    let request = GenerationRequest(
        mode: .edit,
        prompt: "add a bag",
        model: "nano-banana-pro",
        apiKey: apiKey,
        resolution: .k1,
        aspectRatio: .square,
        inputImages: [
            GenerationInputImage(
                fileURL: URL(fileURLWithPath: "/tmp/input.png"),
                filename: "input.png",
                mimeType: "image/png",
                data: kieTinyPNGData
            )
        ],
        imageCount: 1
    )

    do {
        _ = try await client.generateImage(
            request: request,
            timeoutSec: 5,
            session: session,
            route: .directFallback
        )
        Issue.record("Expected Kie task failure")
    } catch let error as AppError {
        #expect(error == .kieTaskFailed("MODEL_ERROR: render failed"))
    }
}

private func kieMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func kieJSONObject(from request: URLRequest) throws -> [String: Any] {
    let body = try kieRequestBodyData(from: request)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func kieRequestBodyData(from request: URLRequest) throws -> Data {
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

private func kieJSONResponse(url: URL, object: [String: Any]) throws -> (HTTPURLResponse, Data) {
    let data = try JSONSerialization.data(withJSONObject: object)
    let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
}

private func kieJSONString(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object)
    return try #require(String(data: data, encoding: .utf8))
}

private let kieTinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+2YQAAAAASUVORK5CYII="
private let kieTinyPNGData = Data(base64Encoded: kieTinyPNGBase64)!
