import Foundation

enum GenerationCostRegistry {
    static func estimate(
        provider: ModelProvider,
        model: String,
        resolution: ImageResolution,
        imageCount: Int
    ) -> GenerationCostEstimate {
        let apiModel = ModelProvider.apiModelName(from: model)
        let boundedCount = max(imageCount, 1)

        switch provider {
        case .gemini:
            if let perImage = geminiUSDPerImage(model: apiModel, resolution: resolution) {
                return usdEstimate(
                    provider: provider,
                    model: apiModel,
                    resolution: resolution,
                    imageCount: boundedCount,
                    perImage: perImage,
                    note: nil
                )
            }
        case .openAI:
            if let perImage = openAIUSDPerImage(model: apiModel, resolution: resolution) {
                return usdEstimate(
                    provider: provider,
                    model: apiModel,
                    resolution: resolution,
                    imageCount: boundedCount,
                    perImage: perImage,
                    note: nil
                )
            }
        case .openAICompatible:
            if let perImage = openAIUSDPerImage(model: apiModel, resolution: resolution)
                ?? geminiUSDPerImage(model: apiModel, resolution: resolution) {
                return usdEstimate(
                    provider: provider,
                    model: apiModel,
                    resolution: resolution,
                    imageCount: boundedCount,
                    perImage: perImage,
                    note: "gateway"
                )
            }
        case .kie:
            if let perImageCredits = kieCreditsPerImage(model: apiModel, resolution: resolution) {
                return GenerationCostEstimate(
                    provider: provider,
                    model: apiModel,
                    resolution: resolution,
                    imageCount: boundedCount,
                    unit: .kieCredits,
                    perImage: perImageCredits,
                    total: perImageCredits * Double(boundedCount),
                    confidence: .estimated,
                    note: nil
                )
            }
        }

        return GenerationCostEstimate(
            provider: provider,
            model: apiModel,
            resolution: resolution,
            imageCount: boundedCount,
            unit: .unknown,
            perImage: nil,
            total: nil,
            confidence: .unavailable,
            note: nil
        )
    }

    static func actualKieCredits(
        model: String,
        resolution: ImageResolution,
        imageCount: Int,
        totalCredits: Double
    ) -> GenerationCostEstimate {
        let boundedCount = max(imageCount, 1)
        return GenerationCostEstimate(
            provider: .kie,
            model: ModelProvider.apiModelName(from: model),
            resolution: resolution,
            imageCount: boundedCount,
            unit: .kieCredits,
            perImage: totalCredits / Double(boundedCount),
            total: totalCredits,
            confidence: .actual,
            note: nil
        )
    }

    static func combinedActualCost(
        from images: [GeneratedImageResult],
        fallback: GenerationCostEstimate
    ) -> GenerationCostEstimate? {
        let costs = images.compactMap(\.cost)
        guard !costs.isEmpty,
              costs.allSatisfy({ $0.unit == costs[0].unit && $0.provider == costs[0].provider }),
              let total = costs.map(\.total).compactMap({ $0 }).nilIfEmpty?.reduce(0, +) else {
            return nil
        }

        return GenerationCostEstimate(
            provider: fallback.provider,
            model: fallback.model,
            resolution: fallback.resolution,
            imageCount: fallback.imageCount,
            unit: costs[0].unit,
            perImage: total / Double(max(fallback.imageCount, 1)),
            total: total,
            confidence: .actual,
            note: fallback.note
        )
    }

    static func perImageCost(from estimate: GenerationCostEstimate) -> GenerationCostEstimate? {
        guard estimate.confidence != .unavailable else {
            return nil
        }

        let imageCount = max(estimate.imageCount, 1)
        let perImage = estimate.perImage ?? estimate.total.map { $0 / Double(imageCount) }
        return GenerationCostEstimate(
            provider: estimate.provider,
            model: estimate.model,
            resolution: estimate.resolution,
            imageCount: 1,
            unit: estimate.unit,
            perImage: perImage,
            total: perImage,
            confidence: estimate.confidence,
            note: estimate.note
        )
    }

    static func compactDisplayText(
        for estimate: GenerationCostEstimate,
        language: AppLanguage,
        creditConversion: CreditCostConversion? = nil
    ) -> String {
        guard estimate.confidence != .unavailable,
              let total = estimate.total else {
            return language == .ru ? "недоступно" : "unavailable"
        }

        return valueText(for: estimate, total: total, language: language, creditConversion: creditConversion)
    }

    static func displayText(
        for estimate: GenerationCostEstimate,
        language: AppLanguage,
        creditConversion: CreditCostConversion? = nil
    ) -> String {
        switch estimate.confidence {
        case .unavailable:
            return language == .ru
                ? "Стоимость недоступна для этой модели"
                : "Cost unavailable for this model"
        case .estimated, .actual:
            guard let total = estimate.total else {
                return language == .ru
                    ? "Стоимость недоступна для этой модели"
                    : "Cost unavailable for this model"
            }

            let prefix: String
            if language == .ru {
                prefix = estimate.confidence == .actual ? "Факт" : "Оценка"
            } else {
                prefix = estimate.confidence == .actual ? "Actual" : "Estimate"
            }

            let value = valueText(for: estimate, total: total, language: language, creditConversion: creditConversion)
            let images = language == .ru
                ? "за \(estimate.imageCount) изображ."
                : "for \(estimate.imageCount) image(s)"
            let note = estimate.note == "gateway"
                ? (language == .ru ? " · тариф шлюза может отличаться" : " · gateway pricing may differ")
                : ""
            return "\(prefix): \(value) \(images)\(note)"
        }
    }

    private static func valueText(
        for estimate: GenerationCostEstimate,
        total: Double,
        language: AppLanguage,
        creditConversion: CreditCostConversion?
    ) -> String {
        let isActual = estimate.confidence == .actual
        switch estimate.unit {
        case .usd:
            return "\(isActual ? "" : "~")$\(formatUSD(total))"
        case .kieCredits:
            let credits = "\(isActual ? "" : "~")\(formatCredits(total)) Kie credits"
            guard let converted = creditConversion?.formattedApproximateAmount(forCredits: total) else {
                return credits
            }
            return "\(credits) (\(converted))"
        case .unknown:
            return language == .ru ? "недоступно" : "unavailable"
        }
    }

    private static func usdEstimate(
        provider: ModelProvider,
        model: String,
        resolution: ImageResolution,
        imageCount: Int,
        perImage: Double,
        note: String?
    ) -> GenerationCostEstimate {
        GenerationCostEstimate(
            provider: provider,
            model: model,
            resolution: resolution,
            imageCount: imageCount,
            unit: .usd,
            perImage: perImage,
            total: perImage * Double(imageCount),
            confidence: .estimated,
            note: note
        )
    }

    private static func geminiUSDPerImage(model: String, resolution: ImageResolution) -> Double? {
        let normalized = model.lowercased()
        if normalized.contains("nano-banana-pro") || normalized.contains("gemini-3-pro-image") {
            return resolution == .k4 ? 0.24 : 0.134
        }
        if normalized.contains("nano-banana") || normalized.contains("gemini-2.5-flash-image") {
            return 0.039
        }
        return nil
    }

    private static func openAIUSDPerImage(model: String, resolution: ImageResolution) -> Double? {
        let normalized = model.lowercased()
        guard normalized.hasPrefix("gpt-image") else {
            return nil
        }

        switch resolution {
        case .k1:
            return 0.06
        case .k2:
            return 0.12
        case .k4:
            return 0.25
        }
    }

    private static func kieCreditsPerImage(model: String, resolution: ImageResolution) -> Double? {
        let normalized = model.lowercased()
        if normalized.contains("upscale") {
            return resolution == .k4 ? 40 : 20
        }
        if normalized.contains("remove-background") {
            return 10
        }
        if normalized.contains("nano-banana-pro") || normalized.contains("nano-banana-2") || normalized.contains("gpt-image-2") {
            return resolution == .k4 ? 150 : 100
        }
        if normalized.contains("google/nano-banana") || normalized == "nano-banana" {
            return 30
        }
        if normalized.contains("flux-2/pro") {
            return 90
        }
        if normalized.contains("flux-2/flex") {
            return 60
        }
        if normalized.contains("seedream") || normalized.contains("qwen") || normalized.contains("wan") {
            return 50
        }
        return nil
    }

    private static func formatUSD(_ value: Double) -> String {
        if value < 0.01 {
            return String(format: "%.4f", value)
        }
        return String(format: "%.3f", value)
    }

    private static func formatCredits(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

private extension Array {
    var nilIfEmpty: [Element]? {
        isEmpty ? nil : self
    }
}
