import Foundation

actor OpenAIModelCatalogClient {
    private struct ModelsEnvelope: Decodable {
        let data: [APIModel]?
        let error: APIError?
    }

    private struct APIModel: Decodable {
        let id: String
    }

    private struct APIError: Decodable {
        let code: String?
        let message: String?
        let type: String?
    }

    private struct ErrorEnvelope: Decodable {
        let error: APIError
    }

    private let baseURL: URL
    private let provider: ModelProvider

    init(baseURL: URL = URL(string: "https://api.openai.com")!, provider: ModelProvider = .openAI) {
        self.baseURL = baseURL
        self.provider = provider
    }

    func fetchModels(
        apiKey: String,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> [ModelCatalogItem] {
        let sanitizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedKey.isEmpty else {
            throw AppError.missingOpenAIAPIKey
        }

        let endpoint = endpointURL("v1/models")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(timeoutSec)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(sanitizedKey)", forHTTPHeaderField: "Authorization")

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
            throw AppError.modelCatalogUnavailable("Failed to decode OpenAI model catalog")
        }

        if let errorPayload = decoded.error {
            throw mapAPIError(statusCode: 400, message: errorPayload.message, route: route)
        }

        return (decoded.data ?? []).map { model in
            ModelCatalogItem(
                provider: provider,
                name: ModelProvider.encodedModelName(provider: provider, modelName: model.id),
                displayName: Self.displayName(for: model.id),
                description: "",
                supportedMethods: ["images.generate"],
                isCustomFallback: false
            )
        }
    }

    static func filterImageReadyModels(from models: [ModelCatalogItem]) -> [ModelCatalogItem] {
        models.filter { item in
            let apiModelName = ModelProvider.apiModelName(from: item.name)
            switch item.provider {
            case .openAI:
                return isOpenAIImageModelName(apiModelName)
            case .openAICompatible:
                return isOpenAICompatibleImageModelName(apiModelName)
            case .gemini:
                return false
            case .kie:
                return false
            }
        }
    }

    static func filterTextReadyModels(from models: [ModelCatalogItem]) -> [ModelCatalogItem] {
        models.filter { item in
            let apiModelName = ModelProvider.apiModelName(from: item.name)
            switch item.provider {
            case .openAI:
                return isOpenAITextModelName(apiModelName)
            case .openAICompatible:
                return isOpenAICompatibleTextModelName(apiModelName)
            case .gemini, .kie:
                return false
            }
        }
    }

    static func isOpenAIImageModelName(_ modelName: String) -> Bool {
        let normalized = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("gpt-image")
    }

    static func isOpenAICompatibleImageModelName(_ modelName: String) -> Bool {
        let normalized = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("gpt-image") || normalized.contains("image")
    }

    static func isTextModelName(_ modelName: String) -> Bool {
        isOpenAITextModelName(modelName)
    }

    static func isOpenAITextModelName(_ modelName: String) -> Bool {
        let normalized = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.hasPrefix("gpt-"),
              !normalized.hasPrefix("gpt-image-") else {
            return false
        }

        let snapshotPattern = #".*-\d{4}-\d{2}-\d{2}$"#
        return normalized.range(of: snapshotPattern, options: .regularExpression) == nil
    }

    static func isOpenAICompatibleTextModelName(_ modelName: String) -> Bool {
        let normalized = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !isNonTextModelName(normalized) else {
            return false
        }

        let snapshotPattern = #".*-\d{4}-\d{2}-\d{2}$"#
        guard normalized.range(of: snapshotPattern, options: .regularExpression) == nil else {
            return false
        }

        let allowedPrefixes = [
            "gpt-",
            "o1",
            "o2",
            "o3",
            "o4",
            "o5",
            "gemini-",
            "claude-",
            "qwen",
            "deepseek",
            "grok",
            "llama",
            "mistral"
        ]
        return allowedPrefixes.contains { normalized.hasPrefix($0) }
    }

    private static func isNonTextModelName(_ normalized: String) -> Bool {
        let blockedFragments = [
            "gpt-image",
            "image",
            "imagen",
            "dall-e",
            "video",
            "audio",
            "speech",
            "tts",
            "transcrib",
            "whisper",
            "embedding",
            "embed",
            "upscale",
            "background",
            "remove-bg",
            "remove_background",
            "moderation",
            "rerank"
        ]
        return blockedFragments.contains { normalized.contains($0) }
    }

    static func displayName(for modelName: String) -> String {
        let apiModelName = ModelProvider.apiModelName(from: modelName)
        switch apiModelName.lowercased() {
        case "gpt-image-2":
            return "GPT Image 2"
        case "gpt-image-1.5":
            return "GPT Image 1.5"
        case "gpt-image-1-mini":
            return "GPT Image 1 Mini"
        case "gpt-image-1":
            return "GPT Image 1"
        case "chatgpt-image-latest":
            return "ChatGPT Image Latest"
        case "dall-e-3":
            return "DALL·E 3"
        case "dall-e-2":
            return "DALL·E 2"
        default:
            return apiModelName
                .split(separator: "-")
                .map { segment in
                    let value = String(segment)
                    return value.uppercased() == "GPT" ? "GPT" : value.capitalized
                }
                .joined(separator: " ")
        }
    }

    private func endpointURL(_ path: String) -> URL {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if baseURL.pathComponents.last?.lowercased() == "v1",
           normalizedPath.lowercased().hasPrefix("v1/") {
            return baseURL.appendingPathComponent(String(normalizedPath.dropFirst("v1/".count)))
        }
        return baseURL.appendingPathComponent(normalizedPath)
    }

    private func mapHTTPError(statusCode: Int, data: Data, route: NetworkRoute) -> AppError {
        let message = extractMessage(from: data)
        return mapAPIError(statusCode: statusCode, message: message, route: route)
    }

    private func mapAPIError(statusCode: Int, message: String?, route: NetworkRoute) -> AppError {
        if let billingError = AppError.billingCreditsDepletedError(message: message) {
            return billingError
        }

        switch statusCode {
        case 400:
            return .modelCatalogUnavailable(message ?? "Bad request")
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
            return .modelCatalogUnavailable(message ?? "HTTP \(statusCode)")
        }
    }

    private func extractMessage(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return errorDescription(
                message: envelope.error.message,
                type: envelope.error.type,
                code: envelope.error.code
            )
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        return String(data: data, encoding: .utf8)
    }

    private func errorDescription(message: String?, type: String?, code: String?) -> String? {
        let parts = [type, code, message]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ": ")
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
