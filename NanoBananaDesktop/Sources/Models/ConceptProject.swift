import CoreGraphics
import Foundation

struct ConceptRGBAColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = ConceptRGBAColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = ConceptRGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let blue = ConceptRGBAColor(red: 0.18, green: 0.55, blue: 1, alpha: 1)
    static let clear = ConceptRGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
}

enum ConceptLayerType: String, Codable, CaseIterable, Identifiable, Sendable {
    case referenceImage
    case sketch
    case result

    var id: String { rawValue }
}

enum ConceptTool: String, Codable, CaseIterable, Identifiable, Sendable {
    case brush
    case eraser
    case fill

    var id: String { rawValue }
}

enum ConceptCanvasSizePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var maxDimension: CGFloat {
        switch self {
        case .small:
            return 1024
        case .medium:
            return 1536
        case .large:
            return 2048
        }
    }
}

enum ConceptReferenceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case strictPreserve
    case balanced
    case creative

    var id: String { rawValue }
}

struct ConceptPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
}

struct ConceptStroke: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var tool: ConceptTool
    var color: ConceptRGBAColor
    var width: Double
    var opacity: Double
    var points: [ConceptPoint]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        tool: ConceptTool,
        color: ConceptRGBAColor,
        width: Double,
        opacity: Double,
        points: [ConceptPoint],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.tool = tool
        self.color = color
        self.width = width
        self.opacity = opacity
        self.points = points
        self.createdAt = createdAt
    }
}

struct ConceptLayer: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var type: ConceptLayerType
    var isVisible: Bool
    var isLocked: Bool
    var zIndex: Int
    var strokeColor: ConceptRGBAColor
    var strokeWidth: Double
    var opacity: Double
    var strokes: [ConceptStroke]
    var assetFilename: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: ConceptLayerType,
        isVisible: Bool = true,
        isLocked: Bool = false,
        zIndex: Int,
        strokeColor: ConceptRGBAColor = .blue,
        strokeWidth: Double = 4,
        opacity: Double = 1,
        strokes: [ConceptStroke] = [],
        assetFilename: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.zIndex = zIndex
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.opacity = opacity
        self.strokes = strokes
        self.assetFilename = assetFilename
        self.updatedAt = updatedAt
    }

    var isEditable: Bool {
        (type == .sketch || type == .result) && !isLocked
    }
}

struct ConceptProject: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var canvasAspectRatio: ImageAspectRatio
    var canvasSizePreset: ConceptCanvasSizePreset
    var canvasBackgroundColor: ConceptRGBAColor
    var prompt: String
    var model: String
    var resolutionSelection: ResolutionSelection
    var aspectRatioSelection: AspectRatioSelection
    var referenceMode: ConceptReferenceMode
    var imageCount: Int
    var layers: [ConceptLayer]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Concept Project",
        canvasAspectRatio: ImageAspectRatio = .landscape16x9,
        canvasSizePreset: ConceptCanvasSizePreset = .medium,
        canvasBackgroundColor: ConceptRGBAColor = .clear,
        prompt: String = "",
        model: String = AppConfig.defaultModel,
        resolutionSelection: ResolutionSelection = .k1,
        aspectRatioSelection: AspectRatioSelection = .landscape16x9,
        referenceMode: ConceptReferenceMode = .balanced,
        imageCount: Int = 1,
        layers: [ConceptLayer] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.canvasAspectRatio = canvasAspectRatio
        self.canvasSizePreset = canvasSizePreset
        self.canvasBackgroundColor = canvasBackgroundColor
        self.prompt = prompt
        self.model = model
        self.resolutionSelection = resolutionSelection
        self.aspectRatioSelection = aspectRatioSelection
        self.referenceMode = referenceMode
        self.imageCount = min(max(imageCount, 1), 4)
        self.layers = layers
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func emptyDefault() -> ConceptProject {
        ConceptProject(
            title: "Concept Project",
            canvasAspectRatio: .landscape16x9,
            canvasSizePreset: .medium,
            canvasBackgroundColor: .clear,
            prompt: "",
            model: AppConfig.defaultModel,
            resolutionSelection: .k1,
            aspectRatioSelection: .landscape16x9,
            referenceMode: .balanced,
            imageCount: 1,
            layers: [
                ConceptLayer(name: "Layer 1", type: .sketch, zIndex: 0)
            ]
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case canvasAspectRatio
        case canvasSizePreset
        case canvasBackgroundColor
        case prompt
        case model
        case resolutionSelection
        case aspectRatioSelection
        case referenceMode
        case imageCount
        case layers
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Concept Project"
        canvasAspectRatio = try container.decodeIfPresent(ImageAspectRatio.self, forKey: .canvasAspectRatio) ?? .landscape16x9
        canvasSizePreset = try container.decodeIfPresent(ConceptCanvasSizePreset.self, forKey: .canvasSizePreset) ?? .medium
        canvasBackgroundColor = try container.decodeIfPresent(ConceptRGBAColor.self, forKey: .canvasBackgroundColor) ?? .clear
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? AppConfig.defaultModel
        resolutionSelection = try container.decodeIfPresent(ResolutionSelection.self, forKey: .resolutionSelection) ?? .k1
        aspectRatioSelection = try container.decodeIfPresent(AspectRatioSelection.self, forKey: .aspectRatioSelection) ?? .landscape16x9
        referenceMode = try container.decodeIfPresent(ConceptReferenceMode.self, forKey: .referenceMode) ?? .balanced
        imageCount = min(max(try container.decodeIfPresent(Int.self, forKey: .imageCount) ?? 1, 1), 4)
        layers = try container.decodeIfPresent([ConceptLayer].self, forKey: .layers) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

struct ConceptProjectState: Equatable {
    var project: ConceptProject
    var layerAssetData: [UUID: Data]
}

struct ConceptGenerationContext: Equatable, Sendable {
    var projectID: UUID
    var lockedLayerIDs: [UUID]
    var editableLayerIDs: [UUID]
}
