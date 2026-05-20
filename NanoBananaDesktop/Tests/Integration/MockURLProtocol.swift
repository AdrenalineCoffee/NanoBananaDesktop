import Foundation

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var handlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    nonisolated(unsafe) private static let lock = NSLock()

    static func setHandler(forAPIKey apiKey: String, handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        defer { lock.unlock() }
        handlers[apiKey] = handler
    }

    static func removeHandler(forAPIKey apiKey: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: apiKey)
    }

    static func removeAllHandlers() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let key = Self.apiKey(from: request)

        guard let key else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.lock.lock()
        let handler = Self.handlers[key]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func apiKey(from request: URLRequest) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return authorizationKey(from: request)
        }

        if let queryKey = components.queryItems?.first(where: { $0.name == "key" })?.value {
            return queryKey
        }

        return authorizationKey(from: request)
    }

    private static func authorizationKey(from request: URLRequest) -> String? {
        guard let authorization = request.value(forHTTPHeaderField: "Authorization"),
              authorization.lowercased().hasPrefix("bearer ") else {
            return nil
        }

        return String(authorization.dropFirst("Bearer ".count))
    }
}
