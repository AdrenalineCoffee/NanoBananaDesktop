import Foundation

enum KieTextWireFormat: String, Sendable {
    case chatCompletions
    case responses
}

struct KieTextModelSpec: Sendable, Equatable {
    let model: String
    let displayName: String
    let endpointPath: String
    let wireFormat: KieTextWireFormat
    let supportsImageInput: Bool

    var catalogItem: ModelCatalogItem {
        ModelCatalogItem(
            provider: .kie,
            name: ModelProvider.encodedModelName(provider: .kie, modelName: model),
            displayName: displayName,
            description: "text",
            supportedMethods: [wireFormat.rawValue],
            isCustomFallback: false
        )
    }
}

enum KieTextModelRegistry {
    static let specs: [KieTextModelSpec] = [
        .init(model: "gpt-5-4", displayName: "Kie GPT-5.4", endpointPath: "gpt-5-4/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "gpt-5-2", displayName: "Kie GPT-5.2", endpointPath: "gpt-5-2/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "gpt-5", displayName: "Kie GPT-5", endpointPath: "gpt-5/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "gpt-4o", displayName: "Kie GPT-4o", endpointPath: "gpt-4o/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "gemini-3-pro-preview", displayName: "Kie Gemini 3 Pro", endpointPath: "gemini-3-pro-preview/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "gemini-2.5-pro", displayName: "Kie Gemini 2.5 Pro", endpointPath: "gemini-2.5-pro/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "claude-sonnet-4-5", displayName: "Kie Claude Sonnet 4.5", endpointPath: "claude-sonnet-4-5/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "claude-opus-4-1", displayName: "Kie Claude Opus 4.1", endpointPath: "claude-opus-4-1/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "codex", displayName: "Kie Codex", endpointPath: "codex/v1/responses", wireFormat: .responses, supportsImageInput: false)
    ]

    static var catalogItems: [ModelCatalogItem] {
        specs.map(\.catalogItem)
    }

    static func spec(for selectedModelName: String) -> KieTextModelSpec? {
        let apiName = ModelProvider.apiModelName(from: selectedModelName)
        return specs.first { $0.model.caseInsensitiveCompare(apiName) == .orderedSame }
    }
}
