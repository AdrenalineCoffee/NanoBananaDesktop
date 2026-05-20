import AppKit
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision

struct ConceptRasterizer {
    func canvasPixelSize(aspectRatio: ImageAspectRatio, preset: ConceptCanvasSizePreset) -> CGSize {
        let components = aspectRatio.components
        let maxDimension = preset.maxDimension
        if components.width >= components.height {
            return CGSize(width: maxDimension, height: round(maxDimension * components.height / components.width))
        }
        return CGSize(width: round(maxDimension * components.width / components.height), height: maxDimension)
    }

    func normalizedImportedImageData(_ data: Data, canvasSize: CGSize) -> Data? {
        guard let source = cgImage(from: data),
              let context = makeContext(size: canvasSize) else {
            return nil
        }

        let sourceSize = CGSize(width: source.width, height: source.height)
        let fittedRect = aspectFitRect(for: sourceSize, in: CGRect(origin: .zero, size: canvasSize))
        context.clear(CGRect(origin: .zero, size: canvasSize))
        context.interpolationQuality = .high
        context.draw(source, in: fittedRect)
        return pngData(from: context)
    }

    func removeWhiteBackgroundData(
        _ data: Data,
        threshold: Float = 0.025,
        softness: Float = 0.08
    ) -> Data? {
        guard let source = cgImage(from: data),
              let sourceData = source.dataProvider?.data,
              let sourceBytes = CFDataGetBytePtr(sourceData),
              let context = makeContext(size: CGSize(width: source.width, height: source.height)),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = source.width
        let height = source.height
        let thresholdValue = Double(threshold)
        let softnessValue = max(Double(softness), 0.0001)

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        for y in 0..<height {
            for x in 0..<width {
                let sourceOffset = y * source.bytesPerRow + x * 4
                let outputOffset = y * context.bytesPerRow + x * 4

                let alpha = Double(sourceBytes[sourceOffset + 3]) / 255.0
                let red = Double(sourceBytes[sourceOffset]) / 255.0
                let green = Double(sourceBytes[sourceOffset + 1]) / 255.0
                let blue = Double(sourceBytes[sourceOffset + 2]) / 255.0
                let distanceToWhite = colorDistance((red, green, blue), (1, 1, 1))

                let whitenessAlpha: Double
                if distanceToWhite <= thresholdValue {
                    whitenessAlpha = 0
                } else if distanceToWhite >= thresholdValue + softnessValue {
                    whitenessAlpha = 1
                } else {
                    whitenessAlpha = (distanceToWhite - thresholdValue) / softnessValue
                }

                let finalAlpha = clamp(alpha * whitenessAlpha)
                guard finalAlpha > 0.003 else {
                    outputBytes[outputOffset] = 0
                    outputBytes[outputOffset + 1] = 0
                    outputBytes[outputOffset + 2] = 0
                    outputBytes[outputOffset + 3] = 0
                    continue
                }

                let correctedRed = clamp((red - (1.0 - finalAlpha)) / finalAlpha)
                let correctedGreen = clamp((green - (1.0 - finalAlpha)) / finalAlpha)
                let correctedBlue = clamp((blue - (1.0 - finalAlpha)) / finalAlpha)

                outputBytes[outputOffset] = UInt8((correctedRed * 255.0).rounded())
                outputBytes[outputOffset + 1] = UInt8((correctedGreen * 255.0).rounded())
                outputBytes[outputOffset + 2] = UInt8((correctedBlue * 255.0).rounded())
                outputBytes[outputOffset + 3] = UInt8((finalAlpha * 255.0).rounded())
            }
        }

        return pngData(from: context)
    }

    func removeBackgroundData(_ data: Data, canvasSize: CGSize) throws -> Data {
        if let whiteBackgroundCutout = removeBorderConnectedWhiteBackgroundData(data, canvasSize: canvasSize) {
            return whiteBackgroundCutout
        }

        guard #available(macOS 14.0, *) else {
            throw AppError.conceptBackgroundRemovalUnavailable
        }
        return try removeBackgroundDataVision(data, canvasSize: canvasSize)
    }

    func renderLayerImage(
        layer: ConceptLayer,
        assetData: Data?,
        canvasSize: CGSize
    ) -> NSImage? {
        guard let data = renderLayerData(layer: layer, assetData: assetData, canvasSize: canvasSize) else {
            return nil
        }
        return NSImage(data: data)
    }

    func compositeCanvasImage(
        project: ConceptProject,
        assetDataByLayer: [UUID: Data],
        canvasSize: CGSize
    ) -> NSImage? {
        let hasVisibleContent = project.layers.contains { layer in
            layer.isVisible && (!layer.strokes.isEmpty || assetDataByLayer[layer.id] != nil)
        }
        if !hasVisibleContent && project.canvasBackgroundColor.alpha <= 0.001 {
            return nil
        }
        guard let data = compositeData(
            layers: project.layers,
            assetDataByLayer: assetDataByLayer,
            canvasSize: canvasSize,
            backgroundColor: project.canvasBackgroundColor,
            predicate: { $0.isVisible }
        ) else {
            return nil
        }
        return NSImage(data: data)
    }

    func renderLayerData(
        layer: ConceptLayer,
        assetData: Data?,
        canvasSize: CGSize
    ) -> Data? {
        guard let context = makeContext(size: canvasSize) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        if let assetData,
           let assetImage = cgImage(from: assetData) {
            context.draw(assetImage, in: CGRect(origin: .zero, size: canvasSize))
        }

        for stroke in layer.strokes {
            draw(stroke: stroke, in: context, canvasSize: canvasSize)
        }

        return pngData(from: context)
    }

    func compositeData(
        layers: [ConceptLayer],
        assetDataByLayer: [UUID: Data],
        canvasSize: CGSize,
        backgroundColor: ConceptRGBAColor? = nil,
        predicate: (ConceptLayer) -> Bool
    ) -> Data? {
        guard let context = makeContext(size: canvasSize) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        if let backgroundColor {
            context.setFillColor(
                CGColor(
                    red: backgroundColor.red,
                    green: backgroundColor.green,
                    blue: backgroundColor.blue,
                    alpha: backgroundColor.alpha
                )
            )
            context.fill(CGRect(origin: .zero, size: canvasSize))
        }
        for layer in layers.reversed() where layer.isVisible && predicate(layer) {
            if let data = renderLayerData(layer: layer, assetData: assetDataByLayer[layer.id], canvasSize: canvasSize),
               let image = cgImage(from: data) {
                context.draw(image, in: CGRect(origin: .zero, size: canvasSize))
            }
        }
        return pngData(from: context)
    }

    func maskData(
        layers: [ConceptLayer],
        assetDataByLayer: [UUID: Data],
        canvasSize: CGSize,
        dilationRadius: Int = 0,
        predicate: (ConceptLayer) -> Bool
    ) -> Data? {
        guard let composite = compositeData(
            layers: layers,
            assetDataByLayer: assetDataByLayer,
            canvasSize: canvasSize,
            backgroundColor: nil,
            predicate: predicate
        ),
              let source = cgImage(from: composite),
              let context = makeContext(size: canvasSize) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        let width = min(Int(canvasSize.width.rounded(.down)), source.width)
        let height = min(Int(canvasSize.height.rounded(.down)), source.height)
        guard let data = source.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let bytesPerRow = source.bytesPerRow
        var binaryMask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let sourceOffset = y * bytesPerRow + x * 4
                let alpha = bytes[sourceOffset + 3]
                let value: UInt8 = alpha > 10 ? 255 : 0
                binaryMask[y * width + x] = value
            }
        }

        if dilationRadius > 0 {
            binaryMask = dilatedBinaryMask(binaryMask, width: width, height: height, radius: dilationRadius)
        }

        for y in 0..<height {
            for x in 0..<width {
                let outputOffset = y * context.bytesPerRow + x * 4
                let value = binaryMask[y * width + x]
                outputBytes[outputOffset] = value
                outputBytes[outputOffset + 1] = value
                outputBytes[outputOffset + 2] = value
                outputBytes[outputOffset + 3] = 255
            }
        }

        return pngData(from: context)
    }

    func contentAwareMaskData(
        layers: [ConceptLayer],
        assetDataByLayer: [UUID: Data],
        canvasSize: CGSize,
        dilationRadius: Int = 0,
        predicate: (ConceptLayer) -> Bool
    ) -> Data? {
        let width = max(Int(canvasSize.width.rounded(.down)), 1)
        let height = max(Int(canvasSize.height.rounded(.down)), 1)
        var binaryMask = [UInt8](repeating: 0, count: width * height)

        for layer in layers where layer.isVisible && predicate(layer) {
            guard let renderedData = renderLayerData(
                layer: layer,
                assetData: assetDataByLayer[layer.id],
                canvasSize: canvasSize
            ) else {
                continue
            }

            let processedData: Data
            if assetDataByLayer[layer.id] != nil || layer.type == .referenceImage {
                processedData = removeBorderConnectedWhiteBackgroundData(renderedData, canvasSize: canvasSize)
                    ?? (try? removeBackgroundData(renderedData, canvasSize: canvasSize))
                    ?? Data()
            } else {
                processedData = renderedData
            }

            guard !processedData.isEmpty else {
                continue
            }

            guard let source = cgImage(from: processedData),
                  let sourceData = source.dataProvider?.data,
                  let sourceBytes = CFDataGetBytePtr(sourceData) else {
                continue
            }

            let maskWidth = min(width, source.width)
            let maskHeight = min(height, source.height)
            for y in 0..<maskHeight {
                for x in 0..<maskWidth {
                    let offset = y * source.bytesPerRow + x * 4
                    if sourceBytes[offset + 3] > 10 {
                        binaryMask[y * width + x] = 255
                    }
                }
            }
        }

        if dilationRadius > 0 {
            binaryMask = dilatedBinaryMask(binaryMask, width: width, height: height, radius: dilationRadius)
        }

        guard let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        for y in 0..<height {
            for x in 0..<width {
                let outputOffset = y * context.bytesPerRow + x * 4
                let value = binaryMask[y * width + x]
                outputBytes[outputOffset] = value
                outputBytes[outputOffset + 1] = value
                outputBytes[outputOffset + 2] = value
                outputBytes[outputOffset + 3] = 255
            }
        }

        return pngData(from: context)
    }

    func subtractMaskData(primaryMaskData: Data, subtractingMaskData: Data, canvasSize: CGSize) -> Data? {
        guard let primary = cgImage(from: primaryMaskData),
              let subtracting = cgImage(from: subtractingMaskData),
              let primaryData = primary.dataProvider?.data,
              let subtractingData = subtracting.dataProvider?.data,
              let primaryBytes = CFDataGetBytePtr(primaryData),
              let subtractingBytes = CFDataGetBytePtr(subtractingData),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = min(primary.width, subtracting.width, Int(canvasSize.width.rounded(.down)))
        let height = min(primary.height, subtracting.height, Int(canvasSize.height.rounded(.down)))

        context.clear(CGRect(origin: .zero, size: canvasSize))
        for y in 0..<height {
            for x in 0..<width {
                let primaryOffset = y * primary.bytesPerRow + x * 4
                let subtractingOffset = y * subtracting.bytesPerRow + x * 4
                let outputOffset = y * context.bytesPerRow + x * 4

                let primaryValue = max(primaryBytes[primaryOffset], max(primaryBytes[primaryOffset + 1], primaryBytes[primaryOffset + 2]))
                let subtractingValue = max(subtractingBytes[subtractingOffset], max(subtractingBytes[subtractingOffset + 1], subtractingBytes[subtractingOffset + 2]))
                let value: UInt8 = (primaryValue > 0 && subtractingValue == 0) ? 255 : 0
                outputBytes[outputOffset] = value
                outputBytes[outputOffset + 1] = value
                outputBytes[outputOffset + 2] = value
                outputBytes[outputOffset + 3] = 255
            }
        }

        return pngData(from: context)
    }

    func intersectMaskData(primaryMaskData: Data, intersectingMaskData: Data, canvasSize: CGSize) -> Data? {
        guard let primary = cgImage(from: primaryMaskData),
              let intersecting = cgImage(from: intersectingMaskData),
              let primaryData = primary.dataProvider?.data,
              let intersectingData = intersecting.dataProvider?.data,
              let primaryBytes = CFDataGetBytePtr(primaryData),
              let intersectingBytes = CFDataGetBytePtr(intersectingData),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = min(primary.width, intersecting.width, Int(canvasSize.width.rounded(.down)))
        let height = min(primary.height, intersecting.height, Int(canvasSize.height.rounded(.down)))

        context.clear(CGRect(origin: .zero, size: canvasSize))
        for y in 0..<height {
            for x in 0..<width {
                let primaryOffset = y * primary.bytesPerRow + x * 4
                let intersectingOffset = y * intersecting.bytesPerRow + x * 4
                let outputOffset = y * context.bytesPerRow + x * 4

                let primaryValue = max(primaryBytes[primaryOffset], max(primaryBytes[primaryOffset + 1], primaryBytes[primaryOffset + 2]))
                let intersectingValue = max(intersectingBytes[intersectingOffset], max(intersectingBytes[intersectingOffset + 1], intersectingBytes[intersectingOffset + 2]))
                let value: UInt8 = (primaryValue > 0 && intersectingValue > 0) ? 255 : 0
                outputBytes[outputOffset] = value
                outputBytes[outputOffset + 1] = value
                outputBytes[outputOffset + 2] = value
                outputBytes[outputOffset + 3] = 255
            }
        }

        return pngData(from: context)
    }

    func connectedComponentMaskData(
        sourceMaskData: Data,
        seedMaskData: Data,
        canvasSize: CGSize,
        dilationRadius: Int = 0
    ) -> Data? {
        guard let source = cgImage(from: sourceMaskData),
              let seed = cgImage(from: seedMaskData),
              let sourceData = source.dataProvider?.data,
              let seedData = seed.dataProvider?.data,
              let sourceBytes = CFDataGetBytePtr(sourceData),
              let seedBytes = CFDataGetBytePtr(seedData),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = min(source.width, seed.width, Int(canvasSize.width.rounded(.down)))
        let height = min(source.height, seed.height, Int(canvasSize.height.rounded(.down)))
        guard width > 0, height > 0 else { return nil }

        var sourceMask = [UInt8](repeating: 0, count: width * height)
        var queue: [(Int, Int)] = []
        queue.reserveCapacity(width * height / 8)

        for y in 0..<height {
            for x in 0..<width {
                let sourceOffset = y * source.bytesPerRow + x * 4
                let seedOffset = y * seed.bytesPerRow + x * 4
                let sourceValue = max(sourceBytes[sourceOffset], max(sourceBytes[sourceOffset + 1], sourceBytes[sourceOffset + 2]))
                let seedValue = max(seedBytes[seedOffset], max(seedBytes[seedOffset + 1], seedBytes[seedOffset + 2]))
                let index = y * width + x
                sourceMask[index] = sourceValue > 10 ? 255 : 0
                if sourceMask[index] > 0 && seedValue > 10 {
                    queue.append((x, y))
                }
            }
        }

        guard !queue.isEmpty else { return nil }

        var visited = [UInt8](repeating: 0, count: width * height)
        var queueIndex = 0
        while queueIndex < queue.count {
            let (x, y) = queue[queueIndex]
            queueIndex += 1

            guard x >= 0, x < width, y >= 0, y < height else { continue }
            let index = y * width + x
            guard visited[index] == 0, sourceMask[index] > 0 else { continue }
            visited[index] = 255

            queue.append((x + 1, y))
            queue.append((x - 1, y))
            queue.append((x, y + 1))
            queue.append((x, y - 1))
        }

        if dilationRadius > 0 {
            visited = dilatedBinaryMask(visited, width: width, height: height, radius: dilationRadius)
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        for y in 0..<height {
            for x in 0..<width {
                let outputOffset = y * context.bytesPerRow + x * 4
                let value = visited[y * width + x]
                outputBytes[outputOffset] = value
                outputBytes[outputOffset + 1] = value
                outputBytes[outputOffset + 2] = value
                outputBytes[outputOffset + 3] = 255
            }
        }

        return pngData(from: context)
    }

    func alphaMaskData(imageData: Data, canvasSize: CGSize, dilationRadius: Int = 0) -> Data? {
        guard let source = cgImage(from: imageData),
              let sourceProvider = source.dataProvider?.data,
              let sourceBytes = CFDataGetBytePtr(sourceProvider),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = min(source.width, Int(canvasSize.width.rounded(.down)))
        let height = min(source.height, Int(canvasSize.height.rounded(.down)))
        guard width > 0, height > 0 else { return nil }

        var binaryMask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let sourceOffset = y * source.bytesPerRow + x * 4
                binaryMask[y * width + x] = sourceBytes[sourceOffset + 3] > 10 ? 255 : 0
            }
        }

        if dilationRadius > 0 {
            binaryMask = dilatedBinaryMask(binaryMask, width: width, height: height, radius: dilationRadius)
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        for y in 0..<height {
            for x in 0..<width {
                let outputOffset = y * context.bytesPerRow + x * 4
                let value = binaryMask[y * width + x]
                outputBytes[outputOffset] = value
                outputBytes[outputOffset + 1] = value
                outputBytes[outputOffset + 2] = value
                outputBytes[outputOffset + 3] = 255
            }
        }

        return pngData(from: context)
    }

    func dilatedMaskData(maskData: Data, canvasSize: CGSize, dilationRadius: Int) -> Data? {
        guard let source = cgImage(from: maskData),
              let sourceProvider = source.dataProvider?.data,
              let sourceBytes = CFDataGetBytePtr(sourceProvider),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = min(source.width, Int(canvasSize.width.rounded(.down)))
        let height = min(source.height, Int(canvasSize.height.rounded(.down)))
        guard width > 0, height > 0 else { return nil }

        var binaryMask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let sourceOffset = y * source.bytesPerRow + x * 4
                let value = max(sourceBytes[sourceOffset], max(sourceBytes[sourceOffset + 1], sourceBytes[sourceOffset + 2]))
                binaryMask[y * width + x] = value > 10 ? 255 : 0
            }
        }

        if dilationRadius > 0 {
            binaryMask = dilatedBinaryMask(binaryMask, width: width, height: height, radius: dilationRadius)
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        for y in 0..<height {
            for x in 0..<width {
                let outputOffset = y * context.bytesPerRow + x * 4
                let value = binaryMask[y * width + x]
                outputBytes[outputOffset] = value
                outputBytes[outputOffset + 1] = value
                outputBytes[outputOffset + 2] = value
                outputBytes[outputOffset + 3] = 255
            }
        }

        return pngData(from: context)
    }

    func differenceMaskData(
        baseData: Data,
        generatedData: Data,
        canvasSize: CGSize,
        threshold: Double = 0.075,
        dilationRadius: Int = 4
    ) -> Data? {
        guard let base = cgImage(from: baseData),
              let generated = cgImage(from: generatedData),
              let baseProvider = base.dataProvider?.data,
              let generatedProvider = generated.dataProvider?.data,
              let baseBytes = CFDataGetBytePtr(baseProvider),
              let generatedBytes = CFDataGetBytePtr(generatedProvider),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = min(base.width, generated.width, Int(canvasSize.width.rounded(.down)))
        let height = min(base.height, generated.height, Int(canvasSize.height.rounded(.down)))
        guard width > 0, height > 0 else { return nil }

        var binaryMask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let baseOffset = y * base.bytesPerRow + x * 4
                let generatedOffset = y * generated.bytesPerRow + x * 4

                let baseSample = (
                    red: Double(baseBytes[baseOffset]) / 255.0,
                    green: Double(baseBytes[baseOffset + 1]) / 255.0,
                    blue: Double(baseBytes[baseOffset + 2]) / 255.0
                )
                let generatedSample = (
                    red: Double(generatedBytes[generatedOffset]) / 255.0,
                    green: Double(generatedBytes[generatedOffset + 1]) / 255.0,
                    blue: Double(generatedBytes[generatedOffset + 2]) / 255.0
                )
                let colorDelta = colorDistance(baseSample, generatedSample)
                let alphaDelta = abs(Double(baseBytes[baseOffset + 3]) - Double(generatedBytes[generatedOffset + 3])) / 255.0
                if colorDelta > threshold || alphaDelta > 0.05 {
                    binaryMask[y * width + x] = 255
                }
            }
        }

        if dilationRadius > 0 {
            binaryMask = dilatedBinaryMask(binaryMask, width: width, height: height, radius: dilationRadius)
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        for y in 0..<height {
            for x in 0..<width {
                let outputOffset = y * context.bytesPerRow + x * 4
                let value = binaryMask[y * width + x]
                outputBytes[outputOffset] = value
                outputBytes[outputOffset + 1] = value
                outputBytes[outputOffset + 2] = value
                outputBytes[outputOffset + 3] = 255
            }
        }

        return pngData(from: context)
    }

    func colorAlignedDifferenceMaskData(
        baseData: Data,
        generatedData: Data,
        referenceMaskData: Data?,
        canvasSize: CGSize,
        threshold: Double = 0.075,
        dilationRadius: Int = 4
    ) -> Data? {
        guard let base = cgImage(from: baseData),
              let generated = cgImage(from: generatedData),
              let baseProvider = base.dataProvider?.data,
              let generatedProvider = generated.dataProvider?.data,
              let baseBytes = CFDataGetBytePtr(baseProvider),
              let generatedBytes = CFDataGetBytePtr(generatedProvider),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let referenceMask = referenceMaskData.flatMap(cgImage(from:))
        let referenceBytes = referenceMask.flatMap { $0.dataProvider?.data }.flatMap(CFDataGetBytePtr)

        let width = min(base.width, generated.width, Int(canvasSize.width.rounded(.down)))
        let height = min(base.height, generated.height, Int(canvasSize.height.rounded(.down)))
        guard width > 0, height > 0 else { return nil }

        var baseTotals = (red: 0.0, green: 0.0, blue: 0.0)
        var generatedTotals = (red: 0.0, green: 0.0, blue: 0.0)
        var sampleCount = 0

        for y in 0..<height {
            for x in 0..<width {
                let baseOffset = y * base.bytesPerRow + x * 4
                let generatedOffset = y * generated.bytesPerRow + x * 4

                let useSample: Bool
                if let referenceMask, let referenceBytes {
                    let maskOffset = y * referenceMask.bytesPerRow + x * 4
                    let maskValue = max(referenceBytes[maskOffset], max(referenceBytes[maskOffset + 1], referenceBytes[maskOffset + 2]))
                    useSample = maskValue > 0
                } else {
                    useSample = true
                }

                guard useSample else { continue }
                guard baseBytes[baseOffset + 3] > 0 || generatedBytes[generatedOffset + 3] > 0 else { continue }

                baseTotals.red += Double(baseBytes[baseOffset]) / 255.0
                baseTotals.green += Double(baseBytes[baseOffset + 1]) / 255.0
                baseTotals.blue += Double(baseBytes[baseOffset + 2]) / 255.0

                generatedTotals.red += Double(generatedBytes[generatedOffset]) / 255.0
                generatedTotals.green += Double(generatedBytes[generatedOffset + 1]) / 255.0
                generatedTotals.blue += Double(generatedBytes[generatedOffset + 2]) / 255.0
                sampleCount += 1
            }
        }

        let colorOffset: (red: Double, green: Double, blue: Double)
        if sampleCount > 0 {
            let sampleFactor = 1.0 / Double(sampleCount)
            colorOffset = (
                generatedTotals.red * sampleFactor - baseTotals.red * sampleFactor,
                generatedTotals.green * sampleFactor - baseTotals.green * sampleFactor,
                generatedTotals.blue * sampleFactor - baseTotals.blue * sampleFactor
            )
        } else {
            colorOffset = (0, 0, 0)
        }

        var binaryMask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let baseOffset = y * base.bytesPerRow + x * 4
                let generatedOffset = y * generated.bytesPerRow + x * 4
                let isProtectedReferencePixel: Bool
                if let referenceMask, let referenceBytes {
                    let maskOffset = y * referenceMask.bytesPerRow + x * 4
                    let maskValue = max(referenceBytes[maskOffset], max(referenceBytes[maskOffset + 1], referenceBytes[maskOffset + 2]))
                    isProtectedReferencePixel = maskValue > 0
                } else {
                    isProtectedReferencePixel = false
                }

                if isProtectedReferencePixel {
                    binaryMask[y * width + x] = 0
                    continue
                }

                let baseSample = (
                    red: Double(baseBytes[baseOffset]) / 255.0,
                    green: Double(baseBytes[baseOffset + 1]) / 255.0,
                    blue: Double(baseBytes[baseOffset + 2]) / 255.0
                )
                let alignedGeneratedSample = (
                    red: clamp(Double(generatedBytes[generatedOffset]) / 255.0 - colorOffset.red),
                    green: clamp(Double(generatedBytes[generatedOffset + 1]) / 255.0 - colorOffset.green),
                    blue: clamp(Double(generatedBytes[generatedOffset + 2]) / 255.0 - colorOffset.blue)
                )
                let colorDelta = colorDistance(baseSample, alignedGeneratedSample)
                let alphaDelta = abs(Double(baseBytes[baseOffset + 3]) - Double(generatedBytes[generatedOffset + 3])) / 255.0
                if colorDelta > threshold || alphaDelta > 0.05 {
                    binaryMask[y * width + x] = 255
                }
            }
        }

        if dilationRadius > 0 {
            binaryMask = dilatedBinaryMask(binaryMask, width: width, height: height, radius: dilationRadius)
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        for y in 0..<height {
            for x in 0..<width {
                let outputOffset = y * context.bytesPerRow + x * 4
                let value = binaryMask[y * width + x]
                outputBytes[outputOffset] = value
                outputBytes[outputOffset + 1] = value
                outputBytes[outputOffset + 2] = value
                outputBytes[outputOffset + 3] = 255
            }
        }

        return pngData(from: context)
    }

    func boundingBox(forMaskData maskData: Data, threshold: UInt8 = 10) -> CGRect? {
        guard let mask = cgImage(from: maskData),
              let maskDataProvider = mask.dataProvider?.data,
              let maskBytes = CFDataGetBytePtr(maskDataProvider) else {
            return nil
        }

        var minX = mask.width
        var minY = mask.height
        var maxX = -1
        var maxY = -1

        for y in 0..<mask.height {
            for x in 0..<mask.width {
                let offset = y * mask.bytesPerRow + x * 4
                let value = max(maskBytes[offset], max(maskBytes[offset + 1], maskBytes[offset + 2]))
                guard value > threshold else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )
    }

    func expandedROIRect(for boundingBox: CGRect, paddingFraction: CGFloat, canvasSize: CGSize) -> CGRect {
        let paddingX = max((boundingBox.width * paddingFraction).rounded(.up), 1)
        let paddingY = max((boundingBox.height * paddingFraction).rounded(.up), 1)
        let expanded = boundingBox.insetBy(dx: -paddingX, dy: -paddingY)
        let clamped = expanded.intersection(CGRect(origin: .zero, size: canvasSize))
        return CGRect(
            x: floor(clamped.origin.x),
            y: floor(clamped.origin.y),
            width: max(1, ceil(clamped.size.width)),
            height: max(1, ceil(clamped.size.height))
        )
    }

    func croppedImageData(_ data: Data, rect: CGRect) -> Data? {
        guard let source = cgImage(from: data),
              let sourceData = source.dataProvider?.data,
              let sourceBytes = CFDataGetBytePtr(sourceData) else {
            return nil
        }

        let pixelRect = CGRect(
            x: max(0, floor(rect.origin.x)),
            y: max(0, floor(rect.origin.y)),
            width: max(1, ceil(rect.size.width)),
            height: max(1, ceil(rect.size.height))
        ).intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let context = makeContext(size: pixelRect.size),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: pixelRect.size))
        let originX = Int(pixelRect.origin.x)
        let originY = Int(pixelRect.origin.y)
        let width = Int(pixelRect.width)
        let height = Int(pixelRect.height)

        for y in 0..<height {
            for x in 0..<width {
                let sourceOffset = (originY + y) * source.bytesPerRow + (originX + x) * 4
                let outputOffset = y * context.bytesPerRow + x * 4
                outputBytes[outputOffset] = sourceBytes[sourceOffset]
                outputBytes[outputOffset + 1] = sourceBytes[sourceOffset + 1]
                outputBytes[outputOffset + 2] = sourceBytes[sourceOffset + 2]
                outputBytes[outputOffset + 3] = sourceBytes[sourceOffset + 3]
            }
        }

        return pngData(from: context)
    }

    func resizedImageData(_ data: Data, size: CGSize) -> Data? {
        guard let source = cgImage(from: data),
              let context = makeContext(size: size) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: size))
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(origin: .zero, size: size))
        return pngData(from: context)
    }

    func blendedImageData(baseData: Data, generatedData: Data, maskData: Data, canvasSize: CGSize) -> Data? {
        guard let base = cgImage(from: baseData),
              let generated = cgImage(from: generatedData),
              let mask = cgImage(from: maskData),
              let baseProvider = base.dataProvider?.data,
              let generatedProvider = generated.dataProvider?.data,
              let maskProvider = mask.dataProvider?.data,
              let baseBytes = CFDataGetBytePtr(baseProvider),
              let generatedBytes = CFDataGetBytePtr(generatedProvider),
              let maskBytes = CFDataGetBytePtr(maskProvider),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = min(base.width, generated.width, mask.width, Int(canvasSize.width.rounded(.down)))
        let height = min(base.height, generated.height, mask.height, Int(canvasSize.height.rounded(.down)))

        context.clear(CGRect(origin: .zero, size: canvasSize))
        for y in 0..<height {
            for x in 0..<width {
                let baseOffset = y * base.bytesPerRow + x * 4
                let generatedOffset = y * generated.bytesPerRow + x * 4
                let maskOffset = y * mask.bytesPerRow + x * 4
                let outputOffset = y * context.bytesPerRow + x * 4

                let maskValue = Double(max(maskBytes[maskOffset], max(maskBytes[maskOffset + 1], maskBytes[maskOffset + 2]))) / 255.0
                for channel in 0..<4 {
                    let baseValue = Double(baseBytes[baseOffset + channel])
                    let generatedValue = Double(generatedBytes[generatedOffset + channel])
                    let blended = baseValue * (1.0 - maskValue) + generatedValue * maskValue
                    outputBytes[outputOffset + channel] = UInt8(min(max(blended.rounded(), 0), 255))
                }
            }
        }

        return pngData(from: context)
    }

    func reinsertCropData(_ cropData: Data, roiRect: CGRect, canvasSize: CGSize) -> Data? {
        guard let crop = cgImage(from: cropData),
              let cropProvider = crop.dataProvider?.data,
              let cropBytes = CFDataGetBytePtr(cropProvider),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        let originX = max(0, Int(floor(roiRect.origin.x)))
        let originY = max(0, Int(floor(roiRect.origin.y)))
        let maxWidth = max(0, Int(canvasSize.width.rounded(.down)) - originX)
        let maxHeight = max(0, Int(canvasSize.height.rounded(.down)) - originY)
        let width = min(crop.width, maxWidth)
        let height = min(crop.height, maxHeight)
        guard width > 0, height > 0 else { return pngData(from: context) }

        for y in 0..<height {
            for x in 0..<width {
                let cropOffset = y * crop.bytesPerRow + x * 4
                let outputOffset = (originY + y) * context.bytesPerRow + (originX + x) * 4
                outputBytes[outputOffset] = cropBytes[cropOffset]
                outputBytes[outputOffset + 1] = cropBytes[cropOffset + 1]
                outputBytes[outputOffset + 2] = cropBytes[cropOffset + 2]
                outputBytes[outputOffset + 3] = cropBytes[cropOffset + 3]
            }
        }

        return pngData(from: context)
    }

    func subtractProtectedPixels(
        imageData: Data,
        protectMaskData: Data,
        canvasSize: CGSize
    ) -> Data? {
        guard let source = cgImage(from: imageData),
              let protectMask = cgImage(from: protectMaskData),
              let sourceProvider = source.dataProvider?.data,
              let protectProvider = protectMask.dataProvider?.data,
              let sourceBytes = CFDataGetBytePtr(sourceProvider),
              let protectBytes = CFDataGetBytePtr(protectProvider),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = min(source.width, protectMask.width, Int(canvasSize.width.rounded(.down)))
        let height = min(source.height, protectMask.height, Int(canvasSize.height.rounded(.down)))

        context.clear(CGRect(origin: .zero, size: canvasSize))
        for y in 0..<height {
            for x in 0..<width {
                let sourceOffset = y * source.bytesPerRow + x * 4
                let maskOffset = y * protectMask.bytesPerRow + x * 4
                let outputOffset = y * context.bytesPerRow + x * 4

                let protectValue = Double(
                    max(protectBytes[maskOffset], max(protectBytes[maskOffset + 1], protectBytes[maskOffset + 2]))
                ) / 255.0
                let keepAlpha = 1.0 - protectValue

                guard keepAlpha > 0.001 else {
                    outputBytes[outputOffset] = 0
                    outputBytes[outputOffset + 1] = 0
                    outputBytes[outputOffset + 2] = 0
                    outputBytes[outputOffset + 3] = 0
                    continue
                }

                outputBytes[outputOffset] = sourceBytes[sourceOffset]
                outputBytes[outputOffset + 1] = sourceBytes[sourceOffset + 1]
                outputBytes[outputOffset + 2] = sourceBytes[sourceOffset + 2]
                let sourceAlpha = Double(sourceBytes[sourceOffset + 3]) / 255.0
                let finalAlpha = clamp(sourceAlpha * keepAlpha)
                outputBytes[outputOffset + 3] = UInt8((finalAlpha * 255.0).rounded())
            }
        }

        return pngData(from: context)
    }

    func floodFillData(
        imageData: Data?,
        canvasSize: CGSize,
        startPoint: ConceptPoint,
        fillColor: ConceptRGBAColor,
        opacity: Double,
        tolerance: UInt8 = 12
    ) -> Data? {
        guard let baseData = imageData ?? transparentPNGData(canvasSize: canvasSize),
              let source = cgImage(from: baseData),
              let context = makeContext(size: canvasSize),
              let sourceData = source.dataProvider?.data,
              let sourceBytes = CFDataGetBytePtr(sourceData),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = min(source.width, Int(canvasSize.width.rounded(.down)))
        let height = min(source.height, Int(canvasSize.height.rounded(.down)))
        guard width > 0, height > 0 else { return nil }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        for y in 0..<height {
            let sourceRow = y * source.bytesPerRow
            let outputRow = y * context.bytesPerRow
            for x in 0..<width {
                let sourceOffset = sourceRow + x * 4
                let outputOffset = outputRow + x * 4
                outputBytes[outputOffset] = sourceBytes[sourceOffset]
                outputBytes[outputOffset + 1] = sourceBytes[sourceOffset + 1]
                outputBytes[outputOffset + 2] = sourceBytes[sourceOffset + 2]
                outputBytes[outputOffset + 3] = sourceBytes[sourceOffset + 3]
            }
        }

        let startX = min(max(Int((startPoint.x * Double(width)).rounded(.down)), 0), width - 1)
        let startY = min(max(Int((startPoint.y * Double(height)).rounded(.down)), 0), height - 1)
        let startOffset = startY * context.bytesPerRow + startX * 4
        let target = (
            outputBytes[startOffset],
            outputBytes[startOffset + 1],
            outputBytes[startOffset + 2],
            outputBytes[startOffset + 3]
        )
        let replacement = (
            UInt8(max(0, min(255, Int((fillColor.red * 255).rounded())))),
            UInt8(max(0, min(255, Int((fillColor.green * 255).rounded())))),
            UInt8(max(0, min(255, Int((fillColor.blue * 255).rounded())))),
            UInt8(max(0, min(255, Int((fillColor.alpha * opacity * 255).rounded()))))
        )

        guard target != replacement else {
            return pngData(from: context)
        }

        var visited = [UInt8](repeating: 0, count: width * height)
        var queue: [(Int, Int)] = [(startX, startY)]
        var queueIndex = 0

        func matchesTarget(_ x: Int, _ y: Int) -> Bool {
            let offset = y * context.bytesPerRow + x * 4
            return abs(Int(outputBytes[offset]) - Int(target.0)) <= Int(tolerance)
                && abs(Int(outputBytes[offset + 1]) - Int(target.1)) <= Int(tolerance)
                && abs(Int(outputBytes[offset + 2]) - Int(target.2)) <= Int(tolerance)
                && abs(Int(outputBytes[offset + 3]) - Int(target.3)) <= Int(tolerance)
        }

        while queueIndex < queue.count {
            let (x, y) = queue[queueIndex]
            queueIndex += 1

            guard x >= 0, x < width, y >= 0, y < height else { continue }
            let visitIndex = y * width + x
            guard visited[visitIndex] == 0 else { continue }
            visited[visitIndex] = 1

            guard matchesTarget(x, y) else { continue }

            let offset = y * context.bytesPerRow + x * 4
            outputBytes[offset] = replacement.0
            outputBytes[offset + 1] = replacement.1
            outputBytes[offset + 2] = replacement.2
            outputBytes[offset + 3] = replacement.3

            queue.append((x + 1, y))
            queue.append((x - 1, y))
            queue.append((x, y + 1))
            queue.append((x, y - 1))
        }

        return pngData(from: context)
    }

    func maskedPatchData(imageData: Data, maskData: Data, canvasSize: CGSize) -> Data? {
        guard let normalizedSourceData = normalizedImportedImageData(imageData, canvasSize: canvasSize),
              let source = cgImage(from: normalizedSourceData),
              let mask = cgImage(from: maskData),
              let sourceData = source.dataProvider?.data,
              let sourceBytes = CFDataGetBytePtr(sourceData),
              let maskDataProvider = mask.dataProvider?.data,
              let maskBytes = CFDataGetBytePtr(maskDataProvider),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        let width = min(source.width, mask.width, Int(canvasSize.width.rounded(.down)))
        let height = min(source.height, mask.height, Int(canvasSize.height.rounded(.down)))

        for y in 0..<height {
            for x in 0..<width {
                let sourceOffset = y * source.bytesPerRow + x * 4
                let maskOffset = y * mask.bytesPerRow + x * 4
                let outputOffset = y * context.bytesPerRow + x * 4

                let maskValue = max(maskBytes[maskOffset], max(maskBytes[maskOffset + 1], maskBytes[maskOffset + 2]))
                if maskValue == 0 {
                    outputBytes[outputOffset] = 0
                    outputBytes[outputOffset + 1] = 0
                    outputBytes[outputOffset + 2] = 0
                    outputBytes[outputOffset + 3] = 0
                    continue
                }

                outputBytes[outputOffset] = sourceBytes[sourceOffset]
                outputBytes[outputOffset + 1] = sourceBytes[sourceOffset + 1]
                outputBytes[outputOffset + 2] = sourceBytes[sourceOffset + 2]
                let sourceAlpha = UInt16(sourceBytes[sourceOffset + 3])
                let maskedAlpha = (sourceAlpha * UInt16(maskValue)) / 255
                outputBytes[outputOffset + 3] = UInt8(maskedAlpha)
            }
        }

        return pngData(from: context)
    }

    private func draw(stroke: ConceptStroke, in context: CGContext, canvasSize: CGSize) {
        guard stroke.points.count >= 2 else { return }
        let converted = stroke.points.map {
            CGPoint(
                x: CGFloat($0.x) * canvasSize.width,
                y: (1 - CGFloat($0.y)) * canvasSize.height
            )
        }
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(CGFloat(stroke.width))
        if stroke.tool == .eraser {
            context.setBlendMode(.clear)
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        } else {
            context.setBlendMode(.normal)
            context.setStrokeColor(CGColor(
                red: stroke.color.red,
                green: stroke.color.green,
                blue: stroke.color.blue,
                alpha: stroke.color.alpha * stroke.opacity
            ))
        }
        context.beginPath()
        context.addLines(between: converted)
        context.strokePath()
        context.restoreGState()
    }

    private func makeContext(size: CGSize) -> CGContext? {
        let width = Int(max(size.width.rounded(), 1))
        let height = Int(max(size.height.rounded(), 1))
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private func pngData(from context: CGContext) -> Data? {
        guard let image = context.makeImage() else { return nil }
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutable as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutable as Data
    }

    private func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func aspectFitRect(for sourceSize: CGSize, in targetRect: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return targetRect }
        let scale = min(targetRect.width / sourceSize.width, targetRect.height / sourceSize.height)
        let fittedSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: targetRect.midX - fittedSize.width / 2,
            y: targetRect.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func transparentPNGData(canvasSize: CGSize) -> Data? {
        guard let context = makeContext(size: canvasSize) else { return nil }
        context.clear(CGRect(origin: .zero, size: canvasSize))
        return pngData(from: context)
    }

    private func removeBorderConnectedWhiteBackgroundData(_ data: Data, canvasSize: CGSize) -> Data? {
        guard let normalizedData = normalizedImportedImageData(data, canvasSize: canvasSize),
              let source = cgImage(from: normalizedData),
              let sourceData = source.dataProvider?.data,
              let sourceBytes = CFDataGetBytePtr(sourceData),
              let context = makeContext(size: canvasSize),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }

        func pixel(atX x: Int, y: Int) -> (red: Double, green: Double, blue: Double) {
            let offset = y * source.bytesPerRow + x * 4
            return (
                red: Double(sourceBytes[offset]) / 255.0,
                green: Double(sourceBytes[offset + 1]) / 255.0,
                blue: Double(sourceBytes[offset + 2]) / 255.0
            )
        }

        var whiteBorderPixels = [(red: Double, green: Double, blue: Double)]()
        whiteBorderPixels.reserveCapacity((width + height) * 2)
        var totalBorderSamples = 0

        for x in 0..<width {
            for y in [0, height - 1] {
                totalBorderSamples += 1
                let sample = pixel(atX: x, y: y)
                if isNearWhite(sample, distanceThreshold: 0.12, minimumBrightness: 0.88) {
                    whiteBorderPixels.append(sample)
                }
            }
        }
        if height > 2 {
            for y in 1..<(height - 1) {
                for x in [0, width - 1] {
                    totalBorderSamples += 1
                    let sample = pixel(atX: x, y: y)
                    if isNearWhite(sample, distanceThreshold: 0.12, minimumBrightness: 0.88) {
                        whiteBorderPixels.append(sample)
                    }
                }
            }
        }

        guard totalBorderSamples > 0 else { return nil }
        let whiteBorderRatio = Double(whiteBorderPixels.count) / Double(totalBorderSamples)
        guard whiteBorderRatio >= 0.72 else { return nil }

        let background = averageColor(whiteBorderPixels)
        var backgroundMask = [UInt8](repeating: 0, count: width * height)
        var queue = [(Int, Int)]()
        queue.reserveCapacity((width + height) * 2)

        func enqueueIfBackground(_ x: Int, _ y: Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let index = y * width + x
            guard backgroundMask[index] == 0 else { return }
            let sample = pixel(atX: x, y: y)
            if matchesBackground(sample, background: background, strict: true) {
                backgroundMask[index] = 1
                queue.append((x, y))
            }
        }

        for x in 0..<width {
            enqueueIfBackground(x, 0)
            enqueueIfBackground(x, height - 1)
        }
        if height > 2 {
            for y in 1..<(height - 1) {
                enqueueIfBackground(0, y)
                enqueueIfBackground(width - 1, y)
            }
        }

        var queueIndex = 0
        while queueIndex < queue.count {
            let (x, y) = queue[queueIndex]
            queueIndex += 1

            let neighbors = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
            for (nextX, nextY) in neighbors {
                guard nextX >= 0, nextX < width, nextY >= 0, nextY < height else { continue }
                let index = nextY * width + nextX
                guard backgroundMask[index] == 0 else { continue }
                let sample = pixel(atX: nextX, y: nextY)
                if matchesBackground(sample, background: background, strict: true) {
                    backgroundMask[index] = 1
                    queue.append((nextX, nextY))
                }
            }
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let outputBytesPerRow = context.bytesPerRow

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let sourceOffset = y * source.bytesPerRow + x * 4
                let outputOffset = y * outputBytesPerRow + x * 4

                if backgroundMask[index] == 1 {
                    outputBytes[outputOffset] = 0
                    outputBytes[outputOffset + 1] = 0
                    outputBytes[outputOffset + 2] = 0
                    outputBytes[outputOffset + 3] = 0
                    continue
                }

                let sample = pixel(atX: x, y: y)
                let originalAlpha = Double(sourceBytes[sourceOffset + 3]) / 255.0
                let edgeBackground = hasBackgroundNeighbor(backgroundMask, width: width, height: height, x: x, y: y)
                var alpha = originalAlpha

                if edgeBackground {
                    let distance = colorDistance(sample, background)
                    if distance < 0.02 {
                        alpha = 0
                    } else if distance < 0.16 {
                        alpha *= clamp((distance - 0.02) / 0.14)
                    }
                }

                guard alpha > 0.004 else {
                    outputBytes[outputOffset] = 0
                    outputBytes[outputOffset + 1] = 0
                    outputBytes[outputOffset + 2] = 0
                    outputBytes[outputOffset + 3] = 0
                    continue
                }

                let correctedRed = clamp((sample.red - background.red * (1.0 - alpha)) / alpha)
                let correctedGreen = clamp((sample.green - background.green * (1.0 - alpha)) / alpha)
                let correctedBlue = clamp((sample.blue - background.blue * (1.0 - alpha)) / alpha)

                outputBytes[outputOffset] = UInt8((correctedRed * 255.0).rounded())
                outputBytes[outputOffset + 1] = UInt8((correctedGreen * 255.0).rounded())
                outputBytes[outputOffset + 2] = UInt8((correctedBlue * 255.0).rounded())
                outputBytes[outputOffset + 3] = UInt8((alpha * 255.0).rounded())
            }
        }

        return pngData(from: context)
    }

    @available(macOS 14.0, *)
    private func removeBackgroundDataVision(_ data: Data, canvasSize: CGSize) throws -> Data {
        guard let normalizedData = normalizedImportedImageData(data, canvasSize: canvasSize),
              let image = cgImage(from: normalizedData) else {
            throw AppError.conceptBackgroundRemovalFailed("Failed to normalize layer image.")
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw AppError.conceptBackgroundRemovalFailed(error.localizedDescription)
        }

        guard let observation = request.results?.first else {
            throw AppError.conceptBackgroundRemovalFailed("No foreground subject detected.")
        }

        let instances = observation.allInstances
        guard !instances.isEmpty else {
            throw AppError.conceptBackgroundRemovalFailed("No foreground subject detected.")
        }

        let maskedPixelBuffer: CVPixelBuffer
        do {
            maskedPixelBuffer = try observation.generateMaskedImage(
                ofInstances: instances,
                from: handler,
                croppedToInstancesExtent: false
            )
        } catch {
            throw AppError.conceptBackgroundRemovalFailed(error.localizedDescription)
        }

        let outputImage = CIImage(cvPixelBuffer: maskedPixelBuffer)
        let extent = outputImage.extent.integral
        guard let cgImage = Self.ciContext.createCGImage(outputImage, from: extent) else {
            throw AppError.conceptBackgroundRemovalFailed("Failed to render foreground mask.")
        }

        guard let rawCutoutData = pngData(from: cgImage) else {
            throw AppError.conceptBackgroundRemovalFailed("Failed to encode PNG output.")
        }
        let decontaminatedData = removeWhiteBackgroundData(
            rawCutoutData,
            threshold: 0.012,
            softness: 0.05
        ) ?? rawCutoutData
        return refineForegroundEdgesData(decontaminatedData) ?? decontaminatedData
    }

    private func refineForegroundEdgesData(_ data: Data) -> Data? {
        guard let source = cgImage(from: data),
              let sourceData = source.dataProvider?.data,
              let sourceBytes = CFDataGetBytePtr(sourceData),
              let context = makeContext(size: CGSize(width: source.width, height: source.height)),
              let outputBytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let width = source.width
        let height = source.height
        let sourceBytesPerRow = source.bytesPerRow
        let outputBytesPerRow = context.bytesPerRow

        var alphaMap = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * sourceBytesPerRow + x * 4
                alphaMap[y * width + x] = sourceBytes[offset + 3]
            }
        }

        var erodedAlpha = alphaMap
        if width > 2, height > 2 {
            for y in 0..<height {
                for x in 0..<width {
                    var minimum = alphaMap[y * width + x]
                    for sampleY in max(0, y - 1)...min(height - 1, y + 1) {
                        for sampleX in max(0, x - 1)...min(width - 1, x + 1) {
                            minimum = min(minimum, alphaMap[sampleY * width + sampleX])
                        }
                    }
                    erodedAlpha[y * width + x] = minimum
                }
            }
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        for y in 0..<height {
            for x in 0..<width {
                let sourceOffset = y * sourceBytesPerRow + x * 4
                let outputOffset = y * outputBytesPerRow + x * 4

                let originalAlpha = alphaMap[y * width + x]
                let refinedAlpha = UInt8((UInt16(originalAlpha) + UInt16(erodedAlpha[y * width + x])) / 2)
                guard refinedAlpha >= 6 else {
                    outputBytes[outputOffset] = 0
                    outputBytes[outputOffset + 1] = 0
                    outputBytes[outputOffset + 2] = 0
                    outputBytes[outputOffset + 3] = 0
                    continue
                }

                let alpha = max(Double(refinedAlpha) / 255.0, 0.001)
                let red = Double(sourceBytes[sourceOffset]) / 255.0
                let green = Double(sourceBytes[sourceOffset + 1]) / 255.0
                let blue = Double(sourceBytes[sourceOffset + 2]) / 255.0
                let shouldDecontaminate = originalAlpha < 250

                let correctedRed = shouldDecontaminate ? clamp((red - (1.0 - alpha)) / alpha) : red
                let correctedGreen = shouldDecontaminate ? clamp((green - (1.0 - alpha)) / alpha) : green
                let correctedBlue = shouldDecontaminate ? clamp((blue - (1.0 - alpha)) / alpha) : blue

                outputBytes[outputOffset] = UInt8((correctedRed * 255.0).rounded())
                outputBytes[outputOffset + 1] = UInt8((correctedGreen * 255.0).rounded())
                outputBytes[outputOffset + 2] = UInt8((correctedBlue * 255.0).rounded())
                outputBytes[outputOffset + 3] = refinedAlpha
            }
        }

        return pngData(from: context)
    }

    private static let ciContext = CIContext(options: [
        .cacheIntermediates: false
    ])

    private func pngData(from image: CGImage) -> Data? {
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutable as Data
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func isNearWhite(_ color: (red: Double, green: Double, blue: Double), distanceThreshold: Double, minimumBrightness: Double) -> Bool {
        colorDistance(color, (1, 1, 1)) <= distanceThreshold
            && max(color.red, max(color.green, color.blue)) >= minimumBrightness
    }

    private func averageColor(_ colors: [(red: Double, green: Double, blue: Double)]) -> (red: Double, green: Double, blue: Double) {
        guard !colors.isEmpty else { return (1, 1, 1) }
        let totals = colors.reduce(into: (red: 0.0, green: 0.0, blue: 0.0)) { partial, color in
            partial.red += color.red
            partial.green += color.green
            partial.blue += color.blue
        }
        let count = Double(colors.count)
        return (totals.red / count, totals.green / count, totals.blue / count)
    }

    private func colorDistance(_ lhs: (red: Double, green: Double, blue: Double), _ rhs: (red: Double, green: Double, blue: Double)) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        return sqrt(red * red + green * green + blue * blue)
    }

    private func matchesBackground(
        _ color: (red: Double, green: Double, blue: Double),
        background: (red: Double, green: Double, blue: Double),
        strict: Bool
    ) -> Bool {
        let distance = colorDistance(color, background)
        let brightness = max(color.red, max(color.green, color.blue))
        let minChannel = min(color.red, min(color.green, color.blue))
        let saturation = brightness - minChannel
        if strict {
            return distance <= 0.14 && brightness >= 0.84 && saturation <= 0.18
        }
        return distance <= 0.20 && brightness >= 0.78 && saturation <= 0.24
    }

    private func hasBackgroundNeighbor(_ mask: [UInt8], width: Int, height: Int, x: Int, y: Int) -> Bool {
        for sampleY in max(0, y - 1)...min(height - 1, y + 1) {
            for sampleX in max(0, x - 1)...min(width - 1, x + 1) {
                if sampleX == x && sampleY == y { continue }
                if mask[sampleY * width + sampleX] == 1 {
                    return true
                }
            }
        }
        return false
    }

    private func dilatedBinaryMask(_ source: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        guard radius > 0, width > 0, height > 0 else { return source }
        var output = source

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard source[index] == 0 else {
                    output[index] = 255
                    continue
                }

                var isForeground = false
                for sampleY in max(0, y - radius)...min(height - 1, y + radius) {
                    for sampleX in max(0, x - radius)...min(width - 1, x + radius) {
                        if source[sampleY * width + sampleX] > 0 {
                            isForeground = true
                            break
                        }
                    }
                    if isForeground { break }
                }
                output[index] = isForeground ? 255 : 0
            }
        }

        return output
    }

}
