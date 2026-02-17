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
    private let batchPollIntervalNanos: UInt64 = 1_500_000_000

    init(baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!) {
        self.baseURL = baseURL
    }

    // Legacy direct generateContent path (kept for compatibility and tests)
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

    // Batch API path for multi-image generation
    func generateImagesBatch(
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

        let imageCount = min(max(request.imageCount, 1), 4)
        let operationTimeoutSec = effectiveBatchOperationTimeoutSec(
            baseTimeoutSec: timeoutSec,
            imageCount: imageCount
        )
        let endpoint = try batchEndpointURL(model: sanitizedModel, apiKey: apiKey)
        let payload = try batchPayloadData(
            prompt: prompt,
            resolution: request.resolution,
            aspectRatio: request.aspectRatio,
            inputImages: request.inputImages,
            imageCount: imageCount
        )

        var attempts = 0
        while true {
            do {
                return try await executeBatchGeneration(
                    endpoint: endpoint,
                    payload: payload,
                    apiKey: apiKey,
                    resolution: request.resolution,
                    timeoutSec: timeoutSec,
                    operationTimeoutSec: operationTimeoutSec,
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

    func generateTextFromImages(
        prompt: String,
        model: String,
        apiKey: String,
        images: [GenerationInputImage],
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

        guard !images.isEmpty else {
            throw AppError.promptFromImageNoValidFile
        }

        let endpoint = try endpointURL(model: sanitizedModel, apiKey: trimmedAPIKey)
        let payload = try textFromImagesPayloadData(prompt: trimmedPrompt, images: images)
        return try await executeTextFromImagesWithRetry(
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

    private func batchEndpointURL(model: String, apiKey: String) throws -> URL {
        let normalizedModel: String
        if model.lowercased().hasPrefix("models/") {
            normalizedModel = model
        } else {
            normalizedModel = "models/\(model)"
        }

        let endpointPath = "v1beta/\(normalizedModel):batchGenerateContent"
        let endpoint = baseURL.appendingPathComponent(endpointPath)

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw AppError.invalidConfiguration("Cannot create batch URL components")
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let finalURL = components.url else {
            throw AppError.invalidConfiguration("Cannot generate batch endpoint URL")
        }

        return finalURL
    }

    private func batchStatusURL(batchName: String, apiKey: String) throws -> URL {
        let trimmedName = batchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AppError.invalidConfiguration("Batch operation name is empty")
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/v1beta/\(trimmedName)"
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let finalURL = components?.url else {
            throw AppError.invalidConfiguration("Cannot generate batch status URL")
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
        let contents = buildContents(prompt: prompt, inputImages: inputImages)
        let config = buildImageGenerationConfig(resolution: resolution, aspectRatio: aspectRatio)

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

    private func textFromImagesPayloadData(prompt: String, images: [GenerationInputImage]) throws -> Data {
        var parts: [[String: Any]] = []
        for image in images {
            parts.append([
                "inlineData": [
                    "mimeType": image.mimeType,
                    "data": image.data.base64EncodedString()
                ]
            ])
        }
        parts.append(["text": prompt])

        let payload: [String: Any] = [
            "contents": [
                ["parts": parts]
            ]
        ]

        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AppError.invalidConfiguration("Failed to build payload: \(error.localizedDescription)")
        }
    }

    private func batchPayloadData(
        prompt: String,
        resolution: ImageResolution,
        aspectRatio: ImageAspectRatio?,
        inputImages: [GenerationInputImage],
        imageCount: Int
    ) throws -> Data {
        let boundedImageCount = min(max(imageCount, 1), 4)
        let generationRequest = buildGenerationRequestObject(
            prompt: prompt,
            resolution: resolution,
            aspectRatio: aspectRatio,
            inputImages: inputImages
        )

        let inlinedRequests: [[String: Any]] = (0..<boundedImageCount).map { index in
            [
                "request": generationRequest,
                "metadata": ["key": "request-\(index + 1)"]
            ]
        }

        let payload: [String: Any] = [
            "batch": [
                "displayName": "nanobanana-desktop-batch",
                "inputConfig": [
                    "requests": [
                        "requests": inlinedRequests
                    ]
                ]
            ]
        ]

        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AppError.invalidConfiguration("Failed to build batch payload: \(error.localizedDescription)")
        }
    }

    private func buildGenerationRequestObject(
        prompt: String,
        resolution: ImageResolution,
        aspectRatio: ImageAspectRatio?,
        inputImages: [GenerationInputImage]
    ) -> [String: Any] {
        [
            "contents": buildContents(prompt: prompt, inputImages: inputImages),
            "generationConfig": buildImageGenerationConfig(resolution: resolution, aspectRatio: aspectRatio)
        ]
    }

    private func buildContents(prompt: String, inputImages: [GenerationInputImage]) -> [[String: Any]] {
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
        return [["parts": parts]]
    }

    private func buildImageGenerationConfig(
        resolution: ImageResolution,
        aspectRatio: ImageAspectRatio?
    ) -> [String: Any] {
        var imageConfig: [String: Any] = ["imageSize": resolution.rawValue]
        if let aspectRatio {
            imageConfig["aspectRatio"] = aspectRatio.rawValue
        }

        return [
            "responseModalities": ["TEXT", "IMAGE"],
            "imageConfig": imageConfig
        ]
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

    private func executeTextFromImagesWithRetry(
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
        let data = try await executeRequest(
            endpoint: endpoint,
            method: "POST",
            payload: payload,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )

        return try parseSuccessfulResponse(data: data, resolution: resolution, route: route)
    }

    private func executeTextOnce(
        endpoint: URL,
        payload: Data,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> String {
        let data = try await executeRequest(
            endpoint: endpoint,
            method: "POST",
            payload: payload,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )

        return try parseSuccessfulTextResponse(data: data, route: route)
    }

    private func executeBatchGeneration(
        endpoint: URL,
        payload: Data,
        apiKey: String,
        resolution: ImageResolution,
        timeoutSec: Int,
        operationTimeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> GenerationResult {
        let createData = try await executeRequest(
            endpoint: endpoint,
            method: "POST",
            payload: payload,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )

        let operation = try parseJSONObject(from: createData)

        if let immediate = try parseBatchResultFromOperation(
            operation,
            resolution: resolution,
            route: route
        ) {
            return immediate
        }

        guard let operationName = operation["name"] as? String,
              !operationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidResponse
        }

        let deadline = Date().addingTimeInterval(TimeInterval(operationTimeoutSec))
        while true {
            if Date() >= deadline {
                throw AppError.timeout
            }

            try await Task.sleep(nanoseconds: batchPollIntervalNanos)

            let statusURL = try batchStatusURL(batchName: operationName, apiKey: apiKey)
            let statusData = try await executeRequest(
                endpoint: statusURL,
                method: "GET",
                payload: nil,
                timeoutSec: timeoutSec,
                session: session,
                route: route
            )

            let statusOperation = try parseJSONObject(from: statusData)
            if let result = try parseBatchResultFromOperation(
                statusOperation,
                resolution: resolution,
                route: route
            ) {
                return result
            }
        }
    }

    private func parseBatchResultFromOperation(
        _ operation: [String: Any],
        resolution: ImageResolution,
        route: NetworkRoute
    ) throws -> GenerationResult? {
        if let operationError = operation["error"] as? [String: Any] {
            throw mapStatusObject(operationError, route: route)
        }

        let state = batchState(from: operation)
        if isBatchFailureState(state) {
            if let response = operation["response"] as? [String: Any],
               let responseError = response["error"] as? [String: Any] {
                throw mapStatusObject(responseError, route: route)
            }
            throw AppError.invalidConfiguration("Batch finished with state \(state ?? "UNKNOWN")")
        }

        let done = operation["done"] as? Bool ?? false
        let shouldParseOutput = done || isBatchSuccessState(state)
        guard shouldParseOutput else {
            return nil
        }

        let inlinedResponses = extractInlinedResponses(from: operation)
        guard !inlinedResponses.isEmpty else {
            throw AppError.noImageInResponse
        }

        return try parseInlinedBatchResponses(
            inlinedResponses,
            resolution: resolution,
            route: route
        )
    }

    private func parseInlinedBatchResponses(
        _ inlinedResponses: [[String: Any]],
        resolution: ImageResolution,
        route: NetworkRoute
    ) throws -> GenerationResult {
        var allImages: [GeneratedImageResult] = []
        var firstError: AppError?

        for responseObject in inlinedResponses {
            if let errorObject = responseObject["error"] as? [String: Any] {
                if firstError == nil {
                    firstError = mapStatusObject(errorObject, route: route)
                }
                continue
            }

            guard let rawResponse = responseObject["response"] as? [String: Any] else {
                continue
            }

            let responseData: Data
            do {
                responseData = try JSONSerialization.data(withJSONObject: rawResponse)
            } catch {
                throw AppError.decodingError
            }

            let parsed = try parseSuccessfulResponse(data: responseData, resolution: resolution, route: route)
            allImages.append(contentsOf: parsed.images)
        }

        if allImages.isEmpty {
            if let firstError {
                throw firstError
            }
            throw AppError.noImageInResponse
        }

        return GenerationResult(images: allImages, usedResolution: resolution)
    }

    private func extractInlinedResponses(from object: [String: Any]) -> [[String: Any]] {
        if let list = object["inlinedResponses"] as? [[String: Any]] {
            return list
        }

        if let wrappedList = object["inlinedResponses"] as? [String: Any],
           let nested = wrappedList["inlinedResponses"] as? [[String: Any]] {
            return nested
        }

        if let response = object["response"] as? [String: Any] {
            let nested = extractInlinedResponses(from: response)
            if !nested.isEmpty {
                return nested
            }
        }

        if let output = object["output"] as? [String: Any] {
            let nested = extractInlinedResponses(from: output)
            if !nested.isEmpty {
                return nested
            }
        }

        if let dest = object["dest"] as? [String: Any] {
            let nested = extractInlinedResponses(from: dest)
            if !nested.isEmpty {
                return nested
            }
        }

        return []
    }

    private func parseJSONObject(from data: Data) throws -> [String: Any] {
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let dictionary = object as? [String: Any] else {
                throw AppError.decodingError
            }
            return dictionary
        } catch let appError as AppError {
            throw appError
        } catch {
            throw AppError.decodingError
        }
    }

    private func batchState(from operation: [String: Any]) -> String? {
        guard let metadata = operation["metadata"] as? [String: Any] else {
            return nil
        }

        if let state = metadata["state"] as? String {
            return state
        }

        if let state = metadata["batchState"] as? String {
            return state
        }

        if let state = metadata["jobState"] as? String {
            return state
        }

        return nil
    }

    private func isBatchSuccessState(_ state: String?) -> Bool {
        guard let normalized = state?.uppercased(), !normalized.isEmpty else {
            return false
        }
        return normalized.contains("SUCCEEDED") || normalized.contains("SUCCESS")
    }

    private func isBatchFailureState(_ state: String?) -> Bool {
        guard let normalized = state?.uppercased(), !normalized.isEmpty else {
            return false
        }

        return normalized.contains("FAILED") ||
            normalized.contains("CANCELLED") ||
            normalized.contains("CANCELED") ||
            normalized.contains("EXPIRED")
    }

    private func executeRequest(
        endpoint: URL,
        method: String,
        payload: Data?,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
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

        return data
    }

    private func parseSuccessfulResponse(
        data: Data,
        resolution: ImageResolution,
        route: NetworkRoute
    ) throws -> GenerationResult {
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

        var images: [GeneratedImageResult] = []

        for candidate in decoded.candidates ?? [] {
            var candidateText: [String] = []
            var candidateImages: [Data] = []

            for part in candidate.content?.parts ?? [] {
                if let text = part.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    candidateText.append(text)
                }

                if let rawBase64 = part.inlineData?.data,
                   let decodedImage = Data(base64Encoded: rawBase64, options: [.ignoreUnknownCharacters]) {
                    candidateImages.append(decodedImage)
                }
            }

            let mergedText = candidateText.isEmpty ? nil : candidateText.joined(separator: "\n")
            for imageData in candidateImages {
                images.append(GeneratedImageResult(imageData: imageData, modelText: mergedText))
            }
        }

        guard !images.isEmpty else {
            throw AppError.noImageInResponse
        }

        return GenerationResult(images: images, usedResolution: resolution)
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

    private func mapStatusObject(_ status: [String: Any], route: NetworkRoute) -> AppError {
        let code: Int
        if let intCode = status["code"] as? Int {
            code = intCode
        } else if let stringCode = status["code"] as? String, let intCode = Int(stringCode) {
            code = intCode
        } else {
            code = 0
        }

        let message = status["message"] as? String

        if code <= 0 {
            if let message, !message.isEmpty {
                return .invalidConfiguration(message)
            }
            return .invalidResponse
        }

        return mapAPIError(statusCode: code, message: message, route: route)
    }

    private func mapHTTPError(statusCode: Int, data: Data, route: NetworkRoute) -> AppError {
        let message = extractMessage(from: data)
        return mapAPIError(statusCode: statusCode, message: message, route: route)
    }

    private func mapAPIError(statusCode: Int, message: String?, route: NetworkRoute) -> AppError {
        let normalizedMessage = (message ?? "").lowercased()

        switch statusCode {
        case 400:
            if normalizedMessage.contains("image input modality is not enabled") {
                return .promptFromImageModelNotSupported(message ?? "Image input modality is not enabled")
            }
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

    private func effectiveBatchOperationTimeoutSec(baseTimeoutSec: Int, imageCount: Int) -> Int {
        let safeBase = max(baseTimeoutSec, 30)
        let boundedCount = min(max(imageCount, 1), 4)

        // Batch jobs can queue longer than direct generateContent calls.
        // Scale total wait time by image count to avoid premature timeout.
        return min(safeBase * boundedCount, 900)
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
