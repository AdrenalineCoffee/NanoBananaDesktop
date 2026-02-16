import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
@MainActor
func historyThumbnailLoaderGeneratesThumbnailForValidImage() async throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let imageURL = tempDirectory.appendingPathComponent("sample.png")
    try tinyPNGData.write(to: imageURL)

    let loader = HistoryThumbnailLoader(countLimit: 8, totalCostLimit: 2 * 1024 * 1024)
    let thumbnail = await loader.thumbnail(for: imageURL.path, targetSize: CGSize(width: 44, height: 44))

    #expect(thumbnail != nil)
}

@Test
@MainActor
func historyThumbnailLoaderUsesInMemoryCacheForRepeatedRequests() async throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let imageURL = tempDirectory.appendingPathComponent("sample.png")
    try tinyPNGData.write(to: imageURL)

    let loader = HistoryThumbnailLoader(countLimit: 8, totalCostLimit: 2 * 1024 * 1024)
    let first = await loader.thumbnail(for: imageURL.path, targetSize: CGSize(width: 44, height: 44))
    let second = await loader.thumbnail(for: imageURL.path, targetSize: CGSize(width: 44, height: 44))

    #expect(first != nil)
    #expect(second != nil)
    #expect(first === second)
}

@Test
@MainActor
func historyThumbnailLoaderReturnsNilForCorruptedOrMissingFile() async throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let corruptedURL = tempDirectory.appendingPathComponent("bad.png")
    try Data("not-an-image".utf8).write(to: corruptedURL)
    let missingURL = tempDirectory.appendingPathComponent("missing.png")

    let loader = HistoryThumbnailLoader(countLimit: 8, totalCostLimit: 2 * 1024 * 1024)
    let corrupted = await loader.thumbnail(for: corruptedURL.path, targetSize: CGSize(width: 44, height: 44))
    let missing = await loader.thumbnail(for: missingURL.path, targetSize: CGSize(width: 44, height: 44))

    #expect(corrupted == nil)
    #expect(missing == nil)
}

private let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+2YQAAAAASUVORK5CYII="
private let tinyPNGData = Data(base64Encoded: tinyPNGBase64)!
