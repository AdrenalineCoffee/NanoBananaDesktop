import Foundation
import ImageIO
import Testing
@testable import NanoBananaDesktop

@Test
func imagePersistenceServiceEmbedsPromptAndModelMetadataIntoPNG() throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let service = ImagePersistenceService()
    let prompt = "A cinematic product render"
    let model = "gpt-image-2"

    let savedURL = try service.savePNG(
        imageData: imagePersistenceTinyPNGData,
        filename: "render",
        outputDirectory: tempDirectory,
        metadata: ImageGenerationMetadata(prompt: prompt, model: model)
    )

    let source = try #require(CGImageSourceCreateWithURL(savedURL as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    let pngProperties = try #require(properties[kCGImagePropertyPNGDictionary as String] as? [String: Any])

    #expect(pngProperties[kCGImagePropertyPNGDescription as String] as? String == prompt)
    #expect(pngProperties[kCGImagePropertyPNGTitle as String] as? String == model)
    #expect(pngProperties[kCGImagePropertyPNGSoftware as String] as? String == "NanoBananaDesktop")
}

private let imagePersistenceTinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+2YQAAAAASUVORK5CYII="
private let imagePersistenceTinyPNGData = Data(base64Encoded: imagePersistenceTinyPNGBase64)!
