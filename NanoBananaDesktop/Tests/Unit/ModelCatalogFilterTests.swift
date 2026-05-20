import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func filterImageReadyModelsIncludesOnlySupportedImageModels() {
    let models: [ModelCatalogItem] = [
        ModelCatalogItem(
            provider: .gemini,
            name: "gemini-3-pro-image-preview",
            displayName: "Nano Banana Pro",
            description: "Gemini 3 Pro Image Preview",
            supportedMethods: ["generateContent", "countTokens"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .gemini,
            name: "gemini-2.5-flash",
            displayName: "Gemini Flash",
            description: "General multimodal model",
            supportedMethods: ["generateContent"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .gemini,
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
            provider: .gemini,
            name: "gemini-3-pro-image-preview",
            displayName: "Nano Banana Pro",
            description: "Gemini 3 Pro Image Preview",
            supportedMethods: ["generateContent", "countTokens"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .gemini,
            name: "gemini-2.5-flash",
            displayName: "Gemini Flash",
            description: "General multimodal model",
            supportedMethods: ["generateContent"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .gemini,
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
                provider: .gemini,
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
                provider: .gemini,
                name: "nano-banana-pro-preview",
                displayName: "Nano Banana Pro",
                description: "Gemini 3 Pro Image Preview",
                supportedMethods: ["generateContent"],
                isCustomFallback: false
            ),
            ModelCatalogItem(
                provider: .gemini,
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
                provider: .gemini,
                name: "gemini-3-pro-image-preview",
                displayName: "Nano Banana Pro",
                description: "Gemini 3 Pro Image Preview",
                supportedMethods: ["generateContent"],
                isCustomFallback: false
            ),
            ModelCatalogItem(
                provider: .gemini,
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
                provider: .gemini,
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

@Test
func selectableTextModelsInferOpenAIProviderForCustomGPTModel() async throws {
    let viewModel = try await makeMainViewModel()

    await MainActor.run {
        viewModel.config.promptEnhancementModel = "gpt-5.4"
        viewModel.applyTextModelCatalog([])
    }

    let selectable = await MainActor.run { viewModel.selectableTextModels }
    #expect(selectable.first?.name == "gpt-5.4")
    #expect(selectable.first?.provider == .openAI)
    #expect(selectable.first?.isCustomFallback == true)
}

@Test
func selectableTextModelsInferOpenAICompatibleProviderForPrefixedCustomGPTModel() async throws {
    let viewModel = try await makeMainViewModel()

    await MainActor.run {
        viewModel.config.promptEnhancementModel = "openAICompatible:gpt-5.4"
        viewModel.applyTextModelCatalog([])
    }

    let selectable = await MainActor.run { viewModel.selectableTextModels }
    #expect(selectable.first?.name == "openAICompatible:gpt-5.4")
    #expect(selectable.first?.provider == .openAICompatible)
    #expect(selectable.first?.isCustomFallback == true)
}

@Test
func selectableTextModelsSortCurrentSelectionFirst() async throws {
    let viewModel = try await makeMainViewModel()

    await MainActor.run {
        viewModel.config.promptEnhancementModel = "gpt-5.4"
        viewModel.applyTextModelCatalog([
            ModelCatalogItem(
                provider: .gemini,
                name: "gemini-2.5-flash",
                displayName: "Gemini Flash",
                description: "",
                supportedMethods: ["generateContent"],
                isCustomFallback: false
            ),
            ModelCatalogItem(
                provider: .openAI,
                name: "gpt-5.4",
                displayName: "GPT 5.4",
                description: "",
                supportedMethods: ["responses"],
                isCustomFallback: false
            )
        ])
    }

    let selectable = await MainActor.run { viewModel.selectableTextModels }
    #expect(selectable.first?.name == "gpt-5.4")
}

@Test
func filterOpenAIImageReadyModelsIncludesGPTImageModels() {
    let models: [ModelCatalogItem] = [
        ModelCatalogItem(
            provider: .openAI,
            name: "gpt-image-2",
            displayName: "GPT Image 2",
            description: "",
            supportedMethods: ["images.generate"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAI,
            name: "gpt-5.4",
            displayName: "GPT-5.4",
            description: "",
            supportedMethods: ["responses"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAI,
            name: "dall-e-3",
            displayName: "DALL-E 3",
            description: "",
            supportedMethods: ["images.generate"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAI,
            name: "chatgpt-image-latest",
            displayName: "ChatGPT Image Latest",
            description: "",
            supportedMethods: ["images.generate"],
            isCustomFallback: false
        )
    ]

    let filtered = OpenAIModelCatalogClient.filterImageReadyModels(from: models)
    #expect(filtered.map(\.name) == ["gpt-image-2"])
}

@Test
func filterOpenAITextReadyModelsIncludesAliasWithoutSnapshots() {
    let models: [ModelCatalogItem] = [
        ModelCatalogItem(
            provider: .openAI,
            name: "gpt-5.4",
            displayName: "GPT-5.4",
            description: "",
            supportedMethods: ["responses"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAI,
            name: "gpt-5.4-2026-03-15",
            displayName: "GPT-5.4 Snapshot",
            description: "",
            supportedMethods: ["responses"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAI,
            name: "gpt-image-2",
            displayName: "GPT Image 2",
            description: "",
            supportedMethods: ["images.generate"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAI,
            name: "dall-e-3",
            displayName: "DALL-E 3",
            description: "",
            supportedMethods: ["images.generate"],
            isCustomFallback: false
        )
    ]

    let filtered = OpenAIModelCatalogClient.filterTextReadyModels(from: models)
    #expect(filtered.map(\.name) == ["gpt-5.4"])
}

@Test
func filterOpenAICompatibleModelsUsesEncodedProviderNames() {
    let models: [ModelCatalogItem] = [
        ModelCatalogItem(
            provider: .openAICompatible,
            name: "openAICompatible:gpt-image-2",
            displayName: "GPT Image 2",
            description: "",
            supportedMethods: ["images.generate"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAICompatible,
            name: "openAICompatible:gemini-3.1-flash-image-preview",
            displayName: "Gemini 3.1 Flash Image Preview",
            description: "",
            supportedMethods: ["images.generate"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAICompatible,
            name: "openAICompatible:gemini-3-pro-image-preview",
            displayName: "Gemini 3 Pro Image Preview",
            description: "",
            supportedMethods: ["images.generate"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAICompatible,
            name: "openAICompatible:gpt-5.4",
            displayName: "GPT-5.4",
            description: "",
            supportedMethods: ["responses"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAICompatible,
            name: "openAICompatible:gpt-5.4-2026-03-15",
            displayName: "GPT-5.4 Snapshot",
            description: "",
            supportedMethods: ["responses"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAICompatible,
            name: "openAICompatible:claude-sonnet-4-5",
            displayName: "Claude Sonnet 4.5",
            description: "",
            supportedMethods: ["chat.completions"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAICompatible,
            name: "openAICompatible:qwen2.5-vl",
            displayName: "Qwen 2.5 VL",
            description: "",
            supportedMethods: ["chat.completions"],
            isCustomFallback: false
        ),
        ModelCatalogItem(
            provider: .openAICompatible,
            name: "openAICompatible:text-embedding-3-large",
            displayName: "Embedding",
            description: "",
            supportedMethods: ["embeddings"],
            isCustomFallback: false
        )
    ]

    let imageModels = OpenAIModelCatalogClient.filterImageReadyModels(from: models)
    let textModels = OpenAIModelCatalogClient.filterTextReadyModels(from: models)

    #expect(imageModels.map(\.name) == [
        "openAICompatible:gpt-image-2",
        "openAICompatible:gemini-3.1-flash-image-preview",
        "openAICompatible:gemini-3-pro-image-preview"
    ])
    #expect(textModels.map(\.name) == [
        "openAICompatible:gpt-5.4",
        "openAICompatible:claude-sonnet-4-5",
        "openAICompatible:qwen2.5-vl"
    ])
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
