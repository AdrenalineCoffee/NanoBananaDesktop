import Foundation

struct GenerationInputImage: Equatable, Sendable {
    let id: UUID
    let fileURL: URL
    let filename: String
    let mimeType: String
    let data: Data

    init(
        id: UUID = UUID(),
        fileURL: URL,
        filename: String,
        mimeType: String,
        data: Data
    ) {
        self.id = id
        self.fileURL = fileURL
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

struct GenerationRequest: Sendable {
    var mode: GenerationMode
    var prompt: String
    var model: String
    var apiKey: String
    var resolution: ImageResolution
    var aspectRatio: ImageAspectRatio
    var inputImages: [GenerationInputImage]
    var imageCount: Int = 1
}

struct GeneratedImageResult: Equatable, Sendable {
    let imageData: Data
    let modelText: String?
    let cost: GenerationCostEstimate?

    init(imageData: Data, modelText: String?, cost: GenerationCostEstimate? = nil) {
        self.imageData = imageData
        self.modelText = modelText
        self.cost = cost
    }
}

struct GenerationResult: Equatable, Sendable {
    let images: [GeneratedImageResult]
    let usedResolution: ImageResolution
    let cost: GenerationCostEstimate?

    init(
        images: [GeneratedImageResult],
        usedResolution: ImageResolution,
        cost: GenerationCostEstimate? = nil
    ) {
        self.images = images
        self.usedResolution = usedResolution
        self.cost = cost
    }

    var imageData: Data {
        images.first?.imageData ?? Data()
    }

    var imageDatas: [Data] {
        images.map(\.imageData)
    }

    var modelText: String? {
        images
            .compactMap(\.modelText)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
