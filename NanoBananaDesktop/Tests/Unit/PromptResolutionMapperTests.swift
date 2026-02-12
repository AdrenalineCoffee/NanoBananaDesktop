import Testing
@testable import NanoBananaDesktop

@Test
func autoResolutionDefaultsTo1K() {
    let mapper = PromptResolutionMapper()
    let resolution = mapper.resolve(prompt: "A calm landscape", selection: .auto)
    #expect(resolution == .k1)
}

@Test
func autoResolutionDetects4KKeywords() {
    let mapper = PromptResolutionMapper()
    let resolution = mapper.resolve(prompt: "ultra high-res portrait", selection: .auto)
    #expect(resolution == .k4)
}

@Test
func autoResolutionDetects2KKeywords() {
    let mapper = PromptResolutionMapper()
    let resolution = mapper.resolve(prompt: "normal quality 2048 artwork", selection: .auto)
    #expect(resolution == .k2)
}

@Test
func manualSelectionOverridesPrompt() {
    let mapper = PromptResolutionMapper()
    let resolution = mapper.resolve(prompt: "4K ultra image", selection: .k1)
    #expect(resolution == .k1)
}
