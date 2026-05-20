import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func maskedPatchDataKeepsPixelsOnlyInsideMask() throws {
    let rasterizer = ConceptRasterizer()
    let canvasSize = CGSize(width: 2, height: 2)
    let source = try #require(makeRGBAImageData(size: canvasSize) { x, y in
        if x == 0 && y == 0 { return (255, 0, 0, 255) }
        return (0, 255, 0, 255)
    })
    let mask = try #require(makeRGBAImageData(size: canvasSize) { x, y in
        let visible = (x == 0 && y == 0)
        let value: UInt8 = visible ? 255 : 0
        return (value, value, value, 255)
    })

    let patch = try #require(rasterizer.maskedPatchData(imageData: source, maskData: mask, canvasSize: canvasSize))
    let pixels = try #require(readRGBA(pngData: patch))

    #expect(pixels[0][0] == (255, 0, 0, 255))
    #expect(pixels[0][1].3 == 0)
    #expect(pixels[1][0].3 == 0)
    #expect(pixels[1][1].3 == 0)
}

@Test
func maskDataPreservesTopLeftOrientation() throws {
    let rasterizer = ConceptRasterizer()
    let canvasSize = CGSize(width: 2, height: 2)
    let layerID = UUID()
    let asset = try #require(makeRGBAImageData(size: canvasSize) { x, y in
        if x == 0 && y == 0 { return (255, 255, 255, 255) }
        return (0, 0, 0, 0)
    })
    let layer = ConceptLayer(
        id: layerID,
        name: "Mask",
        type: .sketch,
        isVisible: true,
        isLocked: false,
        zIndex: 0,
        assetFilename: "layer-\(layerID.uuidString).png"
    )

    let mask = try #require(
        rasterizer.maskData(
            layers: [layer],
            assetDataByLayer: [layerID: asset],
            canvasSize: canvasSize,
            predicate: { _ in true }
        )
    )
    let pixels = try #require(readRGBA(pngData: mask))
    #expect(pixels[0][0].0 == 255)
    #expect(pixels[1][0].0 == 0)
}

@Test
func floodFillDataFillsConnectedTransparentRegion() throws {
    let rasterizer = ConceptRasterizer()
    let canvasSize = CGSize(width: 2, height: 2)
    let result = try #require(
        rasterizer.floodFillData(
            imageData: nil,
            canvasSize: canvasSize,
            startPoint: ConceptPoint(x: 0.75, y: 0.75),
            fillColor: .blue,
            opacity: 1
        )
    )
    let pixels = try #require(readRGBA(pngData: result))
    for row in pixels {
        for pixel in row {
            #expect(pixel.2 > 0)
            #expect(pixel.3 == 255)
        }
    }
}

@Test
func removeBackgroundDataRemovesBorderConnectedWhiteBackground() throws {
    let rasterizer = ConceptRasterizer()
    let canvasSize = CGSize(width: 3, height: 3)
    let source = try #require(makeRGBAImageData(size: canvasSize) { x, y in
        if x == 1 && y == 1 {
            return (32, 64, 160, 255)
        }
        return (255, 255, 255, 255)
    })

    let result = try rasterizer.removeBackgroundData(source, canvasSize: canvasSize)
    let pixels = try #require(readRGBA(pngData: result))

    #expect(pixels[0][0].3 == 0)
    #expect(pixels[0][2].3 == 0)
    #expect(pixels[2][0].3 == 0)
    #expect(pixels[2][2].3 == 0)
    #expect(pixels[1][1].3 > 240)
    #expect(pixels[1][1].2 > 120)
}

@Test
func subtractMaskDataRemovesProtectedPixelsFromEditableRegion() throws {
    let rasterizer = ConceptRasterizer()
    let canvasSize = CGSize(width: 3, height: 1)
    let editableMask = try #require(makeRGBAImageData(size: canvasSize) { x, _ in
        let value: UInt8 = x < 3 ? 255 : 0
        return (value, value, value, 255)
    })
    let protectMask = try #require(makeRGBAImageData(size: canvasSize) { x, _ in
        let value: UInt8 = x == 1 ? 255 : 0
        return (value, value, value, 255)
    })

    let result = try #require(
        rasterizer.subtractMaskData(
            primaryMaskData: editableMask,
            subtractingMaskData: protectMask,
            canvasSize: canvasSize
        )
    )
    let pixels = try #require(readRGBA(pngData: result))

    #expect(pixels[0][0].0 == 255)
    #expect(pixels[0][1].0 == 0)
    #expect(pixels[0][2].0 == 255)
}

@Test
func contentAwareMaskDataIgnoresWhiteReferenceBackground() throws {
    let rasterizer = ConceptRasterizer()
    let canvasSize = CGSize(width: 3, height: 3)
    let layerID = UUID()
    let reference = try #require(makeRGBAImageData(size: canvasSize) { x, y in
        if x == 1 && y == 1 {
            return (255, 0, 0, 255)
        }
        return (255, 255, 255, 255)
    })
    let layer = ConceptLayer(
        id: layerID,
        name: "Reference",
        type: .referenceImage,
        isVisible: true,
        isLocked: true,
        zIndex: 0,
        assetFilename: "layer-\(layerID.uuidString).png"
    )

    let mask = try #require(
        rasterizer.contentAwareMaskData(
            layers: [layer],
            assetDataByLayer: [layerID: reference],
            canvasSize: canvasSize,
            predicate: { _ in true }
        )
    )
    let pixels = try #require(readRGBA(pngData: mask))

    #expect(pixels[1][1].0 == 255)
    #expect(pixels[0][0].0 == 0)
    #expect(pixels[0][2].0 == 0)
    #expect(pixels[2][0].0 == 0)
    #expect(pixels[2][2].0 == 0)
}

@Test
func expandedROIRectAddsPaddingAndClampsToCanvasBounds() {
    let rasterizer = ConceptRasterizer()
    let roi = rasterizer.expandedROIRect(
        for: CGRect(x: 80, y: 80, width: 20, height: 20),
        paddingFraction: 0.2,
        canvasSize: CGSize(width: 100, height: 100)
    )

    #expect(roi.origin.x == 76)
    #expect(roi.origin.y == 76)
    #expect(roi.maxX == 100)
    #expect(roi.maxY == 100)
}

@Test
func blendedImageDataPreservesBaseOutsideMaskAndUsesGeneratedInsideMask() throws {
    let rasterizer = ConceptRasterizer()
    let size = CGSize(width: 2, height: 1)
    let base = try #require(makeRGBAImageData(size: size) { _, _ in (255, 0, 0, 255) })
    let generated = try #require(makeRGBAImageData(size: size) { _, _ in (0, 0, 255, 255) })
    let mask = try #require(makeRGBAImageData(size: size) { x, _ in
        let value: UInt8 = x == 1 ? 255 : 0
        return (value, value, value, 255)
    })

    let blended = try #require(
        rasterizer.blendedImageData(
            baseData: base,
            generatedData: generated,
            maskData: mask,
            canvasSize: size
        )
    )
    let pixels = try #require(readRGBA(pngData: blended))

    #expect(pixels[0][0] == (255, 0, 0, 255))
    #expect(pixels[0][1] == (0, 0, 255, 255))
}

@Test
func reinsertCropDataPlacesPatchAtExpectedCanvasOffset() throws {
    let rasterizer = ConceptRasterizer()
    let crop = try #require(makeRGBAImageData(size: CGSize(width: 1, height: 1)) { _, _ in (0, 255, 0, 255) })
    let reinjected = try #require(
        rasterizer.reinsertCropData(
            crop,
            roiRect: CGRect(x: 1, y: 0, width: 1, height: 1),
            canvasSize: CGSize(width: 2, height: 1)
        )
    )
    let pixels = try #require(readRGBA(pngData: reinjected))

    #expect(pixels[0][0].3 == 0)
    #expect(pixels[0][1] == (0, 255, 0, 255))
}

@Test
func subtractProtectedPixelsClearsProtectedRegionWithoutClippingElsewhere() throws {
    let rasterizer = ConceptRasterizer()
    let size = CGSize(width: 3, height: 1)
    let image = try #require(makeRGBAImageData(size: size) { _, _ in (255, 0, 0, 255) })
    let protectMask = try #require(makeRGBAImageData(size: size) { x, _ in
        let value: UInt8 = x == 1 ? 255 : 0
        return (value, value, value, 255)
    })

    let result = try #require(
        rasterizer.subtractProtectedPixels(
            imageData: image,
            protectMaskData: protectMask,
            canvasSize: size
        )
    )
    let pixels = try #require(readRGBA(pngData: result))

    #expect(pixels[0][0] == (255, 0, 0, 255))
    #expect(pixels[0][1].3 == 0)
    #expect(pixels[0][2] == (255, 0, 0, 255))
}

@Test
func differenceMaskDataKeepsOnlyChangedPixels() throws {
    let rasterizer = ConceptRasterizer()
    let size = CGSize(width: 3, height: 1)
    let base = try #require(makeRGBAImageData(size: size) { _, _ in (255, 255, 255, 255) })
    let generated = try #require(makeRGBAImageData(size: size) { x, _ in
        if x == 1 { return (255, 0, 0, 255) }
        return (255, 255, 255, 255)
    })

    let mask = try #require(
        rasterizer.differenceMaskData(
            baseData: base,
            generatedData: generated,
            canvasSize: size,
            threshold: 0.05,
            dilationRadius: 0
        )
    )
    let pixels = try #require(readRGBA(pngData: mask))

    #expect(pixels[0][0].0 == 0)
    #expect(pixels[0][1].0 == 255)
    #expect(pixels[0][2].0 == 0)
}

@Test
func subtractProtectOutsideExpandedSketchKeepsPixelsInsideSketchEnvelope() throws {
    let rasterizer = ConceptRasterizer()
    let size = CGSize(width: 5, height: 1)
    let foreground = try #require(makeRGBAImageData(size: size) { _, _ in (255, 0, 0, 255) })
    let sketchMask = try #require(makeRGBAImageData(size: size) { x, _ in
        let value: UInt8 = (1...3).contains(x) ? 255 : 0
        return (value, value, value, 255)
    })
    let protectMask = try #require(makeRGBAImageData(size: size) { x, _ in
        let value: UInt8 = x == 0 || x == 4 ? 255 : 0
        return (value, value, value, 255)
    })

    let foregroundMask = try #require(rasterizer.alphaMaskData(imageData: foreground, canvasSize: size))
    let expandedSketch = try #require(rasterizer.dilatedMaskData(maskData: sketchMask, canvasSize: size, dilationRadius: 0))
    let protectOutside = try #require(
        rasterizer.subtractMaskData(
            primaryMaskData: protectMask,
            subtractingMaskData: expandedSketch,
            canvasSize: size
        )
    )
    let resultMask = try #require(
        rasterizer.subtractMaskData(
            primaryMaskData: foregroundMask,
            subtractingMaskData: protectOutside,
            canvasSize: size
        )
    )
    let pixels = try #require(readRGBA(pngData: resultMask))

    #expect(pixels[0][0].0 == 0)
    #expect(pixels[0][1].0 == 255)
    #expect(pixels[0][2].0 == 255)
    #expect(pixels[0][3].0 == 255)
    #expect(pixels[0][4].0 == 0)
}

@Test
func connectedComponentMaskKeepsOnlySeedConnectedRegion() throws {
    let rasterizer = ConceptRasterizer()
    let size = CGSize(width: 5, height: 1)
    let sourceMask = try #require(makeRGBAImageData(size: size) { x, _ in
        let value: UInt8 = (0...1).contains(x) || (3...4).contains(x) ? 255 : 0
        return (value, value, value, 255)
    })
    let seedMask = try #require(makeRGBAImageData(size: size) { x, _ in
        let value: UInt8 = x == 4 ? 255 : 0
        return (value, value, value, 255)
    })

    let result = try #require(
        rasterizer.connectedComponentMaskData(
            sourceMaskData: sourceMask,
            seedMaskData: seedMask,
            canvasSize: size,
            dilationRadius: 0
        )
    )
    let pixels = try #require(readRGBA(pngData: result))

    #expect(pixels[0][0].0 == 0)
    #expect(pixels[0][1].0 == 0)
    #expect(pixels[0][2].0 == 0)
    #expect(pixels[0][3].0 == 255)
    #expect(pixels[0][4].0 == 255)
}


private func makeRGBAImageData(size: CGSize, pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> Data? {
    let width = Int(size.width)
    let height = Int(size.height)
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * context.bytesPerRow + x * 4
            let rgba = pixel(x, y)
            bytes[offset] = rgba.0
            bytes[offset + 1] = rgba.1
            bytes[offset + 2] = rgba.2
            bytes[offset + 3] = rgba.3
        }
    }

    guard let image = context.makeImage() else { return nil }
    let mutable = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(mutable as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return mutable as Data
}

private func readRGBA(pngData: Data) -> [[(UInt8, UInt8, UInt8, UInt8)]]? {
    guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let data = image.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data) else {
        return nil
    }

    var result: [[(UInt8, UInt8, UInt8, UInt8)]] = []
    for y in 0..<image.height {
        var row: [(UInt8, UInt8, UInt8, UInt8)] = []
        for x in 0..<image.width {
            let offset = y * image.bytesPerRow + x * 4
            row.append((bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]))
        }
        result.append(row)
    }
    return result
}
