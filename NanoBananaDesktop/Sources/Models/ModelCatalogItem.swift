import Foundation

struct ModelCatalogItem: Identifiable, Equatable {
    let provider: ModelProvider
    let name: String
    let displayName: String
    let description: String
    let supportedMethods: [String]
    let isCustomFallback: Bool

    var id: String { "\(provider.rawValue):\(name)" }

    static func custom(_ name: String, provider: ModelProvider = .gemini) -> ModelCatalogItem {
        ModelCatalogItem(
            provider: provider,
            name: name,
            displayName: name,
            description: "",
            supportedMethods: [],
            isCustomFallback: true
        )
    }
}
