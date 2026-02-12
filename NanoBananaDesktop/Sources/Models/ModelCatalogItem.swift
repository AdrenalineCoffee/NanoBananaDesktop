import Foundation

struct ModelCatalogItem: Identifiable, Equatable {
    let name: String
    let displayName: String
    let description: String
    let supportedMethods: [String]
    let isCustomFallback: Bool

    var id: String { name }

    static func custom(_ name: String) -> ModelCatalogItem {
        ModelCatalogItem(
            name: name,
            displayName: name,
            description: "",
            supportedMethods: [],
            isCustomFallback: true
        )
    }
}
