import Foundation

enum HistoryStatus: String, Codable, CaseIterable {
    case success
    case error
}

struct HistoryRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let mode: GenerationMode
    let prompt: String
    let resolution: ImageResolution
    let inputImagePaths: [String]
    let outputImagePath: String?
    let status: HistoryStatus
    let errorMessage: String?
    let durationMs: Int
    let modelResponseText: String?

    let networkRoute: NetworkRoute
    let proxyUsed: Bool
    let fallbackUsed: Bool
    let proxySummary: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mode: GenerationMode,
        prompt: String,
        resolution: ImageResolution,
        inputImagePaths: [String],
        outputImagePath: String?,
        status: HistoryStatus,
        errorMessage: String?,
        durationMs: Int,
        modelResponseText: String? = nil,
        networkRoute: NetworkRoute = .proxy,
        proxyUsed: Bool = true,
        fallbackUsed: Bool = false,
        proxySummary: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.prompt = prompt
        self.resolution = resolution
        self.inputImagePaths = inputImagePaths
        self.outputImagePath = outputImagePath
        self.status = status
        self.errorMessage = errorMessage
        self.durationMs = durationMs
        self.modelResponseText = modelResponseText
        self.networkRoute = networkRoute
        self.proxyUsed = proxyUsed
        self.fallbackUsed = fallbackUsed
        self.proxySummary = proxySummary
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case mode
        case prompt
        case resolution
        case inputImagePaths
        case inputImagePath
        case outputImagePath
        case status
        case errorMessage
        case durationMs
        case modelResponseText
        case networkRoute
        case proxyUsed
        case fallbackUsed
        case proxySummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        mode = try container.decodeIfPresent(GenerationMode.self, forKey: .mode) ?? .generate
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        resolution = try container.decodeIfPresent(ImageResolution.self, forKey: .resolution) ?? .k1

        if let paths = try container.decodeIfPresent([String].self, forKey: .inputImagePaths) {
            inputImagePaths = paths
        } else if let single = try container.decodeIfPresent(String.self, forKey: .inputImagePath),
                  !single.isEmpty {
            inputImagePaths = [single]
        } else {
            inputImagePaths = []
        }

        outputImagePath = try container.decodeIfPresent(String.self, forKey: .outputImagePath)
        status = try container.decodeIfPresent(HistoryStatus.self, forKey: .status) ?? .error
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        modelResponseText = try container.decodeIfPresent(String.self, forKey: .modelResponseText)
        networkRoute = try container.decodeIfPresent(NetworkRoute.self, forKey: .networkRoute) ?? .proxy
        proxyUsed = try container.decodeIfPresent(Bool.self, forKey: .proxyUsed) ?? true
        fallbackUsed = try container.decodeIfPresent(Bool.self, forKey: .fallbackUsed) ?? false
        proxySummary = try container.decodeIfPresent(String.self, forKey: .proxySummary)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(mode, forKey: .mode)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(inputImagePaths, forKey: .inputImagePaths)
        try container.encodeIfPresent(outputImagePath, forKey: .outputImagePath)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encodeIfPresent(modelResponseText, forKey: .modelResponseText)
        try container.encode(networkRoute, forKey: .networkRoute)
        try container.encode(proxyUsed, forKey: .proxyUsed)
        try container.encode(fallbackUsed, forKey: .fallbackUsed)
        try container.encodeIfPresent(proxySummary, forKey: .proxySummary)
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case success
    case error

    var id: String { rawValue }
}
