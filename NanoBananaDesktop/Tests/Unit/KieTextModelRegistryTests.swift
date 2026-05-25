import Testing
@testable import NanoBananaDesktop

@Test
func kieTextModelRegistryPublishesPromptReadyModels() {
    let items = KieTextModelRegistry.catalogItems

    #expect(items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "gpt-5-4") })
    #expect(items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "gpt-5-5") })
    #expect(items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "claude-sonnet-4-5") })
    #expect(items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "claude-opus-4-7") })
    #expect(items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "gemini-3-pro-preview") })
    #expect(items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "gpt-5.4-codex") })
    #expect(!items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "codex") })
    #expect(!items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "claude-opus-4-1") })
}

@Test
func kieTextModelRegistryTracksWireFormatAndImageInputSupport() {
    let gpt = KieTextModelRegistry.spec(for: ModelProvider.encodedModelName(provider: .kie, modelName: "gpt-5-4"))
    let opus = KieTextModelRegistry.spec(for: ModelProvider.encodedModelName(provider: .kie, modelName: "claude-opus-4-7"))
    let codex = KieTextModelRegistry.spec(for: ModelProvider.encodedModelName(provider: .kie, modelName: "codex"))

    #expect(gpt?.wireFormat == .responses)
    #expect(gpt?.supportsImageInput == true)
    #expect(opus?.wireFormat == .claudeMessages)
    #expect(opus?.supportsImageInput == true)
    #expect(codex?.wireFormat == .responses)
    #expect(codex?.supportsImageInput == false)
}
