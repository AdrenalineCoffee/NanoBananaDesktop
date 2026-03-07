import Foundation

struct PromptPreset: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var prompt: String
    var imageModel: String
    var resolutionSelection: ResolutionSelection
    var aspectRatioSelection: AspectRatioSelection
    var imageCount: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        imageModel: String,
        resolutionSelection: ResolutionSelection,
        aspectRatioSelection: AspectRatioSelection,
        imageCount: Int,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.imageModel = imageModel
        self.resolutionSelection = resolutionSelection
        self.aspectRatioSelection = aspectRatioSelection
        self.imageCount = min(max(imageCount, 1), 4)
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case prompt
        case imageModel
        case resolutionSelection
        case aspectRatioSelection
        case imageCount
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        imageModel = try container.decodeIfPresent(String.self, forKey: .imageModel) ?? AppConfig.defaultModel
        resolutionSelection = try container.decodeIfPresent(ResolutionSelection.self, forKey: .resolutionSelection) ?? .k1
        aspectRatioSelection = try container.decodeIfPresent(AspectRatioSelection.self, forKey: .aspectRatioSelection) ?? .auto
        imageCount = min(max(try container.decodeIfPresent(Int.self, forKey: .imageCount) ?? 1, 1), 4)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
