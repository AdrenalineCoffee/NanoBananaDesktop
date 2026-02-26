import AppKit
import Foundation
import ImageIO

@MainActor
final class HistoryThumbnailLoader {
    static let shared = HistoryThumbnailLoader()

    private let cache = NSCache<NSString, NSImage>()

    init(countLimit: Int = 80, totalCostLimit: Int = 32 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func thumbnail(for path: String, targetSize: CGSize) async -> NSImage? {
        let key = cacheKey(path: path, targetSize: targetSize)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let rendered = await Self.renderThumbnail(path: path, targetSize: targetSize)
        guard let rendered else {
            return nil
        }

        let cost = max(1, Int(rendered.size.width * rendered.size.height * 4))
        cache.setObject(rendered, forKey: key as NSString, cost: cost)
        return rendered
    }

    func prefetch(paths: [String], targetSize: CGSize) async {
        for path in paths {
            _ = await thumbnail(for: path, targetSize: targetSize)
        }
    }

    private func cacheKey(path: String, targetSize: CGSize) -> String {
        "\(path)#\(Int(targetSize.width))x\(Int(targetSize.height))"
    }

    private nonisolated static func renderThumbnail(path: String, targetSize: CGSize) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let sourceURL = URL(fileURLWithPath: path)
                guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
                    continuation.resume(returning: nil)
                    return
                }

                let maxDimension = max(targetSize.width, targetSize.height)
                let pixelSize = max(64, Int(maxDimension * 2))
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixelSize
                ]

                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }

                // Preserve aspect ratio: using a fixed square size here makes SwiftUI treat the image as 1:1
                // and will visually distort non-square thumbnails.
                let image = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )
                continuation.resume(returning: image)
            }
        }
    }
}
