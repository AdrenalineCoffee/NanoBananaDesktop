import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func kieAccountClientParsesNumericCreditBalance() async throws {
    let apiKey = "kie-credit-number"
    let client = KieAccountAPIClient()
    let session = makeKieAccountSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        #expect(request.url?.path == "/api/v1/chat/credit")
        #expect(request.httpMethod == "GET")
        let data = try JSONSerialization.data(withJSONObject: ["code": 200, "data": 100])
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            data
        )
    }

    let balance = try await client.fetchCreditBalance(
        apiKey: apiKey,
        timeoutSec: 5,
        session: session,
        route: .directFallback
    )

    #expect(balance == 100)
}

@Test
func kieAccountClientParsesNestedCreditBalance() async throws {
    let apiKey = "kie-credit-nested"
    let client = KieAccountAPIClient()
    let session = makeKieAccountSession()
    defer { MockURLProtocol.removeHandler(forAPIKey: apiKey) }

    MockURLProtocol.setHandler(forAPIKey: apiKey) { request in
        let data = try JSONSerialization.data(withJSONObject: [
            "code": 200,
            "data": ["credits": "42.5"]
        ])
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            data
        )
    }

    let balance = try await client.fetchCreditBalance(
        apiKey: apiKey,
        timeoutSec: 5,
        session: session,
        route: .directFallback
    )

    #expect(balance == 42.5)
}

private func makeKieAccountSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}
