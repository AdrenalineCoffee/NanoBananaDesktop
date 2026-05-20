import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func conceptProjectStoreSavesAndLoadsProjectRoundtrip() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let store = try ConceptProjectStore(projectsDirectory: tempDir)
    let layerID = UUID()
    let project = ConceptProject(
        id: UUID(),
        title: "Bike Concept",
        canvasAspectRatio: .landscape16x9,
        canvasSizePreset: .medium,
        canvasBackgroundColor: .white,
        prompt: "Add a bike bag",
        model: "nano-banana-pro-preview",
        resolutionSelection: .k1,
        aspectRatioSelection: .landscape16x9,
        referenceMode: .strictPreserve,
        imageCount: 2,
        layers: [
            ConceptLayer(
                id: layerID,
                name: "Reference",
                type: .referenceImage,
                isVisible: true,
                isLocked: true,
                zIndex: 0,
                assetFilename: "layer-\(layerID.uuidString).png"
            )
        ]
    )
    let state = ConceptProjectState(project: project, layerAssetData: [layerID: tinyConceptPNGData])

    try store.save(state)
    let loadedState = try store.loadProject(id: project.id)
    let loaded = try #require(loadedState)

    #expect(loaded.project.title == "Bike Concept")
    #expect(loaded.project.layers.count == 1)
    #expect(loaded.project.referenceMode == .strictPreserve)
    #expect(loaded.layerAssetData[layerID] == tinyConceptPNGData)
}

@Test
func conceptProjectStoreCreatesDefaultProjectWhenEmpty() throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let store = try ConceptProjectStore(projectsDirectory: tempDir)
    let state = try store.loadLastProjectOrCreateDefault(defaultModel: "nano-banana-pro-preview")

    #expect(state.project.layers.count == 1)
    #expect(state.project.layers.first?.type == .sketch)
    #expect(state.project.model == "nano-banana-pro-preview")
    #expect(state.project.referenceMode == .balanced)
}

private let tinyConceptPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+2YQAAAAASUVORK5CYII="
private let tinyConceptPNGData = Data(base64Encoded: tinyConceptPNGBase64)!
