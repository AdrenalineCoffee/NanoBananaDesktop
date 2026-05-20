import Testing
@testable import NanoBananaDesktop

@Test
func kieModelRegistryPublishesEncodedCatalogItems() {
    let items = KieModelRegistry.catalogItems

    #expect(items.contains { item in
        item.provider == .kie &&
            item.name == ModelProvider.encodedModelName(provider: .kie, modelName: "nano-banana-pro")
    })
    #expect(items.contains { item in
        item.provider == .kie &&
            item.name == ModelProvider.encodedModelName(provider: .kie, modelName: "nano-banana-2")
    })
    #expect(items.contains { item in
        item.provider == .kie &&
            item.name == ModelProvider.encodedModelName(provider: .kie, modelName: "google/nano-banana")
    })
    #expect(items.contains { item in
        item.provider == .kie &&
            item.name == ModelProvider.encodedModelName(provider: .kie, modelName: "google/nano-banana-edit")
    })
    #expect(items.contains { item in
        item.provider == .kie &&
            item.name == ModelProvider.encodedModelName(provider: .kie, modelName: "topaz/image-upscale")
    })
}

@Test
func kieConceptCatalogExcludesUtilityModels() {
    let conceptModels = Set(KieModelRegistry.conceptCatalogItems.map(\.name))

    #expect(conceptModels.contains(ModelProvider.encodedModelName(provider: .kie, modelName: "nano-banana-pro")))
    #expect(conceptModels.contains(ModelProvider.encodedModelName(provider: .kie, modelName: "nano-banana-2")))
    #expect(conceptModels.contains(ModelProvider.encodedModelName(provider: .kie, modelName: "google/nano-banana-edit")))
    #expect(!conceptModels.contains(ModelProvider.encodedModelName(provider: .kie, modelName: "google/nano-banana")))
    #expect(!conceptModels.contains(ModelProvider.encodedModelName(provider: .kie, modelName: "topaz/image-upscale")))
    #expect(!conceptModels.contains(ModelProvider.encodedModelName(provider: .kie, modelName: "recraft/remove-background")))
    #expect(!conceptModels.contains(ModelProvider.encodedModelName(provider: .kie, modelName: "gpt-image-2-text-to-image")))
}

@Test
func kieNanoBananaProAndNanoBanana2AcceptOptionalInputImages() {
    let pro = KieModelRegistry.spec(for: ModelProvider.encodedModelName(provider: .kie, modelName: "nano-banana-pro"))
    let two = KieModelRegistry.spec(for: ModelProvider.encodedModelName(provider: .kie, modelName: "nano-banana-2"))
    let edit = KieModelRegistry.spec(for: ModelProvider.encodedModelName(provider: .kie, modelName: "google/nano-banana-edit"))
    let text = KieModelRegistry.spec(for: ModelProvider.encodedModelName(provider: .kie, modelName: "google/nano-banana"))

    #expect(pro?.inputRequirement == .optional)
    #expect(pro?.requiresInputImage == false)
    #expect(two?.inputRequirement == .optional)
    #expect(two?.requiresInputImage == false)
    #expect(edit?.inputRequirement == .required)
    #expect(edit?.requiresInputImage == true)
    #expect(text?.inputRequirement == KieImageInputRequirement.none)
}
