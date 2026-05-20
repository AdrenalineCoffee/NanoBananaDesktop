import Foundation

actor KieAIImageAPIClient {
    private struct UploadResponse: Decodable {
        let code: Int?
        let msg: String?
        let data: UploadData?
    }

    private struct UploadData: Decodable {
        let downloadUrl: String?
    }

    private struct TaskCreateResponse: Decodable {
        let code: Int?
        let msg: String?
        let data: TaskCreateData?
    }

    private struct TaskCreateData: Decodable {
        let taskId: String?
    }

    private struct TaskRecordResponse: Decodable {
        let code: Int?
        let msg: String?
        let data: TaskRecord?
    }

    private struct TaskRecord: Decodable {
        let state: String?
        let resultJson: String?
        let failCode: String?
        let failMsg: String?
        let progress: Int?
        let creditsConsumed: Double?

        enum CodingKeys: String, CodingKey {
            case state
            case resultJson
            case failCode
            case failMsg
            case progress
            case creditsConsumed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            state = try container.decodeIfPresent(String.self, forKey: .state)
            resultJson = try container.decodeIfPresent(String.self, forKey: .resultJson)
            failCode = try container.decodeIfPresent(String.self, forKey: .failCode)
            failMsg = try container.decodeIfPresent(String.self, forKey: .failMsg)
            progress = try container.decodeIfPresent(Int.self, forKey: .progress)
            if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: .creditsConsumed) {
                creditsConsumed = doubleValue
            } else if let stringValue = try? container.decodeIfPresent(String.self, forKey: .creditsConsumed) {
                creditsConsumed = Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                creditsConsumed = nil
            }
        }
    }

    private struct TaskResult: Sendable {
        let urls: [URL]
        let creditsConsumed: Double?
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

    func generateImage(
        request: GenerationRequest,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> GenerationResult {
        let apiKey = request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw AppError.missingKieAPIKey
        }

        guard let spec = KieModelRegistry.spec(for: request.model) else {
            throw AppError.invalidConfiguration("Unsupported Kie model: \(request.model)")
        }

        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if spec.kind.requiresPrompt && prompt.isEmpty {
            throw AppError.emptyPrompt
        }

        if spec.requiresInputImage && request.inputImages.isEmpty {
            throw AppError.missingInputImage
        }

        if spec.inputField == .none && !request.inputImages.isEmpty {
            throw AppError.invalidConfiguration("Selected Kie model does not support input images")
        }

        let uploadedImageURLs = try await uploadInputImages(
            request.inputImages,
            apiKey: apiKey,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )

        let taskID = try await createTask(
            spec: spec,
            request: request,
            prompt: prompt,
            uploadedImageURLs: uploadedImageURLs,
            apiKey: apiKey,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )

        let taskResult = try await pollTaskResult(
            taskID: taskID,
            apiKey: apiKey,
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )

        var images: [GeneratedImageResult] = []
        let perImageCost: GenerationCostEstimate?
        if let credits = taskResult.creditsConsumed,
           !taskResult.urls.isEmpty {
            perImageCost = GenerationCostRegistry.actualKieCredits(
                model: request.model,
                resolution: request.resolution,
                imageCount: taskResult.urls.count,
                totalCredits: credits
            )
        } else {
            perImageCost = nil
        }

        for url in taskResult.urls {
            let data = try await downloadImage(from: url, timeoutSec: timeoutSec, session: session, route: route)
            let imageCost = perImageCost.map {
                GenerationCostEstimate(
                    provider: $0.provider,
                    model: $0.model,
                    resolution: $0.resolution,
                    imageCount: 1,
                    unit: $0.unit,
                    perImage: $0.perImage,
                    total: $0.perImage,
                    confidence: $0.confidence,
                    note: $0.note
                )
            }
            images.append(GeneratedImageResult(imageData: data, modelText: nil, cost: imageCost))
        }

        guard !images.isEmpty else {
            throw AppError.noImageInResponse
        }
        let totalCost = taskResult.creditsConsumed.map {
            GenerationCostRegistry.actualKieCredits(
                model: request.model,
                resolution: request.resolution,
                imageCount: images.count,
                totalCredits: $0
            )
        }
        return GenerationResult(images: images, usedResolution: request.resolution, cost: totalCost)
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
            let fileName = sanitizedFilename(image.filename)
            let payload: [String: Any] = [
                "base64Data": "data:\(image.mimeType);base64,\(image.data.base64EncodedString())",
                "uploadPath": "images/base64",
                "fileName": fileName
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

    private func createTask(
        spec: KieModelSpec,
        request: GenerationRequest,
        prompt: String,
        uploadedImageURLs: [String],
        apiKey: String,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> String {
        var input: [String: Any] = [:]
        if spec.kind.requiresPrompt || !prompt.isEmpty {
            input["prompt"] = prompt
        }

        switch spec.inputField {
        case .none:
            break
        case .single(let key):
            guard let firstURL = uploadedImageURLs.first else {
                if spec.requiresInputImage {
                    throw AppError.missingInputImage
                }
                break
            }
            input[key] = firstURL
        case .array(let key):
            if spec.requiresInputImage && uploadedImageURLs.isEmpty {
                throw AppError.missingInputImage
            }
            input[key] = uploadedImageURLs
        }

        if let key = spec.aspectRatioKey {
            input[key] = request.aspectRatio.rawValue
        }
        if let key = spec.resolutionKey {
            input[key] = request.resolution.rawValue
        }
        if let key = spec.imageSizeKey {
            input[key] = imageSizeString(for: request.aspectRatio)
        }
        if let key = spec.outputFormatKey {
            input[key] = "png"
        }
        if let key = spec.upscaleFactorKey {
            input[key] = upscaleFactorString(for: request.resolution)
        }
        for (key, value) in spec.defaultInput {
            input[key] = jsonValue(from: value)
        }

        let payload: [String: Any] = [
            "model": spec.model,
            "input": input
        ]

        let endpoint = apiBaseURL.appendingPathComponent("api/v1/jobs/createTask")
        let responseData = try await executeRequest(
            endpoint: endpoint,
            method: "POST",
            apiKey: apiKey,
            body: try JSONSerialization.data(withJSONObject: payload),
            timeoutSec: timeoutSec,
            session: session,
            route: route
        )
        let decoded = try JSONDecoder().decode(TaskCreateResponse.self, from: responseData)
        guard decoded.code == 200,
              let taskID = decoded.data?.taskId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !taskID.isEmpty else {
            throw mapKieBusinessError(code: decoded.code, message: decoded.msg)
        }
        return taskID
    }

    private func pollTaskResult(
        taskID: String,
        apiKey: String,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> TaskResult {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSec))
        var intervalNanoseconds: UInt64 = 2_000_000_000

        while Date() < deadline {
            var components = URLComponents(url: apiBaseURL.appendingPathComponent("api/v1/jobs/recordInfo"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "taskId", value: taskID)]
            guard let endpoint = components?.url else {
                throw AppError.invalidConfiguration("Invalid Kie recordInfo URL")
            }

            let responseData = try await executeRequest(
                endpoint: endpoint,
                method: "GET",
                apiKey: apiKey,
                body: nil,
                timeoutSec: timeoutSec,
                session: session,
                route: route
            )
            let decoded = try JSONDecoder().decode(TaskRecordResponse.self, from: responseData)
            guard decoded.code == 200, let record = decoded.data else {
                throw mapKieBusinessError(code: decoded.code, message: decoded.msg)
            }

            let state = (record.state ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["success", "succeeded", "completed", "complete"].contains(state) {
                return TaskResult(
                    urls: try resultURLs(from: record.resultJson),
                    creditsConsumed: record.creditsConsumed
                )
            }

            if ["fail", "failed", "error", "canceled", "cancelled"].contains(state) {
                let details = [record.failCode, record.failMsg]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ": ")
                throw AppError.kieTaskFailed(details.isEmpty ? "Task failed" : details)
            }

            try await Task.sleep(nanoseconds: intervalNanoseconds)
            intervalNanoseconds = min(intervalNanoseconds + 1_000_000_000, 5_000_000_000)
        }

        throw AppError.timeoutWithDetails("Kie task \(taskID) did not complete within \(timeoutSec)s")
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = TimeInterval(timeoutSec)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

    private func downloadImage(from url: URL, timeoutSec: Int, session: URLSession, route: NetworkRoute) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(timeoutSec)
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

    private func resultURLs(from resultJson: String?) throws -> [URL] {
        guard let resultJson,
              let data = resultJson.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.noImageInResponse
        }

        var urlStrings: [String] = []
        if let resultUrls = object["resultUrls"] as? [String] {
            urlStrings += resultUrls
        }
        if let resultURL = object["resultUrl"] as? String {
            urlStrings.append(resultURL)
        }
        if let url = object["url"] as? String {
            urlStrings.append(url)
        }
        if let imageURL = object["imageUrl"] as? String {
            urlStrings.append(imageURL)
        }
        if let imageUrl = object["image_url"] as? String {
            urlStrings.append(imageUrl)
        }
        collectURLStrings(from: object, into: &urlStrings)

        var seenURLStrings = Set<String>()
        let urls = urlStrings.compactMap { rawValue -> URL? in
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard seenURLStrings.insert(normalized).inserted else {
                return nil
            }
            return URL(string: normalized)
        }
        guard !urls.isEmpty else {
            throw AppError.noImageInResponse
        }
        return urls
    }

    private func collectURLStrings(from value: Any, into urlStrings: inout [String]) {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
                urlStrings.append(trimmed)
            }
            return
        }

        if let array = value as? [Any] {
            for item in array {
                collectURLStrings(from: item, into: &urlStrings)
            }
            return
        }

        if let dictionary = value as? [String: Any] {
            for item in dictionary.values {
                collectURLStrings(from: item, into: &urlStrings)
            }
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

    private func imageSizeString(for aspectRatio: ImageAspectRatio) -> String {
        switch aspectRatio {
        case .square:
            return "square_hd"
        case .landscape16x9:
            return "landscape_16_9"
        case .portrait9x16:
            return "portrait_9_16"
        case .landscape4x3, .landscape3x2, .landscape21x9:
            return "landscape_4_3"
        case .portrait3x4, .portrait2x3, .portrait9x21:
            return "portrait_4_3"
        }
    }

    private func upscaleFactorString(for resolution: ImageResolution) -> String {
        switch resolution {
        case .k4:
            return "4"
        case .k1, .k2:
            return "2"
        }
    }

    private func jsonValue(from value: String) -> Any {
        if value == "true" { return true }
        if value == "false" { return false }
        if let intValue = Int(value) { return intValue }
        if let doubleValue = Double(value) { return doubleValue }
        return value
    }
}
