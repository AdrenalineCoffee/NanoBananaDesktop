import Foundation

actor OpenAIImageAPIClient {
    private struct ImagesResponse: Decodable {
        let data: [ImagePayload]?
        let error: ErrorPayload?
    }

    private struct ImagePayload: Decodable {
        let b64JSON: String?
        let revisedPrompt: String?
        let url: String?

        enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
            case revisedPrompt = "revised_prompt"
            case url
        }
    }

    private struct ErrorEnvelope: Decodable {
        let error: ErrorPayload
    }

    private struct ErrorPayload: Decodable {
        let code: String?
        let message: String?
        let type: String?
    }

    private struct ImageReference: Encodable {
        let imageURL: String

        enum CodingKeys: String, CodingKey {
            case imageURL = "image_url"
        }
    }

    private struct ImageGenerationPayload: Encodable {
        let model: String
        let prompt: String
        let n: Int
        let size: String
        let quality: String?
        let outputFormat: String

        enum CodingKeys: String, CodingKey {
            case model
            case prompt
            case n
            case size
            case quality
            case outputFormat = "output_format"
        }
    }

    private struct ImageEditPayload: Encodable {
        let model: String
        let prompt: String
        let images: [ImageReference]
        let n: Int
        let size: String
        let quality: String?
        let outputFormat: String

        enum CodingKeys: String, CodingKey {
            case model
            case prompt
            case images
            case n
            case size
            case quality
            case outputFormat = "output_format"
        }
    }

    private let baseURL: URL

    init(baseURL: URL = URL(string: "https://api.openai.com")!) {
        self.baseURL = baseURL
    }

    func generateImage(
        request: GenerationRequest,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> GenerationResult {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw AppError.emptyPrompt
        }

        let apiKey = request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw AppError.missingOpenAIAPIKey
        }

        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw AppError.invalidConfiguration("Model cannot be empty")
        }

        let endpoint = endpointURL(request.inputImages.isEmpty ? "v1/images/generations" : "v1/images/edits")
        let payload = try payloadData(for: request)
        let data = try await executeRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            payload: payload,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )
        return try await parseResponse(
            data: data,
            resolution: request.resolution,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )
    }

    private func payloadData(for request: GenerationRequest) throws -> Data {
        let size = sizeString(for: request.aspectRatio)
        let quality = qualityString(for: request.resolution)

        if request.inputImages.isEmpty {
            let payload = ImageGenerationPayload(
                model: request.model,
                prompt: request.prompt,
                n: min(max(request.imageCount, 1), 10),
                size: size,
                quality: quality,
                outputFormat: "png"
            )
            return try JSONEncoder().encode(payload)
        }

        let payload = ImageEditPayload(
            model: request.model,
            prompt: request.prompt,
            images: request.inputImages.map { image in
                ImageReference(imageURL: dataURLString(for: image))
            },
            n: min(max(request.imageCount, 1), 10),
            size: size,
            quality: quality,
            outputFormat: "png"
        )
        return try JSONEncoder().encode(payload)
    }

    private func executeRequest(
        endpoint: URL,
        apiKey: String,
        payload: Data,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(timeoutSec)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

    private func parseResponse(
        data: Data,
        resolution: ImageResolution,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> GenerationResult {
        let decoded: ImagesResponse
        do {
            decoded = try JSONDecoder().decode(ImagesResponse.self, from: data)
        } catch {
            throw AppError.decodingError
        }

        if let errorPayload = decoded.error {
            throw mapAPIError(statusCode: 400, message: errorPayload.message, route: route)
        }

        var images: [GeneratedImageResult] = []
        for item in decoded.data ?? [] {
            if let rawBase64 = item.b64JSON,
               let imageData = Data(base64Encoded: rawBase64, options: [.ignoreUnknownCharacters]) {
                images.append(
                    GeneratedImageResult(
                        imageData: imageData,
                        modelText: item.revisedPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            } else if let urlString = item.url,
                      let url = URL(string: urlString) {
                let imageData = try await downloadImage(
                    from: url,
                    timeoutSec: timeoutSec,
                    session: session,
                    route: route
                )
                images.append(
                    GeneratedImageResult(
                        imageData: imageData,
                        modelText: item.revisedPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            }
        }

        guard !images.isEmpty else {
            throw AppError.noImageInResponse
        }

        return GenerationResult(images: images, usedResolution: resolution)
    }

    private func downloadImage(
        from url: URL,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(timeoutSec)
        request.addValue("image/*", forHTTPHeaderField: "Accept")

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

    private func endpointURL(_ path: String) -> URL {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if baseURL.pathComponents.last?.lowercased() == "v1",
           normalizedPath.lowercased().hasPrefix("v1/") {
            return baseURL.appendingPathComponent(String(normalizedPath.dropFirst("v1/".count)))
        }
        return baseURL.appendingPathComponent(normalizedPath)
    }

    private func sizeString(for aspectRatio: ImageAspectRatio) -> String {
        let ratio = aspectRatio.numericValue
        if abs(ratio - 1) < 0.2 {
            return "1024x1024"
        }
        return ratio > 1 ? "1536x1024" : "1024x1536"
    }

    private func qualityString(for resolution: ImageResolution) -> String? {
        switch resolution {
        case .k4:
            return "high"
        case .k2:
            return "medium"
        case .k1:
            return nil
        }
    }

    private func dataURLString(for image: GenerationInputImage) -> String {
        "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
    }

    private func mapHTTPError(statusCode: Int, data: Data, route: NetworkRoute) -> AppError {
        let message = extractMessage(from: data)
        return mapAPIError(statusCode: statusCode, message: message, route: route)
    }

    private func mapAPIError(statusCode: Int, message: String?, route: NetworkRoute) -> AppError {
        if let billingError = AppError.billingCreditsDepletedError(message: message) {
            return billingError
        }
        let normalizedMessage = (message ?? "").lowercased()

        switch statusCode {
        case 400:
            if normalizedMessage.contains("unknown parameter") {
                return .invalidConfiguration(message ?? "Bad request")
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
}
