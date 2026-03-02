import Foundation

actor GeminiModelCatalogClient {
    private struct ModelsEnvelope: Decodable {
        let models: [APIModel]?
        let error: APIError?
    }

    private struct APIModel: Decodable {
        let name: String?
        let displayName: String?
        let description: String?
        let supportedGenerationMethods: [String]?
    }

    private struct APIError: Decodable {
        let code: Int?
        let message: String?
        let status: String?
    }

    private struct ErrorEnvelope: Decodable {
        let error: APIError
    }

    private let baseURL: URL

    init(baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!) {
        self.baseURL = baseURL
    }

    func fetchModels(
        apiKey: String,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> [ModelCatalogItem] {
        let sanitizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedKey.isEmpty else {
            throw AppError.missingAPIKey
        }

        let endpoint = try endpointURL(apiKey: sanitizedKey)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(timeoutSec)
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
                : AppError.modelCatalogUnavailable(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapHTTPError(statusCode: httpResponse.statusCode, data: data, route: route)
        }

        let decoded: ModelsEnvelope
        do {
            decoded = try JSONDecoder().decode(ModelsEnvelope.self, from: data)
        } catch {
            throw AppError.modelCatalogUnavailable("Failed to decode model catalog")
        }

        if let apiError = decoded.error {
            throw mapAPIError(statusCode: apiError.code ?? 0, message: apiError.message, route: route)
        }

        let mapped: [ModelCatalogItem] = (decoded.models ?? []).compactMap { model -> ModelCatalogItem? in
            guard let rawName = model.name?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else {
                return nil
            }

            return ModelCatalogItem(
                name: rawName.replacingOccurrences(of: "models/", with: ""),
                displayName: model.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                description: model.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                supportedMethods: model.supportedGenerationMethods ?? [],
                isCustomFallback: false
            )
        }

        return mapped
    }

    static func filterImageReadyModels(from models: [ModelCatalogItem]) -> [ModelCatalogItem] {
        let markers = ["image", "nano banana", "image generation"]

        return models.filter { item in
            let methods = Set(item.supportedMethods.map { $0.lowercased() })
            guard methods.contains("generatecontent") else {
                return false
            }

            let searchable = "\(item.name) \(item.displayName) \(item.description)".lowercased()
            return markers.contains(where: { searchable.contains($0) })
        }
    }

    static func filterTextReadyModels(from models: [ModelCatalogItem]) -> [ModelCatalogItem] {
        models.filter { item in
            let methods = Set(item.supportedMethods.map { $0.lowercased() })
            return methods.contains("generatecontent")
        }
    }

    private func endpointURL(apiKey: String) throws -> URL {
        let endpoint = baseURL.appendingPathComponent("v1beta/models")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw AppError.invalidConfiguration("Cannot create URL components")
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let finalURL = components.url else {
            throw AppError.invalidConfiguration("Cannot build model catalog endpoint")
        }

        return finalURL
    }

    private func mapHTTPError(statusCode: Int, data: Data, route: NetworkRoute) -> AppError {
        let message = extractMessage(from: data)
        return mapAPIError(statusCode: statusCode, message: message, route: route)
    }

    private func mapAPIError(statusCode: Int, message: String?, route: NetworkRoute) -> AppError {
        let normalizedMessage = (message ?? "").lowercased()

        switch statusCode {
        case 400:
            return .modelCatalogUnavailable(message ?? "Bad request")
        case 401:
            return .unauthorized
        case 403:
            if normalizedMessage.contains("location is not supported")
                || normalizedMessage.contains("user location is not supported")
                || normalizedMessage.contains("country is not supported") {
                return .modelCatalogUnavailable(message ?? "User location is not supported for API use")
            }
            if normalizedMessage.contains("quota") || normalizedMessage.contains("exceeded") {
                return .quotaExceeded
            }
            return .permissionDenied
        case 407:
            return .proxyAuthFailed(message ?? "Proxy authentication failed")
        case 429:
            return .rateLimited
        case 500...599:
            return .serverError(statusCode)
        default:
            if route == .proxy {
                return .proxyConnectionFailed(message ?? "HTTP \(statusCode)")
            }
            return .modelCatalogUnavailable(message ?? "HTTP \(statusCode)")
        }
    }

    private func extractMessage(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return envelope.error.message
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String {
            return message
        }

        return String(data: data, encoding: .utf8)
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
            return .modelCatalogUnavailable(error.localizedDescription)
        }
    }
}
