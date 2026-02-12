import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func fetchModelsParsesValidCatalogResponse() async throws {
    let apiKey = "key-catalog-success"
    let session = makeSession()
    let client = GeminiModelCatalogClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.httpMethod == "GET")

        let json: [String: Any] = [
            "models": [
                [
                    "name": "models/gemini-3-pro-image-preview",
                    "displayName": "Nano Banana Pro",
                    "description": "Gemini 3 Pro Image Preview",
                    "supportedGenerationMethods": ["generateContent", "countTokens"]
                ],
                [
                    "name": "models/imagen-4.0-ultra-generate-001",
                    "displayName": "Imagen 4 Ultra",
                    "description": "Vertex served Imagen 4.0 ultra model",
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

    let result = try await client.fetchModels(
        apiKey: apiKey,
        timeoutSec: 30,
        session: session,
        route: .proxy
    )

    #expect(result.count == 2)
    #expect(result[0].name == "gemini-3-pro-image-preview")
    #expect(result[1].name == "imagen-4.0-ultra-generate-001")

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func fetchModelsMapsQuotaError() async throws {
    let apiKey = "key-catalog-quota"
    let session = makeSession()
    let client = GeminiModelCatalogClient()

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

    do {
        _ = try await client.fetchModels(
            apiKey: apiKey,
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
func fetchModelsMapsServerError() async throws {
    let apiKey = "key-catalog-server"
    let session = makeSession()
    let client = GeminiModelCatalogClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let json: [String: Any] = [
            "error": [
                "code": 500,
                "message": "Internal error"
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseData)
    }

    do {
        _ = try await client.fetchModels(
            apiKey: apiKey,
            timeoutSec: 30,
            session: session,
            route: .proxy
        )
        Issue.record("Expected server error")
    } catch let error as AppError {
        #expect(error == .serverError(500))
    }

    MockURLProtocol.removeHandler(forAPIKey: apiKey)
}

@Test
func fetchModelsMapsProxyConnectionFailureForProxyRoute() async throws {
    let apiKey = "key-catalog-proxy-fail"
    let session = makeSession()
    let client = GeminiModelCatalogClient()

    MockURLProtocol.setHandler(forAPIKey: apiKey) { _ in
        throw URLError(.cannotConnectToHost)
    }

    do {
        _ = try await client.fetchModels(
            apiKey: apiKey,
            timeoutSec: 30,
            session: session,
            route: .proxy
        )
        Issue.record("Expected proxy connection failure")
    } catch let error as AppError {
        guard case .proxyConnectionFailed = error else {
            Issue.record("Expected proxy connection failure")
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
