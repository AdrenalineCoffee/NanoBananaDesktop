import Foundation

actor OpenAITextAPIClient {
    private struct ErrorEnvelope: Decodable {
        let error: ErrorPayload
    }

    private struct ErrorPayload: Decodable {
        let code: String?
        let message: String?
        let type: String?
    }

    private let baseURL: URL

    init(baseURL: URL = URL(string: "https://api.openai.com")!) {
        self.baseURL = baseURL
    }

    func generateText(
        prompt: String,
        model: String,
        apiKey: String,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> String {
        let payload = try buildTextPayload(prompt: prompt, model: model)
        let data = try await executeResponsesRequest(
            payload: payload,
            apiKey: apiKey,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )
        return try extractOutputText(from: data)
    }

    func generateTextFromImages(
        prompt: String,
        model: String,
        apiKey: String,
        images: [GenerationInputImage],
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> String {
        let payload = try buildTextFromImagesPayload(
            prompt: prompt,
            model: model,
            images: images
        )
        let data = try await executeResponsesRequest(
            payload: payload,
            apiKey: apiKey,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )
        return try extractOutputText(from: data)
    }

    private func buildTextPayload(prompt: String, model: String) throws -> Data {
        let payload: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AppError.invalidConfiguration("Failed to serialize OpenAI text payload")
        }
    }

    private func buildTextFromImagesPayload(
        prompt: String,
        model: String,
        images: [GenerationInputImage]
    ) throws -> Data {
        var content: [[String: Any]] = images.map { image in
            [
                "type": "input_image",
                "image_url": dataURLString(for: image)
            ]
        }
        content.append([
            "type": "input_text",
            "text": prompt
        ])

        let payload: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]

        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AppError.invalidConfiguration("Failed to serialize OpenAI multimodal text payload")
        }
    }

    private func executeResponsesRequest(
        payload: Data,
        apiKey: String,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> Data {
        let sanitizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedKey.isEmpty else {
            throw AppError.missingOpenAIAPIKey
        }

        let endpoint = endpointURL("v1/responses")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(timeoutSec)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(sanitizedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = payload

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

        return data
    }

    private func extractOutputText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.decodingError
        }

        if let outputText = object["output_text"] as? String {
            let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let output = object["output"] as? [[String: Any]] {
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else {
                    continue
                }

                for contentItem in content {
                    if let text = textValue(from: contentItem) {
                        return text
                    }
                }
            }
        }

        throw AppError.noTextInResponse
    }

    private func textValue(from contentItem: [String: Any]) -> String? {
        if let text = contentItem["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let textObject = contentItem["text"] as? [String: Any],
           let value = textObject["value"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private func mapHTTPError(statusCode: Int, data: Data, route: NetworkRoute) -> AppError {
        let message = extractMessage(from: data)
        if let billingError = AppError.billingCreditsDepletedError(message: message) {
            return billingError
        }
        let normalizedMessage = (message ?? "").lowercased()

        switch statusCode {
        case 400:
            if normalizedMessage.contains("input_image")
                || normalizedMessage.contains("image input")
                || normalizedMessage.contains("image modality")
                || normalizedMessage.contains("image")
                    && (normalizedMessage.contains("not supported")
                        || normalizedMessage.contains("not enabled")
                        || normalizedMessage.contains("unsupported")) {
                return .promptFromImageModelNotSupported(message ?? "")
            }
            return .invalidConfiguration(message ?? "Bad request")
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

    private func endpointURL(_ path: String) -> URL {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if baseURL.pathComponents.last?.lowercased() == "v1",
           normalizedPath.lowercased().hasPrefix("v1/") {
            return baseURL.appendingPathComponent(String(normalizedPath.dropFirst("v1/".count)))
        }
        return baseURL.appendingPathComponent(normalizedPath)
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
            return .timeoutWithDetails("route=\(route.rawValue), url_error=\(error.code.rawValue), message=\(error.localizedDescription)")
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .network(error.localizedDescription)
        default:
            return .network(error.localizedDescription)
        }
    }

    private func dataURLString(for image: GenerationInputImage) -> String {
        "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
    }
}
