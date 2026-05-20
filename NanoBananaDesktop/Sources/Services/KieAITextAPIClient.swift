import Foundation

actor KieAITextAPIClient {
    private struct UploadResponse: Decodable {
        let code: Int?
        let msg: String?
        let data: UploadData?
    }

    private struct UploadData: Decodable {
        let downloadUrl: String?
    }

    private let apiBaseURL: URL
    private let uploadBaseURL: URL

    init(
        apiBaseURL: URL = URL(string: "https://api.kie.ai")!,
        uploadBaseURL: URL = URL(string: "https://kieai.redpandaai.co")!
    ) {
        self.apiBaseURL = apiBaseURL
        self.uploadBaseURL = uploadBaseURL
    }

    func generateText(
        prompt: String,
        model: String,
        apiKey: String,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> String {
        let spec = try modelSpec(for: model)
        let payload = try payloadData(spec: spec, prompt: prompt, imageURLs: [])
        let data = try await executeRequest(
            endpoint: endpointURL(spec.endpointPath),
            method: "POST",
            apiKey: apiKey,
            body: payload,
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
        let spec = try modelSpec(for: model)
        guard spec.supportsImageInput else {
            throw AppError.promptFromImageModelNotSupported(model)
        }

        let imageURLs = try await uploadInputImages(
            images,
            apiKey: apiKey,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )
        let payload = try payloadData(spec: spec, prompt: prompt, imageURLs: imageURLs)
        let data = try await executeRequest(
            endpoint: endpointURL(spec.endpointPath),
            method: "POST",
            apiKey: apiKey,
            body: payload,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )
        return try extractOutputText(from: data)
    }

    private func modelSpec(for model: String) throws -> KieTextModelSpec {
        guard let spec = KieTextModelRegistry.spec(for: model) else {
            throw AppError.invalidConfiguration("Unsupported Kie text model: \(model)")
        }
        return spec
    }

    private func payloadData(spec: KieTextModelSpec, prompt: String, imageURLs: [String]) throws -> Data {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw AppError.emptyPrompt
        }

        let payload: [String: Any]
        switch spec.wireFormat {
        case .chatCompletions:
            payload = [
                "model": spec.model,
                "messages": [
                    [
                        "role": "user",
                        "content": chatContent(prompt: trimmedPrompt, imageURLs: imageURLs)
                    ]
                ]
            ]
        case .responses:
            payload = [
                "model": spec.model,
                "input": [
                    [
                        "role": "user",
                        "content": responsesContent(prompt: trimmedPrompt, imageURLs: imageURLs)
                    ]
                ]
            ]
        }

        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AppError.invalidConfiguration("Failed to serialize Kie text payload")
        }
    }

    private func chatContent(prompt: String, imageURLs: [String]) -> Any {
        guard !imageURLs.isEmpty else {
            return prompt
        }

        var content: [[String: Any]] = imageURLs.map { url in
            [
                "type": "image_url",
                "image_url": ["url": url]
            ]
        }
        content.append(["type": "text", "text": prompt])
        return content
    }

    private func responsesContent(prompt: String, imageURLs: [String]) -> [[String: Any]] {
        var content: [[String: Any]] = imageURLs.map { url in
            [
                "type": "input_image",
                "image_url": url
            ]
        }
        content.append(["type": "input_text", "text": prompt])
        return content
    }

    private func uploadInputImages(
        _ images: [GenerationInputImage],
        apiKey: String,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> [String] {
        var uploadedURLs: [String] = []
        for image in images {
            let endpoint = uploadBaseURL.appendingPathComponent("api/file-base64-upload")
            let payload: [String: Any] = [
                "base64Data": "data:\(image.mimeType);base64,\(image.data.base64EncodedString())",
                "uploadPath": "images/base64",
                "fileName": sanitizedFilename(image.filename)
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let responseData = try await executeRequest(
                endpoint: endpoint,
                method: "POST",
                apiKey: apiKey,
                body: data,
                timeoutSec: timeoutSec,
                session: session,
                route: route
            )
            let decoded = try JSONDecoder().decode(UploadResponse.self, from: responseData)
            guard decoded.code == 200,
                  let downloadURL = decoded.data?.downloadUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !downloadURL.isEmpty else {
                throw AppError.kieUploadFailed(decoded.msg ?? "Upload response did not include downloadUrl")
            }
            uploadedURLs.append(downloadURL)
        }
        return uploadedURLs
    }

    private func executeRequest(
        endpoint: URL,
        method: String,
        apiKey: String,
        body: Data?,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> Data {
        let sanitizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedKey.isEmpty else {
            throw AppError.missingKieAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = TimeInterval(timeoutSec)
        request.addValue("Bearer \(sanitizedKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

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

        if let outputText = object["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let choices = object["choices"] as? [[String: Any]] {
            for choice in choices {
                if let message = choice["message"] as? [String: Any],
                   let content = message["content"] {
                    if let text = textValue(from: content) {
                        return text
                    }
                }
            }
        }

        if let output = object["output"] as? [[String: Any]] {
            for item in output {
                if let content = item["content"] as? [[String: Any]] {
                    for contentItem in content {
                        if let text = textValue(from: contentItem) {
                            return text
                        }
                    }
                }
            }
        }

        throw AppError.noTextInResponse
    }

    private func textValue(from value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let dictionary = value as? [String: Any] {
            if let text = dictionary["text"] {
                return textValue(from: text)
            }
            if let value = dictionary["value"] {
                return textValue(from: value)
            }
        }

        if let array = value as? [[String: Any]] {
            let parts = array.compactMap { textValue(from: $0) }
            let joined = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
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
        case 400:
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
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
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
            return .network(error.localizedDescription)
        }
    }

    private func sanitizedFilename(_ filename: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let sanitized = filename.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return result.isEmpty ? "image.png" : result
    }
}
