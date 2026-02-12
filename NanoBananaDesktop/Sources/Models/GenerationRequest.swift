import Foundation

struct GenerationInputImage: Equatable {
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

struct GenerationRequest {
    var mode: GenerationMode
    var prompt: String
    var model: String
    var apiKey: String
    var resolution: ImageResolution
    var aspectRatio: ImageAspectRatio
    var inputImages: [GenerationInputImage]
}

struct GenerationResult {
    let imageData: Data
    let modelText: String?
    let usedResolution: ImageResolution
}
