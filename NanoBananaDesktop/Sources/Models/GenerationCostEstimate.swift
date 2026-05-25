import Foundation

enum GenerationCostUnit: String, Codable, Sendable {
    case usd
    case kieCredits
    case unknown
}

enum GenerationCostConfidence: String, Codable, Sendable {
    case estimated
    case actual
    case unavailable
}

enum CreditCostCurrency: String, Codable, CaseIterable, Identifiable, Sendable {
    case usd
    case eur
    case rub

    var id: String { rawValue }
    var code: String { rawValue.uppercased() }
    var localizationKey: String { "currency.\(rawValue)" }

    var symbol: String {
        switch self {
        case .usd:
            return "$"
        case .eur:
            return "EUR"
        case .rub:
            return "RUB"
        }
    }

    var usesLeadingSymbol: Bool {
        self == .usd
    }
}

struct CreditCostConversion: Equatable, Sendable {
    let currency: CreditCostCurrency
    let costPer100Credits: Double

    func convertedAmount(forCredits credits: Double) -> Double? {
        guard credits.isFinite,
              costPer100Credits.isFinite,
              costPer100Credits > 0 else {
            return nil
        }

        return credits * costPer100Credits / 100
    }

    func formattedApproximateAmount(forCredits credits: Double) -> String? {
        guard let amount = convertedAmount(forCredits: credits) else {
            return nil
        }
        return "~\(Self.formatCurrency(amount, currency: currency))"
    }

    static func formatCurrency(_ value: Double, currency: CreditCostCurrency) -> String {
        let absValue = abs(value)
        let fractionDigits = absValue >= 0.01 ? 2 : 4
        let amount = String(format: "%.\(fractionDigits)f", value)

        if currency.usesLeadingSymbol {
            return "\(currency.symbol)\(amount)"
        }
        return "\(amount) \(currency.symbol)"
    }
}

struct GenerationCostEstimate: Codable, Equatable, Sendable {
    let provider: ModelProvider
    let model: String
    let resolution: ImageResolution
    let imageCount: Int
    let unit: GenerationCostUnit
    let perImage: Double?
    let total: Double?
    let confidence: GenerationCostConfidence
    let note: String?

    func matches(
        provider: ModelProvider,
        model: String,
        resolution: ImageResolution,
        imageCount: Int
    ) -> Bool {
        self.provider == provider &&
            self.model.caseInsensitiveCompare(model) == .orderedSame &&
            self.resolution == resolution &&
            self.imageCount == imageCount
    }
}
