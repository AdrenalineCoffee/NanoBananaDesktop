import Testing
@testable import NanoBananaDesktop

@Test
func kieTextModelRegistryPublishesPromptReadyModels() {
    let items = KieTextModelRegistry.catalogItems

    #expect(items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "gpt-5-4") })
    #expect(items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "claude-sonnet-4-5") })
    #expect(items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "gemini-3-pro-preview") })
    #expect(items.contains { $0.name == ModelProvider.encodedModelName(provider: .kie, modelName: "codex") })
}

@Test
func kieTextModelRegistryTracksWireFormatAndImageInputSupport() {
    let gpt = KieTextModelRegistry.spec(for: ModelProvider.encodedModelName(provider: .kie, modelName: "gpt-5-4"))
    let codex = KieTextModelRegistry.spec(for: ModelProvider.encodedModelName(provider: .kie, modelName: "codex"))

    #expect(gpt?.wireFormat == .chatCompletions)
    #expect(gpt?.supportsImageInput == true)
    #expect(codex?.wireFormat == .responses)
    #expect(codex?.supportsImageInput == false)
}
