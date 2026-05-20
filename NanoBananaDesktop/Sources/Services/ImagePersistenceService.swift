import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageGenerationMetadata: Equatable {
    let prompt: String
    let model: String
}

final class ImagePersistenceService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func savePNG(
        imageData: Data,
        filename: String,
        outputDirectory: URL,
        metadata: ImageGenerationMetadata? = nil
    ) throws -> URL {
        guard outputDirectory.path.hasPrefix("/") else {
            throw AppError.invalidOutputDirectory
        }

        let finalFilename: String
        if filename.lowercased().hasSuffix(".png") {
            finalFilename = filename
        } else {
            finalFilename = "\(filename).png"
        }

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let destination = outputDirectory.appendingPathComponent(finalFilename, isDirectory: false)
        let outputData = metadata
            .flatMap { pngDataEmbeddingMetadata(imageData: imageData, metadata: $0) }
            ?? imageData

        do {
            try outputData.write(to: destination, options: [.atomic])
        } catch {
            throw AppError.ioError(error.localizedDescription)
        }

        return destination
    }

    private func pngDataEmbeddingMetadata(imageData: Data, metadata: ImageGenerationMetadata) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let image = normalizedRGBAImage(from: sourceImage) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        var pngMetadata: [CFString: Any] = [
            kCGImagePropertyPNGSoftware: "NanoBananaDesktop"
        ]

        let trimmedPrompt = metadata.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            pngMetadata[kCGImagePropertyPNGDescription] = trimmedPrompt
        }

        let trimmedModel = metadata.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            pngMetadata[kCGImagePropertyPNGTitle] = trimmedModel
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: pngMetadata
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return output as Data
    }

    private func normalizedRGBAImage(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
