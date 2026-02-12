import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func filterImageReadyModelsIncludesOnlySupportedImageModels() {
    let models: [ModelCatalogItem] = [
        ModelCatalogItem(
            name: "gemini-3-pro-image-preview",
            displayName: "Nano Banana Pro",
            description: "Gemini 3 Pro Image Preview",
            supportedMethods: ["generateContent", "countTokens"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            name: "gemini-2.5-flash",
            displayName: "Gemini Flash",
            description: "General multimodal model",
            supportedMethods: ["generateContent"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            name: "imagen-4.0-ultra-generate-001",
            displayName: "Imagen 4 Ultra",
            description: "High quality image generation",
            supportedMethods: ["predict"],
            isCustomFallback: false
        )
    ]

    let filtered = GeminiModelCatalogClient.filterImageReadyModels(from: models)
    #expect(filtered.map(\.name) == ["gemini-3-pro-image-preview"])
}

@Test
func filterTextReadyModelsIncludesGenerateContentModelsOnly() {
    let models: [ModelCatalogItem] = [
        ModelCatalogItem(
            name: "gemini-3-pro-image-preview",
            displayName: "Nano Banana Pro",
            description: "Gemini 3 Pro Image Preview",
            supportedMethods: ["generateContent", "countTokens"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            name: "gemini-2.5-flash",
            displayName: "Gemini Flash",
            description: "General multimodal model",
            supportedMethods: ["generateContent"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            name: "imagen-4.0-ultra-generate-001",
            displayName: "Imagen 4 Ultra",
            description: "High quality image generation",
            supportedMethods: ["predict"],
            isCustomFallback: false
        )
    ]

    let filtered = GeminiModelCatalogClient.filterTextReadyModels(from: models)
    #expect(filtered.map(\.name) == ["gemini-3-pro-image-preview", "gemini-2.5-flash"])
}

@Test
func selectableModelsInsertCustomWhenCurrentModelIsMissing() async throws {
    let viewModel = try await makeMainViewModel()

    await MainActor.run {
        viewModel.config.model = "my-custom-image-model"
        viewModel.applyModelCatalog([
            ModelCatalogItem(
                name: "gemini-3-pro-image-preview",
                displayName: "Nano Banana Pro",
                description: "Gemini 3 Pro Image Preview",
                supportedMethods: ["generateContent"],
                isCustomFallback: false
            )
        ])
    }

    let selectable = await MainActor.run { viewModel.selectableImageModels }
    #expect(selectable.first?.name == "my-custom-image-model")
    #expect(selectable.first?.isCustomFallback == true)
}

@Test
func selectableModelsSortCurrentModelFirst() async throws {
    let viewModel = try await makeMainViewModel()

    await MainActor.run {
        viewModel.config.model = "gemini-3-pro-image-preview"
        viewModel.applyModelCatalog([
            ModelCatalogItem(
                name: "nano-banana-pro-preview",
                displayName: "Nano Banana Pro",
                description: "Gemini 3 Pro Image Preview",
                supportedMethods: ["generateContent"],
                isCustomFallback: false
            ),
            ModelCatalogItem(
                name: "gemini-3-pro-image-preview",
                displayName: "Nano Banana Pro",
                description: "Gemini 3 Pro Image Preview",
                supportedMethods: ["generateContent"],
                isCustomFallback: false
            )
        ])
    }

    let selectable = await MainActor.run { viewModel.selectableImageModels }
    #expect(selectable.first?.name == "gemini-3-pro-image-preview")
}

@Test
func selectableModelsReorderWhenSelectionChangesAfterCatalogLoad() async throws {
    let viewModel = try await makeMainViewModel()

    await MainActor.run {
        viewModel.config.model = "nano-banana-pro-preview"
        viewModel.applyModelCatalog([
            ModelCatalogItem(
                name: "gemini-3-pro-image-preview",
                displayName: "Nano Banana Pro",
                description: "Gemini 3 Pro Image Preview",
                supportedMethods: ["generateContent"],
                isCustomFallback: false
            ),
            ModelCatalogItem(
                name: "nano-banana-pro-preview",
                displayName: "Nano Banana Pro",
                description: "Gemini 3 Pro Image Preview",
                supportedMethods: ["generateContent"],
                isCustomFallback: false
            )
        ])
        viewModel.config.model = "gemini-3-pro-image-preview"
    }

    let selectable = await MainActor.run { viewModel.selectableImageModels }
    #expect(selectable.first?.name == "gemini-3-pro-image-preview")
}

@Test
func selectableTextModelsInsertCustomWhenPromptModelIsMissing() async throws {
    let viewModel = try await makeMainViewModel()

    await MainActor.run {
        viewModel.config.promptEnhancementModel = "custom-text-model"
        viewModel.applyTextModelCatalog([
            ModelCatalogItem(
                name: "gemini-2.5-flash",
                displayName: "Gemini Flash",
                description: "Text model",
                supportedMethods: ["generateContent"],
                isCustomFallback: false
            )
        ])
    }

    let selectable = await MainActor.run { viewModel.selectableTextModels }
    #expect(selectable.first?.name == "custom-text-model")
    #expect(selectable.first?.isCustomFallback == true)
}

private func makeMainViewModel() async throws -> MainViewModel {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))

    return await MainActor.run {
        MainViewModel(configStore: configStore, historyStore: historyStore)
    }
}
