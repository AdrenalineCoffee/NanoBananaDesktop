import Foundation

actor KieAccountAPIClient {
    private let apiBaseURL: URL

    init(apiBaseURL: URL = URL(string: "https://api.kie.ai")!) {
        self.apiBaseURL = apiBaseURL
    }

    func fetchCreditBalance(
        apiKey: String,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> Double {
        let sanitizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedKey.isEmpty else {
            throw AppError.missingKieAPIKey
        }

        let endpoint = endpointURL("api/v1/chat/credit")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(timeoutSec)
        request.addValue("Bearer \(sanitizedKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw mapURLError(urlError, route: route)
        } catch {
            throw route == .proxy
                ? AppError.proxyConnectionFailed(error.localizedDescription)
                : AppError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapHTTPError(statusCode: httpResponse.statusCode, data: data, route: route)
        }

        return try parseBalance(from: data)
    }

    private func parseBalance(from data: Data) throws -> Double {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.decodingError
        }

        if let code = object["code"] as? Int, code != 200 {
            throw mapKieBusinessError(code: code, message: extractMessage(from: object))
        }

        if let balance = numericValue(from: object["data"]) {
            return balance
        }

        for key in ["credit", "credits", "balance", "remainingCredits", "remaining_credits"] {
            if let balance = numericValue(from: object[key]) {
                return balance
            }
        }

        throw AppError.decodingError
    }

    private func numericValue(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let dictionary = value as? [String: Any] {
            for key in ["credit", "credits", "balance", "remainingCredits", "remaining_credits"] {
                if let balance = numericValue(from: dictionary[key]) {
                    return balance
                }
            }
        }
        return nil
    }

    private func endpointURL(_ path: String) -> URL {
        path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .reduce(apiBaseURL) { partialURL, component in
                partialURL.appendingPathComponent(String(component))
            }
    }

    private func mapHTTPError(statusCode: Int, data: Data, route: NetworkRoute) -> AppError {
        let message = extractMessage(from: data)
        if let billingError = AppError.billingCreditsDepletedError(message: message) {
            return billingError
        }
        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            if let quotaError = AppError.quotaError(message: message) {
                return quotaError
            }
            return .permissionDenied
        case 407:
            return .proxyAuthFailed(message ?? "Proxy authentication failed")
        case 429:
            if let quotaError = AppError.quotaError(message: message) {
                return quotaError
            }
            return .rateLimited
        case 500...599:
            return .serverError(statusCode)
        default:
            if route == .proxy {
                return .proxyConnectionFailed(message ?? "HTTP \(statusCode)")
            }
            return .network(message ?? "HTTP \(statusCode)")
        }
    }

    private func mapKieBusinessError(code: Int?, message: String?) -> AppError {
        if let billingError = AppError.billingCreditsDepletedError(message: message) {
            return billingError
        }
        if let quotaError = AppError.quotaError(message: message) {
            return quotaError
        }
        if code == 401 {
            return .unauthorized
        }
        if code == 429 {
            return .rateLimited
        }
        return .kieTaskFailed(message ?? "Kie API returned code \(code ?? -1)")
    }

    private func extractMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return extractMessage(from: object)
        }
        return String(data: data, encoding: .utf8)
    }

    private func extractMessage(from object: [String: Any]) -> String? {
        if let msg = object["msg"] as? String {
            return msg
        }
        if let message = object["message"] as? String {
            return message
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }

    private func mapURLError(_ error: URLError, route: NetworkRoute) -> AppError {
        if route == .proxy {
            switch error.code {
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return .proxyAuthFailed(error.localizedDescription)
            default:
                return .proxyConnectionFailed(error.localizedDescription)
            }
        }
        switch error.code {
        case .timedOut:
            return .timeout
        default:
            return .network(error.localizedDescription)
        }
    }
}
