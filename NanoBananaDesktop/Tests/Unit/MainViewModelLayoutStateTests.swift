import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
@MainActor
func imageSettingsExpandedDefaultsToTrue() throws {
    let viewModel = try makeMainViewModel()
    #expect(viewModel.isImageSettingsExpanded == true)
}

@Test
@MainActor
func resolutionSliderMapsToSelectionAndLabel() throws {
    let viewModel = try makeMainViewModel()

    viewModel.resolutionSliderValue = 0
    #expect(viewModel.resolutionSelection == .k1)
    #expect(viewModel.resolutionValueLabel == "1K")

    viewModel.resolutionSliderValue = 1
    #expect(viewModel.resolutionSelection == .k2)
    #expect(viewModel.resolutionValueLabel == "2K")

    viewModel.resolutionSliderValue = 2
    #expect(viewModel.resolutionSelection == .k4)
    #expect(viewModel.resolutionValueLabel == "4K")
}

@Test
@MainActor
func canEnhancePromptDependsOnPromptAndLoadingState() throws {
    let viewModel = try makeMainViewModel()

    viewModel.prompt = "   "
    viewModel.isEnhancingPrompt = false
    #expect(viewModel.canEnhancePrompt == false)

    viewModel.prompt = "Refine this prompt"
    viewModel.isEnhancingPrompt = false
    #expect(viewModel.canEnhancePrompt == true)

    viewModel.isEnhancingPrompt = true
    #expect(viewModel.canEnhancePrompt == false)
}

@MainActor
private func makeMainViewModel() throws -> MainViewModel {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let configStore = try AppConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
    let historyStore = try HistoryStore(historyURL: tempDirectory.appendingPathComponent("history.json"))
    return MainViewModel(configStore: configStore, historyStore: historyStore)
}
