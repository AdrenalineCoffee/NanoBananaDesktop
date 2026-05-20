import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func conceptingViewModelLoadsDefaultProjectAndAddsSketchLayer() async throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let store = try ConceptProjectStore(projectsDirectory: tempDir)
    let viewModel = await MainActor.run {
        ConceptingViewModel(store: store)
    }

    await MainActor.run {
        viewModel.loadIfNeeded(defaultModel: "nano-banana-pro-preview")
    }

    let initialCount = await MainActor.run { viewModel.layers.count }
    #expect(initialCount == 1)

    await MainActor.run {
        viewModel.addSketchLayer()
    }

    let layers = await MainActor.run { viewModel.layers }
    #expect(layers.count == 2)
    #expect(layers.first?.type == .sketch)
}

@Test
func conceptingViewModelImportsReferenceAndBlocksDrawingOnLockedLayer() async throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let imageURL = tempDir.appendingPathComponent("reference.png")
    try tinyConceptSmokePNGData.write(to: imageURL)

    let store = try ConceptProjectStore(projectsDirectory: tempDir)
    let viewModel = await MainActor.run {
        ConceptingViewModel(store: store)
    }

    await MainActor.run {
        viewModel.loadIfNeeded(defaultModel: "nano-banana-pro-preview")
        viewModel.importReferenceImage(from: imageURL)
    }

    let referenceLayer = await MainActor.run {
        viewModel.layers.first(where: { $0.type == .referenceImage })
    }
    let selectedLayer = await MainActor.run { viewModel.selectedLayer }
    let compositeImage = await MainActor.run { viewModel.canvasCompositeImage }

    #expect(referenceLayer != nil)
    #expect(referenceLayer?.isLocked == true)
    #expect(selectedLayer?.type == .referenceImage)
    #expect(compositeImage != nil)

    let beforeStrokeCount = await MainActor.run { viewModel.selectedLayer?.strokes.count ?? 0 }
    await MainActor.run {
        viewModel.commitStroke(points: [
            ConceptPoint(x: 0.1, y: 0.1),
            ConceptPoint(x: 0.2, y: 0.2)
        ])
    }
    let afterStrokeCount = await MainActor.run { viewModel.selectedLayer?.strokes.count ?? 0 }

    #expect(beforeStrokeCount == 0)
    #expect(afterStrokeCount == 0)
}

private let tinyConceptSmokePNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+2YQAAAAASUVORK5CYII="
private let tinyConceptSmokePNGData = Data(base64Encoded: tinyConceptSmokePNGBase64)!

@Test
func conceptingCombinedUserPromptAppendsSettingsAdditionsInline() {
    let combined = ConceptingViewModel.combinedUserPrompt(
        userPrompt: "сделай велосумку по форме скетча",
        promptAdditions: ", сделай этот объект на белом фоне без теней"
    )

    #expect(combined == "сделай велосумку по форме скетча, сделай этот объект на белом фоне без теней")
}

@Test
func mergeGeneratedResultLayerDoesNotOverwriteCurrentPromptChanges() async throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let store = try ConceptProjectStore(projectsDirectory: tempDir)
    let viewModel = await MainActor.run {
        ConceptingViewModel(store: store)
    }

    await MainActor.run {
        viewModel.loadIfNeeded(defaultModel: "nano-banana-pro-preview")
        viewModel.setPrompt("old prompt")
    }

    let projectID = try await MainActor.run {
        try #require(viewModel.project?.id)
    }

    await MainActor.run {
        viewModel.setPrompt("new prompt")
        _ = viewModel.mergeGeneratedResultLayer(
            projectID: projectID,
            layer: ConceptLayer(name: "Result", type: .result, zIndex: 0),
            data: tinyConceptSmokePNGData
        )
    }

    let project = try await MainActor.run {
        try #require(viewModel.project)
    }

    #expect(project.prompt == "new prompt")
    #expect(project.layers.count == 2)
    #expect(project.layers.first?.type == .result)
}
