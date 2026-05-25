import Foundation

enum KieTextWireFormat: String, Sendable {
    case chatCompletions
    case responses
    case claudeMessages
}

struct KieTextModelSpec: Sendable, Equatable {
    let model: String
    let displayName: String
    let endpointPath: String
    let wireFormat: KieTextWireFormat
    let supportsImageInput: Bool
    let isCatalogVisible: Bool

    init(
        model: String,
        displayName: String,
        endpointPath: String,
        wireFormat: KieTextWireFormat,
        supportsImageInput: Bool,
        isCatalogVisible: Bool = true
    ) {
        self.model = model
        self.displayName = displayName
        self.endpointPath = endpointPath
        self.wireFormat = wireFormat
        self.supportsImageInput = supportsImageInput
        self.isCatalogVisible = isCatalogVisible
    }

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
        .init(model: "gpt-5-5", displayName: "Kie GPT-5.5", endpointPath: "codex/v1/responses", wireFormat: .responses, supportsImageInput: true),
        .init(model: "gpt-5-4", displayName: "Kie GPT-5.4", endpointPath: "codex/v1/responses", wireFormat: .responses, supportsImageInput: true),
        .init(model: "gpt-5-2", displayName: "Kie GPT-5.2", endpointPath: "gpt-5-2/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "gpt-5", displayName: "Kie GPT-5", endpointPath: "gpt-5/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "gpt-4o", displayName: "Kie GPT-4o", endpointPath: "gpt-4o/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "gemini-3-pro-preview", displayName: "Kie Gemini 3 Pro", endpointPath: "gemini-3-pro-preview/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "gemini-2.5-pro", displayName: "Kie Gemini 2.5 Pro", endpointPath: "gemini-2.5-pro/v1/chat/completions", wireFormat: .chatCompletions, supportsImageInput: true),
        .init(model: "claude-opus-4-7", displayName: "Kie Claude Opus 4.7", endpointPath: "claude/v1/messages", wireFormat: .claudeMessages, supportsImageInput: true),
        .init(model: "claude-opus-4-6", displayName: "Kie Claude Opus 4.6", endpointPath: "claude/v1/messages", wireFormat: .claudeMessages, supportsImageInput: true),
        .init(model: "claude-opus-4-5", displayName: "Kie Claude Opus 4.5", endpointPath: "claude/v1/messages", wireFormat: .claudeMessages, supportsImageInput: true),
        .init(model: "claude-sonnet-4-6", displayName: "Kie Claude Sonnet 4.6", endpointPath: "claude/v1/messages", wireFormat: .claudeMessages, supportsImageInput: true),
        .init(model: "claude-sonnet-4-5", displayName: "Kie Claude Sonnet 4.5", endpointPath: "claude/v1/messages", wireFormat: .claudeMessages, supportsImageInput: true),
        .init(model: "claude-haiku-4-5", displayName: "Kie Claude Haiku 4.5", endpointPath: "claude/v1/messages", wireFormat: .claudeMessages, supportsImageInput: true),
        .init(model: "gpt-5.4-codex", displayName: "Kie Codex", endpointPath: "api/v1/responses", wireFormat: .responses, supportsImageInput: false),
        .init(model: "codex", displayName: "Kie Codex", endpointPath: "api/v1/responses", wireFormat: .responses, supportsImageInput: false, isCatalogVisible: false),
        .init(model: "claude-opus-4-1", displayName: "Kie Claude Opus 4.1", endpointPath: "claude/v1/messages", wireFormat: .claudeMessages, supportsImageInput: true, isCatalogVisible: false)
    ]

    static var catalogItems: [ModelCatalogItem] {
        specs.filter(\.isCatalogVisible).map(\.catalogItem)
    }

    static func spec(for selectedModelName: String) -> KieTextModelSpec? {
        let apiName = ModelProvider.apiModelName(from: selectedModelName)
        return specs.first { $0.model.caseInsensitiveCompare(apiName) == .orderedSame }
    }
}
