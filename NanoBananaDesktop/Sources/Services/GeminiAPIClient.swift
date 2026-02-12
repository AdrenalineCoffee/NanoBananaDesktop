import Foundation

actor GeminiAPIClient {
    private enum RequestConfigVariant: CaseIterable {
        case config
        case generationConfig
    }

    private struct ErrorEnvelope: Decodable {
        let error: ErrorPayload
    }

    private struct ErrorPayload: Decodable {
        let code: Int?
        let message: String?
        let status: String?
    }

    private struct APIResponse: Decodable {
        let candidates: [Candidate]?
        let error: ErrorPayload?
    }

    private struct Candidate: Decodable {
        let content: CandidateContent?
    }

    private struct CandidateContent: Decodable {
        let parts: [CandidatePart]?
    }

    private struct CandidatePart: Decodable {
        let text: String?
        let inlineData: InlineData?
    }

    private struct InlineData: Decodable {
        let mimeType: String?
        let data: String?
    }

    private let baseURL: URL

    init(baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!) {
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
            throw AppError.missingAPIKey
        }

        let sanitizedModel = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedModel.isEmpty else {
            throw AppError.invalidConfiguration("Model cannot be empty")
        }

        let endpoint = try endpointURL(model: sanitizedModel, apiKey: apiKey)
        let variants: [RequestConfigVariant] = [.config, .generationConfig]
        var lastError: Error?

        for variant in variants {
            do {
                return try await executeForVariant(
                    endpoint: endpoint,
                    prompt: prompt,
                    resolution: request.resolution,
                    aspectRatio: request.aspectRatio,
                    inputImages: request.inputImages,
                    variant: variant,
                    timeoutSec: timeoutSec,
                    session: session,
                    route: route
                )
            } catch let appError as AppError {
                lastError = appError
                if shouldTryPayloadFallback(from: appError, variant: variant) {
                    continue
                }
                throw appError
            } catch {
                lastError = error
                throw error
            }
        }

        if let appError = lastError as? AppError {
            throw appError
        }

        throw AppError.invalidResponse
    }

    func generateText(
        prompt: String,
        model: String,
        apiKey: String,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw AppError.emptyPrompt
        }

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw AppError.missingAPIKey
        }

        let sanitizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedModel.isEmpty else {
            throw AppError.invalidConfiguration("Model cannot be empty")
        }

        let endpoint = try endpointURL(model: sanitizedModel, apiKey: trimmedAPIKey)
        let payload = try textPayloadData(prompt: trimmedPrompt)
        return try await executeTextWithRetry(
            endpoint: endpoint,
            payload: payload,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )
    }

    private func endpointURL(model: String, apiKey: String) throws -> URL {
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let endpoint = baseURL.appendingPathComponent("v1beta/models/\(encodedModel):generateContent")

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw AppError.invalidConfiguration("Cannot create URL components")
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let finalURL = components.url else {
            throw AppError.invalidConfiguration("Cannot generate final endpoint URL")
        }

        return finalURL
    }

    private func payloadData(
        prompt: String,
        resolution: ImageResolution,
        aspectRatio: ImageAspectRatio?,
        inputImages: [GenerationInputImage],
        variant: RequestConfigVariant
    ) throws -> Data {
        var parts: [[String: Any]] = []

        for inputImage in inputImages {
            parts.append([
                "inlineData": [
                    "mimeType": inputImage.mimeType,
                    "data": inputImage.data.base64EncodedString()
                ]
            ])
        }

        parts.append(["text": prompt])

        let contents: [[String: Any]] = [["parts": parts]]
        var imageConfig: [String: Any] = ["imageSize": resolution.rawValue]
        if let aspectRatio {
            imageConfig["aspectRatio"] = aspectRatio.rawValue
        }

        let config: [String: Any] = [
            "responseModalities": ["TEXT", "IMAGE"],
            "imageConfig": imageConfig
        ]

        var payload: [String: Any] = ["contents": contents]

        switch variant {
        case .config:
            payload["config"] = config
        case .generationConfig:
            payload["generationConfig"] = config
        }

        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AppError.invalidConfiguration("Failed to build payload: \(error.localizedDescription)")
        }
    }

    private func textPayloadData(prompt: String) throws -> Data {
        let payload: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ]
        ]

        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AppError.invalidConfiguration("Failed to build payload: \(error.localizedDescription)")
        }
    }

    private func executeForVariant(
        endpoint: URL,
        prompt: String,
        resolution: ImageResolution,
        aspectRatio: ImageAspectRatio?,
        inputImages: [GenerationInputImage],
        variant: RequestConfigVariant,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> GenerationResult {
        do {
            let payload = try payloadData(
                prompt: prompt,
                resolution: resolution,
                aspectRatio: aspectRatio,
                inputImages: inputImages,
                variant: variant
            )

            return try await executeWithRetry(
                endpoint: endpoint,
                payload: payload,
                timeoutSec: timeoutSec,
                resolution: resolution,
                session: session,
                route: route
            )
        } catch let appError as AppError {
            guard let aspectRatio, shouldRetryWithoutAspectRatio(from: appError) else {
                throw appError
            }

            print("[NanoBananaDesktop] Falling back to payload without aspectRatio=\(aspectRatio.rawValue)")
            let fallbackPayload = try payloadData(
                prompt: prompt,
                resolution: resolution,
                aspectRatio: nil,
                inputImages: inputImages,
                variant: variant
            )

            return try await executeWithRetry(
                endpoint: endpoint,
                payload: fallbackPayload,
                timeoutSec: timeoutSec,
                resolution: resolution,
                session: session,
                route: route
            )
        }
    }

    private func executeWithRetry(
        endpoint: URL,
        payload: Data,
        timeoutSec: Int,
        resolution: ImageResolution,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> GenerationResult {
        var attempts = 0

        while true {
            do {
                return try await executeOnce(
                    endpoint: endpoint,
                    payload: payload,
                    timeoutSec: timeoutSec,
                    resolution: resolution,
                    session: session,
                    route: route
                )
            } catch {
                if attempts == 0, isTransient(error: error) {
                    attempts += 1
                    continue
                }
                throw error
            }
        }
    }

    private func executeTextWithRetry(
        endpoint: URL,
        payload: Data,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> String {
        var attempts = 0

        while true {
            do {
                return try await executeTextOnce(
                    endpoint: endpoint,
                    payload: payload,
                    timeoutSec: timeoutSec,
                    session: session,
                    route: route
                )
            } catch {
                if attempts == 0, isTransient(error: error) {
                    attempts += 1
                    continue
                }
                throw error
            }
        }
    }

    private func executeOnce(
        endpoint: URL,
        payload: Data,
        timeoutSec: Int,
        resolution: ImageResolution,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> GenerationResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(timeoutSec)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
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

        return try parseSuccessfulResponse(data: data, resolution: resolution)
    }

    private func executeTextOnce(
        endpoint: URL,
        payload: Data,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(timeoutSec)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
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

        return try parseSuccessfulTextResponse(data: data, route: route)
    }

    private func parseSuccessfulResponse(data: Data, resolution: ImageResolution) throws -> GenerationResult {
        let decoder = JSONDecoder()

        let decoded: APIResponse
        do {
            decoded = try decoder.decode(APIResponse.self, from: data)
        } catch {
            throw AppError.decodingError
        }

        if let errorPayload = decoded.error {
            throw mapAPIError(statusCode: errorPayload.code ?? 0, message: errorPayload.message, route: .proxy)
        }

        var firstImage: Data?
        var textFragments: [String] = []

        for candidate in decoded.candidates ?? [] {
            for part in candidate.content?.parts ?? [] {
                if let text = part.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    textFragments.append(text)
                }

                if firstImage == nil,
                   let rawBase64 = part.inlineData?.data,
                   let decodedImage = Data(base64Encoded: rawBase64, options: [.ignoreUnknownCharacters]) {
                    firstImage = decodedImage
                }
            }
        }

        guard let imageData = firstImage else {
            throw AppError.noImageInResponse
        }

        return GenerationResult(
            imageData: imageData,
            modelText: textFragments.isEmpty ? nil : textFragments.joined(separator: "\n"),
            usedResolution: resolution
        )
    }

    private func parseSuccessfulTextResponse(data: Data, route: NetworkRoute) throws -> String {
        let decoder = JSONDecoder()

        let decoded: APIResponse
        do {
            decoded = try decoder.decode(APIResponse.self, from: data)
        } catch {
            throw AppError.decodingError
        }

        if let errorPayload = decoded.error {
            throw mapAPIError(statusCode: errorPayload.code ?? 0, message: errorPayload.message, route: route)
        }

        for candidate in decoded.candidates ?? [] {
            for part in candidate.content?.parts ?? [] {
                if let text = part.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    return text
                }
            }
        }

        throw AppError.noTextInResponse
    }

    private func mapHTTPError(statusCode: Int, data: Data, route: NetworkRoute) -> AppError {
        let message = extractMessage(from: data)
        return mapAPIError(statusCode: statusCode, message: message, route: route)
    }

    private func mapAPIError(statusCode: Int, message: String?, route: NetworkRoute) -> AppError {
        let normalizedMessage = (message ?? "").lowercased()

        switch statusCode {
        case 400:
            return AppError.invalidConfiguration(message ?? "Bad request")
        case 401:
            return .unauthorized
        case 403:
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
            if statusCode == 0 {
                return .invalidResponse
            }

            if route == .proxy {
                return .proxyConnectionFailed(message ?? "HTTP \(statusCode)")
            }

            return .network(message ?? "HTTP \(statusCode)")
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
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .network(error.localizedDescription)
        default:
            return .network(error.localizedDescription)
        }
    }

    private func isTransient(error: Error) -> Bool {
        if let appError = error as? AppError {
            switch appError {
            case .timeout, .network, .serverError, .proxyConnectionFailed:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func shouldTryPayloadFallback(from error: AppError, variant: RequestConfigVariant) -> Bool {
        guard variant == .config else {
            return false
        }

        guard case .invalidConfiguration(let message) = error else {
            return false
        }

        let normalized = message.lowercased()
        return normalized.contains("unknown name") ||
            normalized.contains("invalid json payload") ||
            normalized.contains("cannot find field")
    }

    private func shouldRetryWithoutAspectRatio(from error: AppError) -> Bool {
        guard case .invalidConfiguration(let message) = error else {
            return false
        }

        let normalized = message.lowercased()
        return normalized.contains("aspectratio") ||
            normalized.contains("aspect ratio") ||
            normalized.contains("aspect_ratio")
    }
}
