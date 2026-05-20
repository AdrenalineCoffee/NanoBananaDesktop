import AppKit
import Foundation

@MainActor
final class ConceptingViewModel: ObservableObject {
    private struct CompletedGeneratedLayerResult: Sendable {
        let index: Int
        let image: GeneratedImageResult
    }

    @Published private(set) var project: ConceptProject?
    @Published private(set) var layerAssetData: [UUID: Data] = [:]
    @Published private(set) var canvasCompositeImage: NSImage?
    @Published var selectedLayerID: UUID?
    @Published var activeTool: ConceptTool = .brush
    @Published var brushColor: ConceptRGBAColor = .blue
    @Published var brushWidth: Double = 4
    @Published var brushOpacity: Double = 1
    @Published var zoomScale: CGFloat = 1
    @Published var isGenerating: Bool = false
    @Published var removingBackgroundLayerID: UUID?
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var didLoadProject: Bool = false

    private let fileManager: FileManager
    private let store: ConceptProjectStore?
    private let rasterizer: ConceptRasterizer
    private let apiClient: GeminiAPIClient
    private let openAIImageAPIClient: OpenAIImageAPIClient
    private let networkClientProvider: NetworkClientProvider
    private let imagePersistenceService: ImagePersistenceService
    private let filenameGenerator: FilenameGenerator
    private let resolutionMapper: PromptResolutionMapper
    private let supportedAttachmentExtensions = Set(["png", "jpg", "jpeg", "webp"])
    private let maxUndoSnapshots = 20
    private var undoStack: [ConceptProjectState] = []
    private var redoStack: [ConceptProjectState] = []
    private var isPreviewReorderingLayers = false

    init(
        fileManager: FileManager = .default,
        store: ConceptProjectStore? = nil,
        rasterizer: ConceptRasterizer = ConceptRasterizer(),
        apiClient: GeminiAPIClient = GeminiAPIClient(),
        openAIImageAPIClient: OpenAIImageAPIClient = OpenAIImageAPIClient(),
        networkClientProvider: NetworkClientProvider = ProxySessionFactory(),
        imagePersistenceService: ImagePersistenceService = ImagePersistenceService(),
        filenameGenerator: FilenameGenerator = FilenameGenerator(),
        resolutionMapper: PromptResolutionMapper = PromptResolutionMapper()
    ) {
        self.fileManager = fileManager
        self.store = store ?? (try? ConceptProjectStore(fileManager: fileManager))
        self.rasterizer = rasterizer
        self.apiClient = apiClient
        self.openAIImageAPIClient = openAIImageAPIClient
        self.networkClientProvider = networkClientProvider
        self.imagePersistenceService = imagePersistenceService
        self.filenameGenerator = filenameGenerator
        self.resolutionMapper = resolutionMapper
    }

    var layers: [ConceptLayer] { project?.layers ?? [] }

    var selectedLayer: ConceptLayer? {
        guard let selectedLayerID else { return nil }
        return project?.layers.first(where: { $0.id == selectedLayerID })
    }

    var canvasSize: CGSize {
        guard let project else {
            return rasterizer.canvasPixelSize(aspectRatio: .landscape16x9, preset: .medium)
        }
        return rasterizer.canvasPixelSize(aspectRatio: project.canvasAspectRatio, preset: project.canvasSizePreset)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var canGenerate: Bool {
        guard let project else { return false }
        return !isGenerating && !project.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canDrawOnSelectedLayer: Bool {
        selectedLayer?.isEditable == true
    }

    func combinedUserPromptPreview(promptAdditions: String) -> String {
        Self.combinedUserPrompt(userPrompt: project?.prompt ?? "", promptAdditions: promptAdditions)
    }

    func layerHasRenderableContent(_ layerID: UUID) -> Bool {
        guard let layer = project?.layers.first(where: { $0.id == layerID }) else { return false }
        return !layer.strokes.isEmpty || layerAssetData[layerID] != nil
    }

    func loadIfNeeded(defaultModel: String = AppConfig.defaultModel) {
        guard !didLoadProject else { return }
        didLoadProject = true
        do {
            let state = try store?.loadLastProjectOrCreateDefault(defaultModel: defaultModel)
                ?? ConceptProjectState(project: ConceptProject.emptyDefault(), layerAssetData: [:])
            project = state.project
            layerAssetData = state.layerAssetData
            selectedLayerID = state.project.layers.first?.id
            syncBrushSettingsFromSelection()
            rebuildCanvasComposite()
        } catch {
            let fallback = ConceptProject.emptyDefault()
            project = fallback
            layerAssetData = [:]
            selectedLayerID = fallback.layers.first?.id
            syncBrushSettingsFromSelection()
            rebuildCanvasComposite()
        }
    }

    func createNewProject(defaultModel: String = AppConfig.defaultModel) {
        clearMessages()
        undoStack.removeAll()
        redoStack.removeAll()
        var fresh = ConceptProject.emptyDefault()
        fresh.model = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppConfig.defaultModel : defaultModel
        project = fresh
        layerAssetData = [:]
        selectedLayerID = fresh.layers.first?.id
        syncBrushSettingsFromSelection()
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func selectLayer(_ layerID: UUID) {
        selectedLayerID = layerID
        syncBrushSettingsFromSelection()
    }

    func setPrompt(_ prompt: String) {
        guard var project else { return }
        project.prompt = prompt
        project.updatedAt = Date()
        self.project = project
        persistCurrentProject()
    }

    func setModel(_ model: String) {
        guard var project else { return }
        project.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if project.model.isEmpty {
            project.model = AppConfig.defaultModel
        }
        project.updatedAt = Date()
        self.project = project
        persistCurrentProject()
    }

    func setResolutionSelection(_ selection: ResolutionSelection) {
        guard var project else { return }
        project.resolutionSelection = selection
        project.updatedAt = Date()
        self.project = project
        persistCurrentProject()
    }

    func setAspectRatioSelection(_ selection: AspectRatioSelection) {
        guard var project else { return }
        project.aspectRatioSelection = selection
        project.updatedAt = Date()
        self.project = project
        persistCurrentProject()
    }

    func setImageCount(_ count: Int) {
        guard var project else { return }
        project.imageCount = min(max(count, 1), 4)
        project.updatedAt = Date()
        self.project = project
        persistCurrentProject()
    }

    func setReferenceMode(_ mode: ConceptReferenceMode) {
        guard var project else { return }
        project.referenceMode = mode
        project.updatedAt = Date()
        self.project = project
        persistCurrentProject()
    }

    func setCanvasAspectRatio(_ aspectRatio: ImageAspectRatio) {
        guard var project else { return }
        pushUndoSnapshot()
        project.canvasAspectRatio = aspectRatio
        if project.aspectRatioSelection == .auto {
            project.aspectRatioSelection = aspectRatio.defaultSelection
        }
        project.updatedAt = Date()
        self.project = project
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func setCanvasSizePreset(_ preset: ConceptCanvasSizePreset) {
        guard var project else { return }
        pushUndoSnapshot()
        project.canvasSizePreset = preset
        project.updatedAt = Date()
        self.project = project
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func setCanvasBackgroundColor(_ color: ConceptRGBAColor) {
        guard var project else { return }
        pushUndoSnapshot()
        project.canvasBackgroundColor = color
        project.updatedAt = Date()
        self.project = project
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func setLayerName(_ name: String, for layerID: UUID) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var project,
              let index = project.layers.firstIndex(where: { $0.id == layerID }) else { return }
        project.layers[index].name = trimmed
        project.layers[index].updatedAt = Date()
        project.updatedAt = Date()
        self.project = project
        persistCurrentProject()
    }

    func setSelectedLayerName(_ name: String) {
        guard let selectedLayerID else { return }
        setLayerName(name, for: selectedLayerID)
    }

    func setBrushColor(_ color: ConceptRGBAColor) {
        brushColor = color
        guard var project,
              let selectedLayerID,
              let index = project.layers.firstIndex(where: { $0.id == selectedLayerID }) else { return }
        project.layers[index].strokeColor = color
        project.layers[index].updatedAt = Date()
        project.updatedAt = Date()
        self.project = project
        persistCurrentProject()
    }

    func setBrushWidth(_ width: Double) {
        let normalizedWidth = min(max(width, 1), 64)
        brushWidth = normalizedWidth
        guard var project,
              let selectedLayerID,
              let index = project.layers.firstIndex(where: { $0.id == selectedLayerID }) else { return }
        project.layers[index].strokeWidth = normalizedWidth
        project.layers[index].updatedAt = Date()
        project.updatedAt = Date()
        self.project = project
        persistCurrentProject()
    }

    func setBrushOpacity(_ opacity: Double) {
        let normalizedOpacity = min(max(opacity, 0.05), 1)
        brushOpacity = normalizedOpacity
        guard var project,
              let selectedLayerID,
              let index = project.layers.firstIndex(where: { $0.id == selectedLayerID }) else { return }
        project.layers[index].opacity = normalizedOpacity
        project.layers[index].updatedAt = Date()
        project.updatedAt = Date()
        self.project = project
        persistCurrentProject()
    }

    func setZoomScale(_ zoom: CGFloat) {
        zoomScale = min(max(zoom, 0.25), 8)
    }

    func zoomIn() {
        setZoomScale(zoomScale * 1.15)
    }

    func zoomOut() {
        setZoomScale(zoomScale / 1.15)
    }

    func resetZoom() {
        zoomScale = 1
    }

    func addSketchLayer() {
        guard var project else { return }
        pushUndoSnapshot()
        let layer = ConceptLayer(
            name: nextLayerName(prefix: "Layer"),
            type: .sketch,
            isVisible: true,
            isLocked: false,
            zIndex: 0,
            strokeColor: brushColor,
            strokeWidth: brushWidth,
            opacity: brushOpacity
        )
        project.layers.insert(layer, at: 0)
        project.updatedAt = Date()
        self.project = project
        self.selectedLayerID = layer.id
        syncBrushSettingsFromSelection()
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func addReferenceLayer() {
        guard var project else { return }
        pushUndoSnapshot()
        let layer = ConceptLayer(
            name: nextLayerName(prefix: "Reference"),
            type: .referenceImage,
            isVisible: true,
            isLocked: true,
            zIndex: 0,
            strokeColor: .blue,
            strokeWidth: 4,
            opacity: 1
        )
        project.layers.insert(layer, at: 0)
        project.updatedAt = Date()
        self.project = project
        self.selectedLayerID = layer.id
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func duplicateLayer(_ layerID: UUID) {
        guard var project,
              let index = project.layers.firstIndex(where: { $0.id == layerID }) else { return }
        pushUndoSnapshot()
        var duplicated = project.layers[index]
        let originalID = duplicated.id
        duplicated.id = UUID()
        duplicated.name += " Copy"
        duplicated.updatedAt = Date()
        if duplicated.assetFilename != nil {
            duplicated.assetFilename = "layer-\(duplicated.id.uuidString).png"
            layerAssetData[duplicated.id] = layerAssetData[originalID]
        }
        project.layers.insert(duplicated, at: index)
        project.updatedAt = Date()
        self.project = project
        self.selectedLayerID = duplicated.id
        syncBrushSettingsFromSelection()
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func duplicateSelectedLayer() {
        guard let selectedLayerID else { return }
        duplicateLayer(selectedLayerID)
    }

    func deleteLayer(_ layerID: UUID) {
        guard var project,
              let index = project.layers.firstIndex(where: { $0.id == layerID }) else { return }
        pushUndoSnapshot()
        let removed = project.layers.remove(at: index)
        layerAssetData.removeValue(forKey: removed.id)
        if project.layers.isEmpty {
            let fallback = ConceptLayer(name: "Layer 1", type: .sketch, zIndex: 0)
            project.layers = [fallback]
            self.selectedLayerID = fallback.id
        } else {
            self.selectedLayerID = project.layers[min(index, project.layers.count - 1)].id
        }
        project.updatedAt = Date()
        self.project = project
        syncBrushSettingsFromSelection()
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func deleteSelectedLayer() {
        guard let selectedLayerID else { return }
        deleteLayer(selectedLayerID)
    }

    func moveLayerUp(_ layerID: UUID) {
        moveLayer(id: layerID, by: -1)
    }

    func moveLayerDown(_ layerID: UUID) {
        moveLayer(id: layerID, by: 1)
    }

    func moveLayer(id layerID: UUID, by offset: Int) {
        guard var project,
              let index = project.layers.firstIndex(where: { $0.id == layerID }) else { return }
        let targetIndex = index + offset
        guard project.layers.indices.contains(targetIndex) else { return }
        pushUndoSnapshot()
        let layer = project.layers.remove(at: index)
        project.layers.insert(layer, at: targetIndex)
        project.updatedAt = Date()
        self.project = project
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func moveLayer(_ layerID: UUID, to index: Int) {
        guard var project,
              let currentIndex = project.layers.firstIndex(where: { $0.id == layerID }) else { return }
        let clampedIndex = min(max(index, 0), project.layers.count - 1)
        guard clampedIndex != currentIndex else { return }
        if !isPreviewReorderingLayers {
            pushUndoSnapshot()
            isPreviewReorderingLayers = true
        }
        let layer = project.layers.remove(at: currentIndex)
        project.layers.insert(layer, at: clampedIndex)
        self.project = project
        rebuildCanvasComposite()
    }

    func finalizeLayerReorder() {
        guard isPreviewReorderingLayers, var project else { return }
        isPreviewReorderingLayers = false
        project.updatedAt = Date()
        self.project = project
        persistCurrentProject()
    }

    func toggleVisibility(for layerID: UUID) {
        guard var project,
              let index = project.layers.firstIndex(where: { $0.id == layerID }) else { return }
        pushUndoSnapshot()
        project.layers[index].isVisible.toggle()
        project.layers[index].updatedAt = Date()
        project.updatedAt = Date()
        self.project = project
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func toggleLock(for layerID: UUID) {
        guard var project,
              let index = project.layers.firstIndex(where: { $0.id == layerID }) else { return }
        pushUndoSnapshot()
        project.layers[index].isLocked.toggle()
        project.layers[index].updatedAt = Date()
        project.updatedAt = Date()
        self.project = project
        if self.selectedLayerID == layerID {
            syncBrushSettingsFromSelection()
        }
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func importReferenceImage(from url: URL) {
        guard supportedAttachmentExtensions.contains(url.pathExtension.lowercased()) else {
            setError(.unsupportedAttachmentFormat(url.lastPathComponent), language: .systemDefault())
            return
        }
        guard var project else { return }
        do {
            let rawData = try Data(contentsOf: url)
            guard let normalizedData = rasterizer.normalizedImportedImageData(rawData, canvasSize: canvasSize) else {
                throw AppError.conceptImportFailed(url.lastPathComponent)
            }
            pushUndoSnapshot()
            let shouldFillSelectedReference = {
                guard let selectedLayerID,
                      let index = project.layers.firstIndex(where: { $0.id == selectedLayerID }) else { return false }
                let layer = project.layers[index]
                return layer.type == .referenceImage && layer.assetFilename == nil && layer.strokes.isEmpty
            }()

            if shouldFillSelectedReference,
               let selectedLayerID,
               let index = project.layers.firstIndex(where: { $0.id == selectedLayerID }) {
                let filename = "layer-\(selectedLayerID.uuidString).png"
                project.layers[index].assetFilename = filename
                project.layers[index].updatedAt = Date()
                layerAssetData[selectedLayerID] = normalizedData
            } else {
                let layerID = UUID()
                let filename = "layer-\(layerID.uuidString).png"
                let layer = ConceptLayer(
                    id: layerID,
                    name: url.deletingPathExtension().lastPathComponent,
                    type: .referenceImage,
                    isVisible: true,
                    isLocked: true,
                    zIndex: 0,
                    strokeColor: .blue,
                    strokeWidth: 4,
                    opacity: 1,
                    strokes: [],
                    assetFilename: filename
                )
                project.layers.insert(layer, at: 0)
                layerAssetData[layerID] = normalizedData
                self.selectedLayerID = layerID
            }

            project.updatedAt = Date()
            self.project = project
            syncBrushSettingsFromSelection()
            rebuildCanvasComposite()
            persistCurrentProject()
        } catch let appError as AppError {
            setError(appError, language: .systemDefault())
        } catch {
            setError(.conceptImportFailed(error.localizedDescription), language: .systemDefault())
        }
    }

    func removeBackground(from layerID: UUID) {
        guard let layer = project?.layers.first(where: { $0.id == layerID }) else {
            setError(.conceptInvalidLayer, language: .systemDefault())
            return
        }
        guard removingBackgroundLayerID == nil else { return }

        let renderedData = rasterizer.renderLayerData(
            layer: layer,
            assetData: layerAssetData[layerID],
            canvasSize: canvasSize
        )
        guard let renderedData else {
            setError(.conceptBackgroundRemovalFailed("Layer has no image content."), language: .systemDefault())
            return
        }

        clearMessages()
        let currentCanvasSize = canvasSize
        let rasterizer = self.rasterizer
        removingBackgroundLayerID = layerID

        Task.detached(priority: .userInitiated) {
            do {
                let removedData = try rasterizer.removeBackgroundData(renderedData, canvasSize: currentCanvasSize)
                await MainActor.run {
                    guard var project = self.project,
                          let index = project.layers.firstIndex(where: { $0.id == layerID }) else {
                        self.removingBackgroundLayerID = nil
                        return
                    }

                    self.pushUndoSnapshot()
                    let filename = project.layers[index].assetFilename ?? "layer-\(layerID.uuidString).png"
                    self.layerAssetData[layerID] = removedData
                    project.layers[index].assetFilename = filename
                    project.layers[index].strokes.removeAll()
                    project.layers[index].updatedAt = Date()
                    project.updatedAt = Date()
                    self.project = project
                    self.rebuildCanvasComposite()
                    self.persistCurrentProject()
                    self.removingBackgroundLayerID = nil
                    self.successMessage = Localizer.string("status.concept_background_removed", language: .systemDefault())
                }
            } catch let error as AppError {
                await MainActor.run {
                    self.removingBackgroundLayerID = nil
                    self.setError(error, language: .systemDefault())
                }
            } catch {
                await MainActor.run {
                    self.removingBackgroundLayerID = nil
                    self.setError(.conceptBackgroundRemovalFailed(error.localizedDescription), language: .systemDefault())
                }
            }
        }
    }

    func commitStroke(points: [ConceptPoint]) {
        guard points.count >= 2,
              var project,
              let selectedLayerID,
              let index = project.layers.firstIndex(where: { $0.id == selectedLayerID }) else {
            return
        }
        guard project.layers[index].isEditable else { return }
        pushUndoSnapshot()
        let stroke = ConceptStroke(
            tool: activeTool,
            color: brushColor,
            width: brushWidth,
            opacity: brushOpacity,
            points: points
        )
        project.layers[index].strokes.append(stroke)
        project.layers[index].strokeColor = brushColor
        project.layers[index].strokeWidth = brushWidth
        project.layers[index].opacity = brushOpacity
        project.layers[index].updatedAt = Date()
        project.updatedAt = Date()
        self.project = project
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func fill(at point: ConceptPoint) {
        guard var project,
              let selectedLayerID,
              let index = project.layers.firstIndex(where: { $0.id == selectedLayerID }) else {
            return
        }
        guard project.layers[index].isEditable else { return }

        pushUndoSnapshot()
        let layer = project.layers[index]
        let renderedLayer = rasterizer.renderLayerData(
            layer: layer,
            assetData: layerAssetData[selectedLayerID],
            canvasSize: canvasSize
        )
        guard let filledData = rasterizer.floodFillData(
            imageData: renderedLayer,
            canvasSize: canvasSize,
            startPoint: point,
            fillColor: brushColor,
            opacity: brushOpacity
        ) else {
            return
        }

        let filename = layer.assetFilename ?? "layer-\(selectedLayerID.uuidString).png"
        layerAssetData[selectedLayerID] = filledData
        project.layers[index].assetFilename = filename
        project.layers[index].strokes.removeAll()
        project.layers[index].strokeColor = brushColor
        project.layers[index].strokeWidth = brushWidth
        project.layers[index].opacity = brushOpacity
        project.layers[index].updatedAt = Date()
        project.updatedAt = Date()
        self.project = project
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func clearSelectedLayerContent() {
        guard var project,
              let selectedLayerID,
              let index = project.layers.firstIndex(where: { $0.id == selectedLayerID }) else { return }
        guard project.layers[index].isEditable else { return }
        pushUndoSnapshot()
        project.layers[index].strokes.removeAll()
        if project.layers[index].type != .referenceImage {
            layerAssetData.removeValue(forKey: selectedLayerID)
            project.layers[index].assetFilename = nil
        }
        project.layers[index].updatedAt = Date()
        project.updatedAt = Date()
        self.project = project
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    func undo() {
        guard let current = currentState(), let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        restore(state: previous)
    }

    func redo() {
        guard let current = currentState(), let next = redoStack.popLast() else { return }
        undoStack.append(current)
        restore(state: next)
    }

    func generate(using appViewModel: MainViewModel) {
        clearMessages()
        guard let project else {
            setError(.conceptNoProjectLoaded, language: appViewModel.config.language)
            return
        }

        let trimmedPrompt = project.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            setError(.emptyPrompt, language: appViewModel.config.language)
            return
        }

        let selectedProvider = appViewModel.imageModelProvider(for: project.model)
        guard appViewModel.isProviderEnabled(selectedProvider) else {
            setError(appViewModel.providerDisabledError(for: selectedProvider), language: appViewModel.config.language)
            return
        }
        let apiKey = appViewModel.apiKey(for: selectedProvider)
        guard !apiKey.isEmpty else {
            setError(appViewModel.missingAPIKeyError(for: selectedProvider), language: appViewModel.config.language)
            return
        }

        let stateSnapshot = ConceptProjectState(project: project, layerAssetData: layerAssetData)
        let canvasSize = self.canvasSize
        let outputDirectory = URL(fileURLWithPath: appViewModel.config.defaultOutputDir, isDirectory: true)
        guard outputDirectory.path.hasPrefix("/") else {
            setError(.invalidOutputDirectory, language: appViewModel.config.language)
            return
        }

        isGenerating = true
        let startedAt = Date()

        Task { [weak self] in
            guard let self else { return }
            do {
                let generationInput = try Self.buildGenerationInput(
                    from: stateSnapshot,
                    activeLayerID: self.selectedLayerID,
                    canvasSize: canvasSize,
                    rasterizer: self.rasterizer,
                    prompt: trimmedPrompt,
                    conceptPromptAdditions: appViewModel.config.conceptPromptAdditions,
                    apiKey: apiKey,
                    model: appViewModel.apiModelName(for: project.model),
                    provider: selectedProvider,
                    resolutionMapper: self.resolutionMapper
                )

                let primaryRoute = try self.resolvePrimaryRoute(config: appViewModel.config)
                let routeUsed: NetworkRoute
                let fallbackUsed: Bool
                if generationInput.request.imageCount > 1 &&
                    (primaryRoute != .proxy || !appViewModel.config.allowDirectFallback) {
                    try await self.performIncrementalGeneration(
                        generationInput: generationInput,
                        appViewModel: appViewModel,
                        trimmedPrompt: trimmedPrompt,
                        outputDirectory: outputDirectory,
                        startedAt: startedAt,
                        route: primaryRoute,
                        proxyUsed: primaryRoute == .proxy,
                        fallbackUsed: false
                    )
                    await MainActor.run {
                        self.isGenerating = false
                    }
                    return
                }

                let result: GenerationResult
                if primaryRoute == .proxy {
                    do {
                        result = try await self.performGeneration(
                            request: generationInput.request,
                            provider: generationInput.provider,
                            config: appViewModel.config,
                            route: .proxy
                        )
                        routeUsed = .proxy
                        fallbackUsed = false
                    } catch let proxyError as AppError where proxyError.isRecoverableProxyFailure {
                        guard appViewModel.config.allowDirectFallback else {
                            throw AppError.directFallbackDisabled(proxyError.debugDetails)
                        }
                        result = try await self.performGeneration(
                            request: generationInput.request,
                            provider: generationInput.provider,
                            config: appViewModel.config,
                            route: .directFallback
                        )
                        routeUsed = .directFallback
                        fallbackUsed = true
                    }
                } else {
                    result = try await self.performGeneration(
                        request: generationInput.request,
                        provider: generationInput.provider,
                        config: appViewModel.config,
                        route: primaryRoute
                    )
                    routeUsed = primaryRoute
                    fallbackUsed = false
                }

                await MainActor.run {
                    var savedOutputURLs: [URL] = []

                    for (index, generatedImage) in result.images.enumerated() {
                        do {
                            let outputFilename = self.filenameGenerator.generateFilename(
                                prompt: trimmedPrompt,
                                outputDirectory: outputDirectory
                            )
                            let savedURL = try self.imagePersistenceService.savePNG(
                                imageData: generatedImage.imageData,
                                filename: outputFilename,
                                outputDirectory: outputDirectory,
                                metadata: ImageGenerationMetadata(
                                    prompt: generationInput.request.prompt,
                                    model: generationInput.request.model
                                )
                            )
                            savedOutputURLs.append(savedURL)

                            let resultLayerID = UUID()
                            let normalizedLayerData = self.composeResultLayerData(
                                generatedImageData: generatedImage.imageData,
                                generationInput: generationInput
                            ) ?? generatedImage.imageData
                            let resultLayer = ConceptLayer(
                                id: resultLayerID,
                                name: result.images.count > 1 ? "Result \(index + 1)" : "Result",
                                type: .result,
                                isVisible: true,
                                isLocked: false,
                                zIndex: 0,
                                strokeColor: self.brushColor,
                                strokeWidth: self.brushWidth,
                                opacity: self.brushOpacity,
                                strokes: [],
                                assetFilename: "layer-\(resultLayerID.uuidString).png"
                            )
                            _ = self.mergeGeneratedResultLayer(
                                projectID: generationInput.state.project.id,
                                layer: resultLayer,
                                data: normalizedLayerData
                            )
                        } catch let appError as AppError {
                            self.setError(appError, language: appViewModel.config.language)
                        } catch {
                            self.setError(.ioError(error.localizedDescription), language: appViewModel.config.language)
                        }
                    }

                    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    let configuredProxySummary = appViewModel.config.proxyEnabled
                        ? "\(appViewModel.config.proxyType.rawValue)://\(appViewModel.config.proxyHost):\(appViewModel.config.proxyPort)"
                        : nil
                    for (index, savedURL) in savedOutputURLs.enumerated() {
                        let modelText = index < result.images.count ? result.images[index].modelText : nil
                        let record = HistoryRecord(
                            mode: .edit,
                            prompt: trimmedPrompt,
                            resolution: generationInput.request.resolution,
                            inputImagePaths: [],
                            outputImagePath: savedURL.path,
                            status: .success,
                            errorMessage: nil,
                            durationMs: durationMs,
                            modelResponseText: modelText,
                            networkRoute: routeUsed,
                            proxyUsed: primaryRoute == .proxy,
                            fallbackUsed: fallbackUsed,
                            proxySummary: configuredProxySummary,
                            sourceMode: .concepting,
                            conceptProjectID: generationInput.context.projectID,
                            conceptLayerIDs: generationInput.context.lockedLayerIDs + generationInput.context.editableLayerIDs
                        )
                        appViewModel.appendExternalHistory(record)
                    }

                    if result.images.count > 1 {
                        self.successMessage = Localizer.string("status.success_saved_multiple", language: appViewModel.config.language, result.images.count)
                    } else if let firstOutput = savedOutputURLs.first {
                        self.successMessage = Localizer.string("status.success_saved", language: appViewModel.config.language, firstOutput.path)
                    }
                    appViewModel.postGenerationCompletionNotificationIfEnabled(imageCount: savedOutputURLs.count)
                    self.isGenerating = false
                }
            } catch let appError as AppError {
                await MainActor.run {
                    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    self.setError(appError, language: appViewModel.config.language)
                    let record = HistoryRecord(
                        mode: .edit,
                        prompt: trimmedPrompt,
                        resolution: self.resolutionMapper.resolve(prompt: trimmedPrompt, selection: project.resolutionSelection),
                        inputImagePaths: [],
                        outputImagePath: nil,
                        status: .error,
                        errorMessage: self.displayMessage(for: appError, language: appViewModel.config.language),
                        failureDiagnostics: appError.debugDetails.isEmpty ? nil : appError.debugDetails,
                        durationMs: durationMs,
                        modelResponseText: nil,
                        networkRoute: appViewModel.config.proxyEnabled ? .proxy : .directFallback,
                        proxyUsed: appViewModel.config.proxyEnabled,
                        fallbackUsed: false,
                        proxySummary: nil,
                        sourceMode: .concepting,
                        conceptProjectID: stateSnapshot.project.id,
                        conceptLayerIDs: stateSnapshot.project.layers.map(\.id)
                    )
                    appViewModel.appendExternalHistory(record)
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    let wrappedError = AppError.network(error.localizedDescription)
                    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    self.setError(wrappedError, language: appViewModel.config.language)
                    let record = HistoryRecord(
                        mode: .edit,
                        prompt: trimmedPrompt,
                        resolution: self.resolutionMapper.resolve(prompt: trimmedPrompt, selection: project.resolutionSelection),
                        inputImagePaths: [],
                        outputImagePath: nil,
                        status: .error,
                        errorMessage: self.displayMessage(for: wrappedError, language: appViewModel.config.language),
                        failureDiagnostics: wrappedError.debugDetails.isEmpty ? nil : wrappedError.debugDetails,
                        durationMs: durationMs,
                        modelResponseText: nil,
                        networkRoute: appViewModel.config.proxyEnabled ? .proxy : .directFallback,
                        proxyUsed: appViewModel.config.proxyEnabled,
                        fallbackUsed: false,
                        proxySummary: nil,
                        sourceMode: .concepting,
                        conceptProjectID: stateSnapshot.project.id,
                        conceptLayerIDs: stateSnapshot.project.layers.map(\.id)
                    )
                    appViewModel.appendExternalHistory(record)
                    self.isGenerating = false
                }
            }
        }
    }

    private func performIncrementalGeneration(
        generationInput: ConceptPreparedGenerationInput,
        appViewModel: MainViewModel,
        trimmedPrompt: String,
        outputDirectory: URL,
        startedAt: Date,
        route: NetworkRoute,
        proxyUsed: Bool,
        fallbackUsed: Bool
    ) async throws {
        let session = try networkClientProvider.makeSession(config: appViewModel.config, route: route)
        let requestTemplate: GenerationRequest = {
            var template = generationInput.request
            template.imageCount = 1
            return template
        }()

        var completedCount = 0
        var firstSavedPath: String?
        try await withThrowingTaskGroup(of: CompletedGeneratedLayerResult.self) { taskGroup in
            for index in 0..<generationInput.request.imageCount {
                taskGroup.addTask {
                    let singleResult: GenerationResult
                    switch generationInput.provider {
                    case .gemini:
                        let directClient = GeminiAPIClient()
                        singleResult = try await directClient.generateImage(
                            request: requestTemplate,
                            timeoutSec: appViewModel.config.requestTimeoutSec,
                            session: session,
                            route: route
                        )
                    case .openAI:
                        let directClient = OpenAIImageAPIClient()
                        singleResult = try await directClient.generateImage(
                            request: requestTemplate,
                            timeoutSec: appViewModel.config.requestTimeoutSec,
                            session: session,
                            route: route
                        )
                    case .openAICompatible:
                        let directClient = OpenAIImageAPIClient(baseURL: try await appViewModel.openAICompatibleBaseURL())
                        singleResult = try await directClient.generateImage(
                            request: requestTemplate,
                            timeoutSec: appViewModel.config.requestTimeoutSec,
                            session: session,
                            route: route
                        )
                    case .kie:
                        let directClient = KieAIImageAPIClient()
                        singleResult = try await directClient.generateImage(
                            request: requestTemplate,
                            timeoutSec: appViewModel.config.requestTimeoutSec,
                            session: session,
                            route: route
                        )
                    }
                    guard let firstImage = singleResult.images.first else {
                        throw AppError.noImageInResponse
                    }
                    return CompletedGeneratedLayerResult(index: index, image: firstImage)
                }
            }

            for try await completed in taskGroup {
                completedCount += 1

                let outputFilename = filenameGenerator.generateFilename(
                    prompt: trimmedPrompt,
                    outputDirectory: outputDirectory
                )
                let savedURL = try imagePersistenceService.savePNG(
                    imageData: completed.image.imageData,
                    filename: outputFilename,
                    outputDirectory: outputDirectory,
                    metadata: ImageGenerationMetadata(
                        prompt: generationInput.request.prompt,
                        model: generationInput.request.model
                    )
                )
                if firstSavedPath == nil {
                    firstSavedPath = savedURL.path
                }

                let resultLayerID = UUID()
                let normalizedLayerData = composeResultLayerData(
                    generatedImageData: completed.image.imageData,
                    generationInput: generationInput
                ) ?? completed.image.imageData
                let resultLayer = ConceptLayer(
                    id: resultLayerID,
                    name: generationInput.request.imageCount > 1 ? "Result \(completed.index + 1)" : "Result",
                    type: .result,
                    isVisible: true,
                    isLocked: false,
                    zIndex: 0,
                    strokeColor: brushColor,
                    strokeWidth: brushWidth,
                    opacity: brushOpacity,
                    strokes: [],
                    assetFilename: "layer-\(resultLayerID.uuidString).png"
                )
                _ = mergeGeneratedResultLayer(
                    projectID: generationInput.state.project.id,
                    layer: resultLayer,
                    data: normalizedLayerData
                )

                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                let configuredProxySummary = appViewModel.config.proxyEnabled
                    ? "\(appViewModel.config.proxyType.rawValue)://\(appViewModel.config.proxyHost):\(appViewModel.config.proxyPort)"
                    : nil
                let record = HistoryRecord(
                    mode: .edit,
                    prompt: trimmedPrompt,
                    resolution: generationInput.request.resolution,
                    inputImagePaths: [],
                    outputImagePath: savedURL.path,
                    status: .success,
                    errorMessage: nil,
                    durationMs: durationMs,
                    modelResponseText: completed.image.modelText,
                    networkRoute: route,
                    proxyUsed: proxyUsed,
                    fallbackUsed: fallbackUsed,
                    proxySummary: configuredProxySummary,
                    sourceMode: .concepting,
                    conceptProjectID: generationInput.context.projectID,
                    conceptLayerIDs: generationInput.context.lockedLayerIDs + generationInput.context.editableLayerIDs
                )
                appViewModel.appendExternalHistory(record)
            }
        }

        if completedCount > 1 {
            successMessage = Localizer.string("status.success_saved_multiple", language: appViewModel.config.language, completedCount)
        } else if let firstSavedPath {
            successMessage = Localizer.string("status.success_saved", language: appViewModel.config.language, firstSavedPath)
        }
        appViewModel.postGenerationCompletionNotificationIfEnabled(imageCount: completedCount)
    }

    private func currentState() -> ConceptProjectState? {
        guard let project else { return nil }
        return ConceptProjectState(project: project, layerAssetData: layerAssetData)
    }

    private func restore(state: ConceptProjectState) {
        project = state.project
        layerAssetData = state.layerAssetData
        selectedLayerID = state.project.layers.first?.id
        syncBrushSettingsFromSelection()
        rebuildCanvasComposite()
        persistCurrentProject()
    }

    @discardableResult
    func mergeGeneratedResultLayer(projectID: UUID, layer: ConceptLayer, data: Data) -> Bool {
        guard var currentProject = project, currentProject.id == projectID else {
            return false
        }

        layerAssetData[layer.id] = data
        currentProject.layers.insert(layer, at: 0)
        currentProject.updatedAt = Date()
        project = currentProject
        if selectedLayerID == nil {
            selectedLayerID = layer.id
            syncBrushSettingsFromSelection()
        }
        rebuildCanvasComposite()
        persistCurrentProject()
        return true
    }

    private func composeResultLayerData(
        generatedImageData: Data,
        generationInput: ConceptPreparedGenerationInput
    ) -> Data? {
        guard let generatedCropData = rasterizer.resizedImageData(
            generatedImageData,
            size: generationInput.roiRect.size
        ) else {
            return nil
        }

        if let isolatedObjectCropData = ((try? rasterizer.removeBackgroundData(
            generatedCropData,
            canvasSize: generationInput.roiRect.size
        )) ?? rasterizer.removeWhiteBackgroundData(generatedCropData)) {
            let isolatedPatchData = {
                let maxDimension = max(generationInput.roiRect.width, generationInput.roiRect.height)
                let coreSeedRadius = max(8, Int((maxDimension * 0.025).rounded()))
                let sketchEnvelopeRadius = max(coreSeedRadius + 14, Int((maxDimension * 0.09).rounded()))
                guard let foregroundMaskData = rasterizer.alphaMaskData(
                    imageData: isolatedObjectCropData,
                    canvasSize: generationInput.roiRect.size
                ),
                let sketchCoreSeedMaskData = rasterizer.dilatedMaskData(
                    maskData: generationInput.generateMaskCropData,
                    canvasSize: generationInput.roiRect.size,
                    dilationRadius: coreSeedRadius
                ),
                let sketchEnvelopeMaskData = rasterizer.dilatedMaskData(
                    maskData: generationInput.generateMaskCropData,
                    canvasSize: generationInput.roiRect.size,
                    dilationRadius: sketchEnvelopeRadius
                ),
                let protectOutsideSketchData = rasterizer.subtractMaskData(
                    primaryMaskData: generationInput.protectMaskCropData,
                    subtractingMaskData: sketchEnvelopeMaskData,
                    canvasSize: generationInput.roiRect.size
                ),
                let cleanedForegroundMaskData = rasterizer.subtractMaskData(
                    primaryMaskData: foregroundMaskData,
                    subtractingMaskData: protectOutsideSketchData,
                    canvasSize: generationInput.roiRect.size
                ) else {
                    return nil
                }

                let seededForegroundMaskData = rasterizer.intersectMaskData(
                    primaryMaskData: cleanedForegroundMaskData,
                    intersectingMaskData: sketchCoreSeedMaskData,
                    canvasSize: generationInput.roiRect.size
                )
                let connectedObjectMaskData = seededForegroundMaskData.flatMap {
                    rasterizer.connectedComponentMaskData(
                        sourceMaskData: cleanedForegroundMaskData,
                        seedMaskData: $0,
                        canvasSize: generationInput.roiRect.size,
                        dilationRadius: 1
                    )
                }
                let boundedObjectMaskData = connectedObjectMaskData ?? rasterizer.intersectMaskData(
                    primaryMaskData: cleanedForegroundMaskData,
                    intersectingMaskData: sketchEnvelopeMaskData,
                    canvasSize: generationInput.roiRect.size
                )
                guard let boundedObjectMaskData,
                      let resultObjectMaskData = rasterizer.dilatedMaskData(
                    maskData: boundedObjectMaskData,
                    canvasSize: generationInput.roiRect.size,
                    dilationRadius: 2
                ),
                let finalResultMaskData = rasterizer.intersectMaskData(
                    primaryMaskData: resultObjectMaskData,
                    intersectingMaskData: foregroundMaskData,
                    canvasSize: generationInput.roiRect.size
                ) else {
                    return nil
                }
                guard rasterizer.boundingBox(forMaskData: finalResultMaskData) != nil else { return nil }
                return rasterizer.maskedPatchData(
                    imageData: isolatedObjectCropData,
                    maskData: finalResultMaskData,
                    canvasSize: generationInput.roiRect.size
                )
            }() ?? isolatedObjectCropData
            return rasterizer.reinsertCropData(
                isolatedPatchData,
                roiRect: generationInput.roiRect,
                canvasSize: generationInput.canvasSize
            )
        }

        let fallbackMaskData = rasterizer.differenceMaskData(
            baseData: generationInput.baseCropData,
            generatedData: generatedCropData,
            canvasSize: generationInput.roiRect.size
        ) ?? generationInput.generateMaskCropData
        let finalCropData = rasterizer.blendedImageData(
            baseData: generationInput.baseCropData,
            generatedData: generatedCropData,
            maskData: fallbackMaskData,
            canvasSize: generationInput.roiRect.size
        ) ?? generatedCropData

        return rasterizer.reinsertCropData(
            finalCropData,
            roiRect: generationInput.roiRect,
            canvasSize: generationInput.canvasSize
        )
    }

    private func pushUndoSnapshot() {
        guard let state = currentState() else { return }
        undoStack.append(state)
        if undoStack.count > maxUndoSnapshots {
            undoStack.removeFirst(undoStack.count - maxUndoSnapshots)
        }
        redoStack.removeAll()
    }

    private func syncBrushSettingsFromSelection() {
        guard let selectedLayer else { return }
        brushColor = selectedLayer.strokeColor
        brushWidth = selectedLayer.strokeWidth
        brushOpacity = selectedLayer.opacity
    }

    private func persistCurrentProject() {
        guard let project else { return }
        let snapshot = ConceptProjectState(project: project, layerAssetData: layerAssetData)
        try? store?.save(snapshot)
    }

    private func rebuildCanvasComposite() {
        guard let project else {
            canvasCompositeImage = nil
            return
        }
        canvasCompositeImage = rasterizer.compositeCanvasImage(
            project: project,
            assetDataByLayer: layerAssetData,
            canvasSize: canvasSize
        )
    }

    private func nextLayerName(prefix: String) -> String {
        let existingNames = Set(layers.map(\.name))
        var index = 1
        while existingNames.contains("\(prefix) \(index)") {
            index += 1
        }
        return "\(prefix) \(index)"
    }

    private func resolvePrimaryRoute(config: AppConfig) throws -> NetworkRoute {
        if config.proxyEnabled {
            let validation = networkClientProvider.validate(config: config)
            if let error = validation.error {
                throw error
            }
            return .proxy
        }
        return .directFallback
    }

    private func performGeneration(
        request: GenerationRequest,
        provider: ModelProvider,
        config: AppConfig,
        route: NetworkRoute
    ) async throws -> GenerationResult {
        let session = try networkClientProvider.makeSession(config: config, route: route)
        if request.imageCount <= 1 {
            switch provider {
            case .gemini:
                return try await apiClient.generateImage(
                    request: request,
                    timeoutSec: config.requestTimeoutSec,
                    session: session,
                    route: route
                )
            case .openAI:
                return try await openAIImageAPIClient.generateImage(
                    request: request,
                    timeoutSec: config.requestTimeoutSec,
                    session: session,
                    route: route
                )
            case .openAICompatible:
                return try await OpenAIImageAPIClient(baseURL: openAICompatibleBaseURL(from: config))
                    .generateImage(
                        request: request,
                        timeoutSec: config.requestTimeoutSec,
                        session: session,
                        route: route
                    )
            case .kie:
                return try await KieAIImageAPIClient().generateImage(
                    request: request,
                    timeoutSec: config.requestTimeoutSec,
                    session: session,
                    route: route
                )
            }
        }
        switch provider {
        case .gemini:
            return try await apiClient.generateImagesBatch(
                request: request,
                timeoutSec: config.requestTimeoutSec,
                session: session,
                route: route
            )
        case .openAI:
            return try await withThrowingTaskGroup(of: GeneratedImageResult.self) { taskGroup in
                var images: [GeneratedImageResult] = []
                var template = request
                template.imageCount = 1
                for _ in 0..<request.imageCount {
                    taskGroup.addTask {
                        let directClient = OpenAIImageAPIClient()
                        let result = try await directClient.generateImage(
                            request: template,
                            timeoutSec: config.requestTimeoutSec,
                            session: session,
                            route: route
                        )
                        guard let firstImage = result.images.first else {
                            throw AppError.noImageInResponse
                        }
                        return firstImage
                    }
                }

                for try await image in taskGroup {
                    images.append(image)
                }

                guard !images.isEmpty else {
                    throw AppError.noImageInResponse
                }

                return GenerationResult(images: images, usedResolution: request.resolution)
            }
        case .openAICompatible:
            return try await withThrowingTaskGroup(of: GeneratedImageResult.self) { taskGroup in
                var images: [GeneratedImageResult] = []
                var template = request
                template.imageCount = 1
                let baseURL = try openAICompatibleBaseURL(from: config)
                for _ in 0..<request.imageCount {
                    taskGroup.addTask {
                        let directClient = OpenAIImageAPIClient(baseURL: baseURL)
                        let result = try await directClient.generateImage(
                            request: template,
                            timeoutSec: config.requestTimeoutSec,
                            session: session,
                            route: route
                        )
                        guard let firstImage = result.images.first else {
                            throw AppError.noImageInResponse
                        }
                        return firstImage
                    }
                }

                for try await image in taskGroup {
                    images.append(image)
                }

                guard !images.isEmpty else {
                    throw AppError.noImageInResponse
                }

                return GenerationResult(images: images, usedResolution: request.resolution)
            }
        case .kie:
            return try await withThrowingTaskGroup(of: GeneratedImageResult.self) { taskGroup in
                var images: [GeneratedImageResult] = []
                var template = request
                template.imageCount = 1
                for _ in 0..<request.imageCount {
                    taskGroup.addTask {
                        let directClient = KieAIImageAPIClient()
                        let result = try await directClient.generateImage(
                            request: template,
                            timeoutSec: config.requestTimeoutSec,
                            session: session,
                            route: route
                        )
                        guard let firstImage = result.images.first else {
                            throw AppError.noImageInResponse
                        }
                        return firstImage
                    }
                }

                for try await image in taskGroup {
                    images.append(image)
                }

                guard !images.isEmpty else {
                    throw AppError.noImageInResponse
                }

                return GenerationResult(images: images, usedResolution: request.resolution)
            }
        }
    }

    private func openAICompatibleBaseURL(from config: AppConfig) throws -> URL {
        var normalized = config.openAICompatibleBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            normalized = AppConfig.defaultOpenAICompatibleBaseURL
        }
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else {
            throw AppError.invalidOpenAICompatibleBaseURL(normalized)
        }
        return url
    }

    private func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    private func setError(_ error: AppError, language: AppLanguage) {
        errorMessage = displayMessage(for: error, language: language)
    }

    private func displayMessage(for error: AppError, language: AppLanguage) -> String {
        let message = userMessage(for: error, language: language)
        guard !error.debugDetails.isEmpty else { return message }
        return "\(message) (\(error.debugDetails))"
    }

    private func userMessage(for error: AppError, language: AppLanguage) -> String {
        switch error {
        case .serverError(let code):
            return Localizer.string("error.server_with_code", language: language, code)
        case .invalidConfiguration(let details):
            let base = Localizer.string("error.invalid_configuration", language: language)
            return details.isEmpty ? base : "\(base): \(details)"
        case .conceptImportFailed(let details):
            let base = Localizer.string("error.concept_import_failed", language: language)
            return details.isEmpty ? base : "\(base): \(details)"
        case .conceptBackgroundRemovalFailed(let details):
            let base = Localizer.string("error.concept_background_removal_failed", language: language)
            return details.isEmpty ? base : "\(base): \(details)"
        case .unsupportedAttachmentFormat(let filename):
            return Localizer.string("error.unsupported_attachment_format", language: language, filename)
        default:
            return Localizer.string(error.localizationKey, language: language)
        }
    }

    private static func buildGenerationInput(
        from state: ConceptProjectState,
        activeLayerID: UUID?,
        canvasSize: CGSize,
        rasterizer: ConceptRasterizer,
        prompt: String,
        conceptPromptAdditions: String,
        apiKey: String,
        model: String,
        provider: ModelProvider,
        resolutionMapper: PromptResolutionMapper
    ) throws -> ConceptPreparedGenerationInput {
        let project = state.project
        let hasContent: (ConceptLayer) -> Bool = { layer in
            !layer.strokes.isEmpty || state.layerAssetData[layer.id] != nil
        }
        let activeEditableLayer = activeLayerID.flatMap { id in
            project.layers.first(where: { $0.id == id && $0.isVisible && $0.isEditable && hasContent($0) })
        } ?? project.layers.first(where: { $0.isVisible && $0.isEditable && hasContent($0) })

        guard let activeEditableLayer else {
            throw AppError.conceptNoEditableRegion
        }
        let editableLayers = [activeEditableLayer]

        let preservedBaseLayers = project.layers.filter {
            $0.isVisible &&
            hasContent($0) &&
            $0.id != activeEditableLayer.id
        }
        guard !preservedBaseLayers.isEmpty else {
            throw AppError.conceptNoLockedBase
        }

        guard let baseCompositeData = rasterizer.compositeData(
            layers: project.layers,
            assetDataByLayer: state.layerAssetData,
            canvasSize: canvasSize,
            backgroundColor: nil,
            predicate: { layer in preservedBaseLayers.contains(where: { $0.id == layer.id }) }
        ) else {
            throw AppError.invalidResponse
        }

        guard let overlayCompositeData = rasterizer.compositeData(
            layers: project.layers,
            assetDataByLayer: state.layerAssetData,
            canvasSize: canvasSize,
            backgroundColor: nil,
            predicate: { layer in editableLayers.contains(where: { $0.id == layer.id }) }
        ) else {
            throw AppError.invalidResponse
        }

        guard let rawGenerateMaskData = rasterizer.maskData(
            layers: project.layers,
            assetDataByLayer: state.layerAssetData,
            canvasSize: canvasSize,
            dilationRadius: 10,
            predicate: { layer in editableLayers.contains(where: { $0.id == layer.id }) }
        ) else {
            throw AppError.conceptNoEditableRegion
        }

        guard let protectMaskData = rasterizer.contentAwareMaskData(
            layers: project.layers,
            assetDataByLayer: state.layerAssetData,
            canvasSize: canvasSize,
            dilationRadius: 3,
            predicate: { layer in preservedBaseLayers.contains(where: { $0.id == layer.id }) }
        ) else {
            throw AppError.invalidResponse
        }

        guard let subtractedEditMaskData = rasterizer.subtractMaskData(
            primaryMaskData: rawGenerateMaskData,
            subtractingMaskData: protectMaskData,
            canvasSize: canvasSize
        ) else {
            throw AppError.invalidResponse
        }

        let effectiveEditMaskData: Data
        if rasterizer.boundingBox(forMaskData: subtractedEditMaskData) != nil {
            effectiveEditMaskData = subtractedEditMaskData
        } else {
            effectiveEditMaskData = rawGenerateMaskData
        }

        guard let boundingBox = rasterizer.boundingBox(forMaskData: effectiveEditMaskData) else {
            throw AppError.conceptNoEditableRegion
        }
        let roiRect = rasterizer.expandedROIRect(for: boundingBox, paddingFraction: 0.2, canvasSize: canvasSize)

        guard let baseCropData = rasterizer.croppedImageData(baseCompositeData, rect: roiRect),
              let overlayCropData = rasterizer.croppedImageData(overlayCompositeData, rect: roiRect),
              let generateMaskCropData = rasterizer.croppedImageData(effectiveEditMaskData, rect: roiRect),
              let protectMaskCropData = rasterizer.croppedImageData(protectMaskData, rect: roiRect) else {
            throw AppError.invalidResponse
        }

        guard rasterizer.boundingBox(forMaskData: generateMaskCropData) != nil else {
            throw AppError.conceptNoEditableRegion
        }

        let resolvedResolution = resolutionMapper.resolve(prompt: prompt, selection: project.resolutionSelection)
        let request = GenerationRequest(
            mode: .edit,
            prompt: buildStaticConceptPrompt(
                userPrompt: prompt,
                promptAdditions: conceptPromptAdditions,
                referenceMode: project.referenceMode
            ),
            model: model,
            apiKey: apiKey,
            resolution: resolvedResolution,
            aspectRatio: ImageAspectRatio.closest(forWidth: roiRect.width, height: roiRect.height),
            inputImages: [
                GenerationInputImage(
                    fileURL: URL(fileURLWithPath: "/concept/base.png"),
                    filename: "base.png",
                    mimeType: "image/png",
                    data: baseCropData
                ),
                GenerationInputImage(
                    fileURL: URL(fileURLWithPath: "/concept/overlay.png"),
                    filename: "overlay.png",
                    mimeType: "image/png",
                    data: overlayCropData
                ),
                GenerationInputImage(
                    fileURL: URL(fileURLWithPath: "/concept/edit-mask.png"),
                    filename: "edit-mask.png",
                    mimeType: "image/png",
                    data: generateMaskCropData
                ),
                GenerationInputImage(
                    fileURL: URL(fileURLWithPath: "/concept/protect-mask.png"),
                    filename: "protect-mask.png",
                    mimeType: "image/png",
                    data: protectMaskCropData
                )
            ],
            imageCount: project.imageCount
        )

        let context = ConceptGenerationContext(
            projectID: project.id,
            lockedLayerIDs: preservedBaseLayers.map(\.id),
            editableLayerIDs: editableLayers.map(\.id)
        )
        return ConceptPreparedGenerationInput(
            state: state,
            request: request,
            provider: provider,
            context: context,
            canvasSize: canvasSize,
            roiRect: roiRect,
            baseCropData: baseCropData,
            generateMaskCropData: generateMaskCropData,
            protectMaskCropData: protectMaskCropData
        )
    }

    private static func buildStaticConceptPrompt(
        userPrompt: String,
        promptAdditions: String,
        referenceMode: ConceptReferenceMode
    ) -> String {
        let combinedUserPrompt = combinedUserPrompt(userPrompt: userPrompt, promptAdditions: promptAdditions)
        let modeInstruction: String
        switch referenceMode {
        case .strictPreserve:
            modeInstruction = """
STRICT PRESERVE MODE:
- Keep the locked/base image unchanged outside the editable region.
- Match the overlay sketch as closely as possible in silhouette, placement, contour, and proportions.
- Prefer preservation over creativity.
"""
        case .balanced:
            modeInstruction = """
BALANCED MODE:
- Preserve the locked/base image outside the editable region.
- Respect the overlay sketch strongly, but allow moderate natural integration of materials and details.
- Keep the result close to the reference while remaining visually coherent.
"""
        case .creative:
            modeInstruction = """
CREATIVE MODE:
- Preserve the locked/base image outside the editable region.
- Use the overlay sketch as a strong guide, but allow more creative interpretation inside the editable region.
- You may refine form, detailing, and integration as long as the intended placement is respected.
"""
        }
        return """
Use the provided images as a concept-editing crop stack.
Image 1 is the preserved base crop built from locked/reference layers. Image 2 is the editable overlay/sketch crop.
Image 3 is the editable region mask. Image 4 is the protected region mask that must remain unchanged.
Modify only the editable masked region. Preserve the base outside the editable mask exactly as much as possible.
Protected pixels must remain unchanged. Do not redraw or alter protected/base regions.
Respect the shape, contours, silhouette, and placement from the overlay image.
\(modeInstruction)

USER PROMPT:
\(combinedUserPrompt)
"""
    }

    nonisolated static func combinedUserPrompt(userPrompt: String, promptAdditions: String) -> String {
        let trimmedPrompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPromptAdditions = promptAdditions.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPrompt.isEmpty else { return "" }
        guard !trimmedPromptAdditions.isEmpty else { return trimmedPrompt }

        let leadingCharacter = trimmedPromptAdditions.first
        let shouldAppendDirectly = leadingCharacter.map { ",.;:!?)]}".contains($0) } ?? false
        if shouldAppendDirectly {
            return "\(trimmedPrompt)\(trimmedPromptAdditions)"
        }

        return "\(trimmedPrompt) \(trimmedPromptAdditions)"
    }
}

private struct ConceptPreparedGenerationInput {
    let state: ConceptProjectState
    let request: GenerationRequest
    let provider: ModelProvider
    let context: ConceptGenerationContext
    let canvasSize: CGSize
    let roiRect: CGRect
    let baseCropData: Data
    let generateMaskCropData: Data
    let protectMaskCropData: Data
}

extension ImageAspectRatio {
    var defaultSelection: AspectRatioSelection {
        switch self {
        case .square:
            return .square
        case .landscape4x3:
            return .landscape4x3
        case .portrait3x4:
            return .portrait3x4
        case .landscape3x2:
            return .landscape3x2
        case .portrait2x3:
            return .portrait2x3
        case .landscape16x9:
            return .landscape16x9
        case .portrait9x16:
            return .portrait9x16
        case .landscape21x9:
            return .landscape21x9
        case .portrait9x21:
            return .portrait9x21
        }
    }
}
