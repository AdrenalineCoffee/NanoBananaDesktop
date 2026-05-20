import Foundation

enum ModelProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case gemini
    case openAI
    case openAICompatible
    case kie

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini:
            return "Google"
        case .openAI:
            return "OpenAI"
        case .openAICompatible:
            return "OpenAI-compatible"
        case .kie:
            return "Kie.ai"
        }
    }

    static func inferImageProvider(from modelName: String) -> ModelProvider {
        let normalized = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("\(openAICompatible.rawValue.lowercased()):") {
            return .openAICompatible
        }
        if normalized.hasPrefix("\(kie.rawValue.lowercased()):") {
            return .kie
        }
        if normalized.hasPrefix("gpt-image")
            || normalized == "chatgpt-image-latest"
            || normalized.hasPrefix("dall-e-") {
            return .openAI
        }
        return .gemini
    }

    static func inferTextProvider(from modelName: String) -> ModelProvider {
        let normalized = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("\(openAICompatible.rawValue.lowercased()):") {
            return .openAICompatible
        }
        if normalized.hasPrefix("\(kie.rawValue.lowercased()):") {
            return .kie
        }
        if normalized.hasPrefix("gpt-") {
            return .openAI
        }
        return .gemini
    }

    static func encodedModelName(provider: ModelProvider, modelName: String) -> String {
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case .openAICompatible, .kie:
            return "\(provider.rawValue):\(trimmedModel)"
        case .gemini, .openAI:
            return trimmedModel
        }
    }

    static func apiModelName(from selectedModelName: String) -> String {
        let trimmed = selectedModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        for provider in [openAICompatible, kie] {
            let prefix = "\(provider.rawValue):"
            if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                return String(trimmed.dropFirst(prefix.count))
            }
        }
        return trimmed
    }
}
