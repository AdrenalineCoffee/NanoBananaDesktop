import Foundation

enum GenerationCostUnit: String, Codable, Sendable {
    case usd
    case kieCredits
    case unknown
}

enum GenerationCostConfidence: String, Codable, Sendable {
    case estimated
    case actual
    case unavailable
}

struct GenerationCostEstimate: Equatable, Sendable {
    let provider: ModelProvider
    let model: String
    let resolution: ImageResolution
    let imageCount: Int
    let unit: GenerationCostUnit
    let perImage: Double?
    let total: Double?
    let confidence: GenerationCostConfidence
    let note: String?

    func matches(
        provider: ModelProvider,
        model: String,
        resolution: ImageResolution,
        imageCount: Int
    ) -> Bool {
        self.provider == provider &&
            self.model.caseInsensitiveCompare(model) == .orderedSame &&
            self.resolution == resolution &&
            self.imageCount == imageCount
    }
}
