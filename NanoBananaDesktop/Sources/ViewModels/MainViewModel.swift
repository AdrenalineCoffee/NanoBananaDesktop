import AppKit
import Foundation
import ImageIO
import SwiftUI

enum ModelRefreshTrigger {
    case onAppear
    case manual
    case keyChanged
}

enum HistoryReuseOutcome: Equatable {
    case restoredAttachments(Int)
    case promptOnlyMissingFiles(missingPaths: [String])
    case promptOnlyNoAttachments
}

@MainActor
final class MainViewModel: ObservableObject {
    @Published var config: AppConfig
    @Published var prompt: String = ""
    @Published var resolutionSelection: ResolutionSelection = .k1
    @Published var aspectRatioSelection: AspectRatioSelection = .auto
    @Published var imageCountSelection: Int = 1
    @Published var isImageSettingsExpanded: Bool = true
    @Published var attachedImages: [AttachedImage] = [] {
        didSet {
            autoDetectedAspectRatio = detectSourceAspectRatio(from: attachedImages)
        }
    }
    @Published var pendingMentionInsert: String?
    @Published private(set) var autoDetectedAspectRatio: ImageAspectRatio?

    @Published var isGenerating: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var startupWarning: String?
    @Published var modelResponseText: String?
    @Published var lastOutputPath: String?
    @Published var lastOutputPaths: [String] = []
    @Published var lastGeneratedImage: NSImage?
    @Published var lastGeneratedImages: [NSImage] = []
    @Published var availableImageModels: [ModelCatalogItem] = []
    @Published var availableTextModels: [ModelCatalogItem] = []
    @Published var isLoadingModels: Bool = false
    @Published var modelCatalogErrorMessage: String?
    @Published var isCheckingAPIAvailability: Bool = false
    @Published var apiAvailabilityMessage: String?
    @Published var apiAvailabilityMessageIsError: Bool = false
    @Published var isEnhancingPrompt: Bool = false
    @Published var isGeneratingPromptFromImage: Bool = false

    @Published var history: [HistoryRecord] = []
    @Published var historyFilter: HistoryFilter = .all
    @Published var historyRouteFilter: HistoryRouteFilter = .all

    private let fileManager: FileManager
    private let configStore: AppConfigStore?
    private let historyStore: HistoryStore?
    private let resolutionMapper: PromptResolutionMapper
    private let filenameGenerator: FilenameGenerator
    private let imagePersistenceService: ImagePersistenceService
    private let apiClient: GeminiAPIClient
    private let modelCatalogClient: GeminiModelCatalogClient
    private let networkClientProvider: NetworkClientProvider
    private let mentionService: AttachmentMentionService

    private let supportedAttachmentExtensions = Set(["png", "jpg", "jpeg", "webp"])
    private var modelCatalogCache: [String: [ModelCatalogItem]] = [:]
    private var lastSavedAPIKey: String = ""

    init(
        fileManager: FileManager = .default,
        configStore: AppConfigStore? = nil,
        historyStore: HistoryStore? = nil,
        resolutionMapper: PromptResolutionMapper = PromptResolutionMapper(),
        filenameGenerator: FilenameGenerator = FilenameGenerator(),
        imagePersistenceService: ImagePersistenceService = ImagePersistenceService(),
        apiClient: GeminiAPIClient = GeminiAPIClient(),
        modelCatalogClient: GeminiModelCatalogClient = GeminiModelCatalogClient(),
        networkClientProvider: NetworkClientProvider = ProxySessionFactory(),
        mentionService: AttachmentMentionService = AttachmentMentionService()
    ) {
        self.fileManager = fileManager
        self.resolutionMapper = resolutionMapper
        self.filenameGenerator = filenameGenerator
        self.imagePersistenceService = imagePersistenceService
        self.apiClient = apiClient
        self.modelCatalogClient = modelCatalogClient
        self.networkClientProvider = networkClientProvider
        self.mentionService = mentionService

        let loadedConfigStore = configStore ?? (try? AppConfigStore(fileManager: fileManager))
        self.configStore = loadedConfigStore
        let loadedHistoryStore = historyStore ?? (try? HistoryStore(fileManager: fileManager))
        self.historyStore = loadedHistoryStore

        if let loadedConfigStore {
            let result = loadedConfigStore.load()
            self.config = result.config
            if result.recoveredFromCorruption {
                self.startupWarning = localizedStatic("warning.config_recovered", language: result.config.language)
            }
        } else {
            self.config = AppConfig.defaultValue(fileManager: fileManager)
            self.startupWarning = localizedStatic("warning.config_store_unavailable", language: self.config.language)
        }

        if let loadedHistoryStore {
            self.history = loadedHistoryStore.load()
        }

        self.lastSavedAPIKey = self.config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var filteredHistory: [HistoryRecord] {
        history
            .filter { historyItem in
                switch historyFilter {
                case .all:
                    return true
                case .success:
                    return historyItem.status == .success
                case .error:
                    return historyItem.status == .error
                }
            }
            .filter { historyItem in
                switch historyRouteFilter {
                case .all:
                    return true
                case .proxy:
                    return historyItem.networkRoute == .proxy
                case .directFallback:
                    return historyItem.networkRoute == .directFallback
                }
            }
    }

    var canGenerate: Bool {
        !isGenerating &&
            !isGeneratingPromptFromImage &&
            !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canEnhancePrompt: Bool {
        !isEnhancingPrompt &&
            !isGeneratingPromptFromImage &&
            !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resolutionSliderValue: Double {
        get {
            switch resolutionSelection {
            case .k2:
                return 1
            case .k4:
                return 2
            case .auto, .k1:
                return 0
            }
        }
        set {
            if newValue < 0.5 {
                resolutionSelection = .k1
            } else if newValue < 1.5 {
                resolutionSelection = .k2
            } else {
                resolutionSelection = .k4
            }
        }
    }

    var resolutionValueLabel: String {
        switch resolutionSelection {
        case .k2:
            return ImageResolution.k2.rawValue
        case .k4:
            return ImageResolution.k4.rawValue
        case .auto, .k1:
            return ImageResolution.k1.rawValue
        }
    }

    var imageCountSliderValue: Double {
        get { Double(imageCountSelection) }
        set { imageCountSelection = min(max(Int(newValue.rounded()), 1), 4) }
    }

    var imageCountValueLabel: String {
        "\(imageCountSelection)"
    }

    var resolvedAspectRatio: ImageAspectRatio {
        if let manual = aspectRatioSelection.manualAspectRatio {
            return manual
        }
        return autoDetectedAspectRatio ?? .square
    }

    var aspectRatioAutoDescription: String {
        localized("main.aspect_ratio_auto_value", resolvedAspectRatio.rawValue)
    }

    var selectableImageModels: [ModelCatalogItem] {
        mergedModelCatalog(models: availableImageModels, with: config.model)
    }

    var selectableTextModels: [ModelCatalogItem] {
        mergedModelCatalog(models: availableTextModels, with: config.promptEnhancementModel)
    }

    var hasOutputToReveal: Bool {
        !lastOutputPaths.isEmpty
    }

    var proxyValidationResult: ProxyValidationResult {
        networkClientProvider.validate(config: config)
    }

    var proxyStatusKey: String {
        if !config.proxyEnabled {
            return "proxy.status.disabled"
        }

        if proxyValidationResult.isValid {
            return "proxy.status.ready"
        }

        return "proxy.status.invalid"
    }

    var proxyStatusSymbol: String {
        if !config.proxyEnabled {
            return "network.slash"
        }

        if proxyValidationResult.isValid {
            return "checkmark.shield"
        }

        return "exclamationmark.triangle"
    }

    var proxySummary: String {
        guard config.proxyEnabled else {
            return localized("proxy.status.disabled")
        }

        let host = config.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return localized("proxy.summary.missing")
        }

        return "\(config.proxyType.rawValue.uppercased()) • \(host):\(config.proxyPort)"
    }

    func localized(_ key: String, _ args: CVarArg...) -> String {
        Localizer.string(key, language: config.language, args)
    }

    func handleMainViewAppeared() {
        refreshAvailableModels(trigger: .onAppear)
    }

    func modelTitle(for item: ModelCatalogItem) -> String {
        if item.isCustomFallback {
            return localized("main.model_custom", item.name)
        }

        if item.displayName.isEmpty {
            return item.name
        }

        if item.displayName.caseInsensitiveCompare(item.name) == .orderedSame {
            return item.displayName
        }

        return "\(item.displayName) (\(item.name))"
    }

    func refreshAvailableModels(trigger: ModelRefreshTrigger = .manual) {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.refreshAvailableModelsAsync(trigger: trigger)
        }
    }

    func applyModelCatalog(_ models: [ModelCatalogItem]) {
        availableImageModels = sortedModelCatalog(models, selectedModel: config.model)
    }

    func applyTextModelCatalog(_ models: [ModelCatalogItem]) {
        availableTextModels = sortedModelCatalog(models, selectedModel: config.promptEnhancementModel)
    }

    func saveSettings() {
        clearTransientMessages()

        let normalizedModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedModel.lowercased().hasPrefix("models/") {
            config.model = String(normalizedModel.dropFirst("models/".count))
        } else {
            config.model = normalizedModel
        }
        if config.model.isEmpty {
            config.model = AppConfig.defaultModel
        }

        let normalizedPromptModel = config.promptEnhancementModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedPromptModel.lowercased().hasPrefix("models/") {
            config.promptEnhancementModel = String(normalizedPromptModel.dropFirst("models/".count))
        } else {
            config.promptEnhancementModel = normalizedPromptModel.isEmpty
                ? AppConfig.defaultPromptEnhancementModel
                : normalizedPromptModel
        }

        let normalizedInstruction = config.promptEnhancementInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        config.promptEnhancementInstruction = normalizedInstruction.isEmpty
            ? AppConfig.defaultPromptEnhancementInstruction
            : normalizedInstruction

        let normalizedPromptFromImageInstruction = config.promptFromImageInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        config.promptFromImageInstruction = normalizedPromptFromImageInstruction.isEmpty
            ? AppConfig.defaultPromptFromImageInstruction
            : normalizedPromptFromImageInstruction

        let updatedAPIKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let didAPIKeyChange = updatedAPIKey != lastSavedAPIKey

        if config.proxyEnabled {
            let validation = proxyValidationResult
            if let error = validation.error {
                setError(error)
                return
            }
        }

        do {
            try configStore?.save(config)
            lastSavedAPIKey = updatedAPIKey
            if didAPIKeyChange {
                refreshAvailableModels(trigger: .keyChanged)
            }
        } catch let appError as AppError {
            setError(appError)
        } catch {
            setError(.ioError(error.localizedDescription))
        }
    }

    func setOutputDirectory(path: String) {
        config.defaultOutputDir = path
        saveSettings()
    }

    func setLanguage(_ language: AppLanguage) {
        config.language = language
        saveSettings()
    }

    func clearTransientMessages() {
        errorMessage = nil
        successMessage = nil
        modelResponseText = nil
    }

    func checkAPIAvailability() {
        Task { [weak self] in
            guard let self else {
                return
            }
            await self.checkAPIAvailabilityAsync()
        }
    }

    func handleDroppedImageURLs(_ urls: [URL]) {
        let buildResult = buildAttachments(from: urls, existingAttachments: attachedImages)
        if !buildResult.attachments.isEmpty {
            attachedImages.append(contentsOf: buildResult.attachments)
            errorMessage = nil
        } else if let firstError = buildResult.errors.first {
            setError(firstError)
        }
    }

    func removeAttachment(id: UUID) {
        attachedImages.removeAll { $0.id == id }
    }

    func requestMentionInsert(for attachment: AttachedImage) {
        pendingMentionInsert = attachment.mentionToken
    }

    @discardableResult
    func reuseFromHistory(_ record: HistoryRecord) -> HistoryReuseOutcome {
        clearTransientMessages()
        prompt = record.prompt
        pendingMentionInsert = nil
        attachedImages = []

        let normalizedPaths = record.inputImagePaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedPaths.isEmpty else {
            successMessage = localized("history.reuse_prompt_only_no_attachments")
            return .promptOnlyNoAttachments
        }

        let fileURLs = normalizedPaths.map { URL(fileURLWithPath: $0) }
        let buildResult = buildAttachments(from: fileURLs, existingAttachments: [])
        if !buildResult.errors.isEmpty {
            let missingPaths = normalizedPaths.filter { path in
                let url = URL(fileURLWithPath: path)
                return !fileManager.fileExists(atPath: url.path) || !fileManager.isReadableFile(atPath: url.path)
            }

            let unavailablePaths = missingPaths.isEmpty
                ? normalizedPaths
                : missingPaths

            errorMessage = localized(
                "history.reuse_prompt_only_missing_files",
                unavailablePaths.joined(separator: ", ")
            )
            return .promptOnlyMissingFiles(missingPaths: unavailablePaths)
        }

        attachedImages = buildResult.attachments
        successMessage = localized("history.reuse_loaded", buildResult.attachments.count)
        return .restoredAttachments(buildResult.attachments.count)
    }

    func revealLastOutputInFinder() {
        guard !lastOutputPaths.isEmpty else {
            return
        }

        let urls = lastOutputPaths.map { URL(fileURLWithPath: $0) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func generate() {
        clearTransientMessages()

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            setError(.emptyPrompt)
            return
        }

        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            setError(.missingAPIKey)
            return
        }

        let outputDirectory = URL(fileURLWithPath: config.defaultOutputDir, isDirectory: true)
        guard outputDirectory.path.hasPrefix("/") else {
            setError(.invalidOutputDirectory)
            return
        }

        let resolvedResolution = resolutionMapper.resolve(prompt: trimmedPrompt, selection: resolutionSelection)
        let requestAspectRatio = resolvedAspectRatio

        let inputImages: [GenerationInputImage]
        do {
            inputImages = try loadInputImages(from: attachedImages)
        } catch let appError as AppError {
            setError(appError)
            return
        } catch {
            setError(.ioError(error.localizedDescription))
            return
        }

        let modeForHistory: GenerationMode = inputImages.isEmpty ? .generate : .edit
        let inputPaths = inputImages.map(\.fileURL.path)

        let request = GenerationRequest(
            mode: modeForHistory,
            prompt: trimmedPrompt,
            model: config.model,
            apiKey: apiKey,
            resolution: resolvedResolution,
            aspectRatio: requestAspectRatio,
            inputImages: inputImages,
            imageCount: imageCountSelection
        )

        let configuredProxySummary: String?
        if config.proxyEnabled {
            let trimmedProxyHost = config.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
            configuredProxySummary = trimmedProxyHost.isEmpty
                ? nil
                : "\(config.proxyType.rawValue)://\(trimmedProxyHost):\(config.proxyPort)"
        } else {
            configuredProxySummary = nil
        }

        isGenerating = true
        let startedAt = Date()

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let primaryRoute = try self.resolvePrimaryRoute()

                var routeUsed = primaryRoute
                var fallbackUsed = false

                let result: GenerationResult
                if primaryRoute == .proxy {
                    do {
                        result = try await self.performGeneration(request: request, route: .proxy)
                    } catch let proxyError as AppError where proxyError.isRecoverableProxyFailure {
                        guard self.config.allowDirectFallback else {
                            throw AppError.directFallbackDisabled(proxyError.debugDetails)
                        }

                        routeUsed = .directFallback
                        fallbackUsed = true
                        result = try await self.performGeneration(request: request, route: .directFallback)
                    }
                } else {
                    result = try await self.performGeneration(request: request, route: primaryRoute)
                }

                var savedURLs: [URL] = []
                var renderedImages: [NSImage] = []

                for generatedImage in result.images {
                    let imageFilename = filenameGenerator.generateFilename(
                        prompt: trimmedPrompt,
                        outputDirectory: outputDirectory
                    )
                    let savedURL = try self.imagePersistenceService.savePNG(
                        imageData: generatedImage.imageData,
                        filename: imageFilename,
                        outputDirectory: outputDirectory
                    )
                    savedURLs.append(savedURL)

                    if let image = NSImage(contentsOf: savedURL) {
                        renderedImages.append(image)
                    }
                }

                guard let firstSavedURL = savedURLs.first else {
                    throw AppError.noImageInResponse
                }

                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                self.lastOutputPaths = savedURLs.map(\.path)
                self.lastOutputPath = firstSavedURL.path
                self.lastGeneratedImages = renderedImages
                self.lastGeneratedImage = renderedImages.first
                if savedURLs.count == 1 {
                    self.successMessage = self.localized("status.success_saved", firstSavedURL.path)
                } else {
                    self.successMessage = self.localized("status.success_saved_multiple", savedURLs.count)
                }
                let mergedModelText = result.images
                    .compactMap(\.modelText)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n\n")
                self.modelResponseText = mergedModelText.isEmpty ? nil : mergedModelText

                for (index, savedURL) in savedURLs.enumerated() {
                    let modelText = index < result.images.count ? result.images[index].modelText : nil
                    self.appendHistory(
                        HistoryRecord(
                            mode: modeForHistory,
                            prompt: trimmedPrompt,
                            resolution: resolvedResolution,
                            inputImagePaths: inputPaths,
                            outputImagePath: savedURL.path,
                            status: .success,
                            errorMessage: nil,
                            durationMs: durationMs,
                            modelResponseText: modelText,
                            networkRoute: routeUsed,
                            proxyUsed: primaryRoute == .proxy,
                            fallbackUsed: fallbackUsed,
                            proxySummary: configuredProxySummary
                        )
                    )
                }
            } catch let appError as AppError {
                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                self.setError(appError)
                self.appendHistory(
                    HistoryRecord(
                        mode: modeForHistory,
                        prompt: trimmedPrompt,
                        resolution: resolvedResolution,
                        inputImagePaths: inputPaths,
                        outputImagePath: nil,
                        status: .error,
                        errorMessage: self.displayMessage(for: appError),
                        failureDiagnostics: appError.debugDetails.isEmpty ? nil : appError.debugDetails,
                        durationMs: durationMs,
                        modelResponseText: nil,
                        networkRoute: self.config.proxyEnabled ? .proxy : .directFallback,
                        proxyUsed: self.config.proxyEnabled,
                        fallbackUsed: false,
                        proxySummary: configuredProxySummary
                    )
                )
            } catch {
                let wrappedError = AppError.network(error.localizedDescription)
                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                self.setError(wrappedError)
                self.appendHistory(
                    HistoryRecord(
                        mode: modeForHistory,
                        prompt: trimmedPrompt,
                        resolution: resolvedResolution,
                        inputImagePaths: inputPaths,
                        outputImagePath: nil,
                        status: .error,
                        errorMessage: self.displayMessage(for: wrappedError),
                        failureDiagnostics: wrappedError.debugDetails.isEmpty ? nil : wrappedError.debugDetails,
                        durationMs: durationMs,
                        modelResponseText: nil,
                        networkRoute: self.config.proxyEnabled ? .proxy : .directFallback,
                        proxyUsed: self.config.proxyEnabled,
                        fallbackUsed: false,
                        proxySummary: configuredProxySummary
                    )
                )
            }

            self.isGenerating = false
        }
    }

    func enhancePrompt() {
        clearTransientMessages()

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            setError(.emptyPrompt)
            return
        }

        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            setError(.missingAPIKey)
            return
        }

        let enhancementModel = config.promptEnhancementModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !enhancementModel.isEmpty else {
            setError(.invalidConfiguration("Prompt enhancement model cannot be empty"))
            return
        }

        let enhancementInput = promptEnhancementInput(for: trimmedPrompt)
        isEnhancingPrompt = true

        Task { [weak self] in
            guard let self else {
                return
            }

            defer { self.isEnhancingPrompt = false }

            do {
                let primaryRoute = try self.resolvePrimaryRoute()

                let improvedPrompt: String
                if primaryRoute == .proxy {
                    do {
                        improvedPrompt = try await self.performPromptEnhancement(
                            prompt: enhancementInput,
                            model: enhancementModel,
                            apiKey: apiKey,
                            route: .proxy
                        )
                    } catch let proxyError as AppError where proxyError.isRecoverableProxyFailure {
                        guard self.config.allowDirectFallback else {
                            throw AppError.directFallbackDisabled(proxyError.debugDetails)
                        }

                        improvedPrompt = try await self.performPromptEnhancement(
                            prompt: enhancementInput,
                            model: enhancementModel,
                            apiKey: apiKey,
                            route: .directFallback
                        )
                    }
                } else {
                    improvedPrompt = try await self.performPromptEnhancement(
                        prompt: enhancementInput,
                        model: enhancementModel,
                        apiKey: apiKey,
                        route: primaryRoute
                    )
                }

                let normalizedImprovedPrompt = improvedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedImprovedPrompt.isEmpty else {
                    throw AppError.noTextInResponse
                }

                self.prompt = normalizedImprovedPrompt
                self.successMessage = self.localized("status.prompt_enhanced")
            } catch let appError as AppError {
                self.setError(appError)
            } catch {
                self.setError(.network(error.localizedDescription))
            }
        }
    }

    func generatePromptFromImage(from droppedURLs: [URL]) {
        clearTransientMessages()

        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            setError(.missingAPIKey)
            return
        }

        let promptModel = config.promptEnhancementModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptModel.isEmpty else {
            setError(.invalidConfiguration("Prompt model cannot be empty"))
            return
        }

        guard let inputImage = firstValidPromptFromImageInput(from: droppedURLs) else {
            setError(.promptFromImageNoValidFile)
            return
        }

        let instruction = config.promptFromImageInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppConfig.defaultPromptFromImageInstruction
            : config.promptFromImageInstruction.trimmingCharacters(in: .whitespacesAndNewlines)

        isGeneratingPromptFromImage = true

        Task { [weak self] in
            guard let self else {
                return
            }

            defer { self.isGeneratingPromptFromImage = false }

            do {
                let primaryRoute = try self.resolvePrimaryRoute()

                let generatedPrompt: String
                if primaryRoute == .proxy {
                    do {
                        generatedPrompt = try await self.performPromptFromImage(
                            prompt: instruction,
                            model: promptModel,
                            apiKey: apiKey,
                            images: [inputImage],
                            route: .proxy
                        )
                    } catch let proxyError as AppError where proxyError.isRecoverableProxyFailure {
                        guard self.config.allowDirectFallback else {
                            throw AppError.directFallbackDisabled(proxyError.debugDetails)
                        }

                        generatedPrompt = try await self.performPromptFromImage(
                            prompt: instruction,
                            model: promptModel,
                            apiKey: apiKey,
                            images: [inputImage],
                            route: .directFallback
                        )
                    }
                } else {
                    generatedPrompt = try await self.performPromptFromImage(
                        prompt: instruction,
                        model: promptModel,
                        apiKey: apiKey,
                        images: [inputImage],
                        route: primaryRoute
                    )
                }

                let normalizedPrompt = generatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedPrompt.isEmpty else {
                    throw AppError.noTextInResponse
                }

                self.prompt = normalizedPrompt
                self.successMessage = self.localized("status.prompt_from_image_done")
            } catch let appError as AppError {
                self.setError(appError)
            } catch {
                self.setError(.network(error.localizedDescription))
            }
        }
    }

    private func isSupportedAttachment(url: URL) -> Bool {
        supportedAttachmentExtensions.contains(url.pathExtension.lowercased())
    }

    private func buildAttachments(from urls: [URL], existingAttachments: [AttachedImage]) -> AttachmentBuildResult {
        var existingPaths = Set(existingAttachments.map { $0.fileURL.standardizedFileURL.path })
        var existingTokens = Set(existingAttachments.map(\.mentionToken))
        var generatedAttachments: [AttachedImage] = []
        var errors: [AppError] = []

        for sourceURL in urls {
            let candidateURL = sourceURL.standardizedFileURL

            if existingPaths.contains(candidateURL.path) {
                continue
            }

            guard isSupportedAttachment(url: candidateURL) else {
                errors.append(.unsupportedAttachmentFormat(candidateURL.lastPathComponent))
                continue
            }

            guard fileManager.fileExists(atPath: candidateURL.path),
                  fileManager.isReadableFile(atPath: candidateURL.path) else {
                errors.append(.unreadableAttachment(candidateURL.lastPathComponent))
                continue
            }

            guard let thumbnail = NSImage(contentsOf: candidateURL) else {
                errors.append(.unreadableAttachment(candidateURL.lastPathComponent))
                continue
            }

            let mentionToken = mentionService.makeMentionToken(fileURL: candidateURL, existingTokens: existingTokens)
            existingTokens.insert(mentionToken)
            existingPaths.insert(candidateURL.path)
            generatedAttachments.append(
                AttachedImage(
                    fileURL: candidateURL,
                    displayName: candidateURL.lastPathComponent,
                    mentionToken: mentionToken,
                    thumbnail: thumbnail
                )
            )
        }

        return AttachmentBuildResult(attachments: generatedAttachments, errors: errors)
    }

    private func firstValidPromptFromImageInput(from droppedURLs: [URL]) -> GenerationInputImage? {
        for sourceURL in droppedURLs {
            let candidateURL = sourceURL.standardizedFileURL
            guard isSupportedAttachment(url: candidateURL) else {
                continue
            }

            guard fileManager.fileExists(atPath: candidateURL.path),
                  fileManager.isReadableFile(atPath: candidateURL.path) else {
                continue
            }

            do {
                let imageData = try Data(contentsOf: candidateURL)
                return GenerationInputImage(
                    fileURL: candidateURL,
                    filename: candidateURL.lastPathComponent,
                    mimeType: mimeType(for: candidateURL),
                    data: imageData
                )
            } catch {
                continue
            }
        }

        return nil
    }

    private func promptEnhancementInput(for trimmedPrompt: String) -> String {
        let instruction = config.promptEnhancementInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = instruction.isEmpty ? AppConfig.defaultPromptEnhancementInstruction : instruction
        return "\(prefix)\n\n\(trimmedPrompt)"
    }

    private func loadInputImages(from attachments: [AttachedImage]) throws -> [GenerationInputImage] {
        try attachments.map { attachment in
            do {
                return GenerationInputImage(
                    fileURL: attachment.fileURL,
                    filename: attachment.displayName,
                    mimeType: mimeType(for: attachment.fileURL),
                    data: try Data(contentsOf: attachment.fileURL)
                )
            } catch {
                throw AppError.unreadableAttachment(attachment.displayName)
            }
        }
    }

    private func resolvePrimaryRoute() throws -> NetworkRoute {
        if config.proxyEnabled {
            let validation = proxyValidationResult
            if let error = validation.error {
                throw error
            }
            return .proxy
        }
        return .directFallback
    }

    private func performGeneration(request: GenerationRequest, route: NetworkRoute) async throws -> GenerationResult {
        let session = try networkClientProvider.makeSession(config: config, route: route)
        if request.imageCount <= 1 {
            return try await apiClient.generateImage(
                request: request,
                timeoutSec: config.requestTimeoutSec,
                session: session,
                route: route
            )
        }

        return try await apiClient.generateImagesBatch(
            request: request,
            timeoutSec: config.requestTimeoutSec,
            session: session,
            route: route
        )
    }

    private func performPromptEnhancement(
        prompt: String,
        model: String,
        apiKey: String,
        route: NetworkRoute
    ) async throws -> String {
        let session = try networkClientProvider.makeSession(config: config, route: route)
        return try await apiClient.generateText(
            prompt: prompt,
            model: model,
            apiKey: apiKey,
            timeoutSec: config.requestTimeoutSec,
            session: session,
            route: route
        )
    }

    private func performPromptFromImage(
        prompt: String,
        model: String,
        apiKey: String,
        images: [GenerationInputImage],
        route: NetworkRoute
    ) async throws -> String {
        let session = try networkClientProvider.makeSession(config: config, route: route)
        return try await apiClient.generateTextFromImages(
            prompt: prompt,
            model: model,
            apiKey: apiKey,
            images: images,
            timeoutSec: config.requestTimeoutSec,
            session: session,
            route: route
        )
    }

    private func refreshAvailableModelsAsync(trigger: ModelRefreshTrigger) async {
        let trimmedAPIKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            modelCatalogErrorMessage = trigger == .manual ? localized(AppError.missingAPIKey.localizationKey) : nil
            availableImageModels = []
            availableTextModels = []
            return
        }

        if isLoadingModels {
            return
        }

        if trigger != .manual, let cached = modelCatalogCache[trimmedAPIKey] {
            applyModelCatalogs(from: cached)
            return
        }

        isLoadingModels = true
        modelCatalogErrorMessage = nil
        defer { isLoadingModels = false }

        do {
            let primaryRoute = try resolvePrimaryRoute()

            let models: [ModelCatalogItem]
            if primaryRoute == .proxy {
                do {
                    models = try await fetchModelCatalog(apiKey: trimmedAPIKey, route: .proxy)
                } catch let proxyError as AppError where proxyError.isRecoverableProxyFailure {
                    guard config.allowDirectFallback else {
                        throw AppError.directFallbackDisabled(proxyError.debugDetails)
                    }

                    models = try await fetchModelCatalog(apiKey: trimmedAPIKey, route: .directFallback)
                }
            } else {
                models = try await fetchModelCatalog(apiKey: trimmedAPIKey, route: primaryRoute)
            }

            modelCatalogCache[trimmedAPIKey] = models
            applyModelCatalogs(from: models)
        } catch let appError as AppError {
            applyModelCatalog([])
            applyTextModelCatalog([])
            modelCatalogErrorMessage = userMessage(for: appError)
        } catch {
            applyModelCatalog([])
            applyTextModelCatalog([])
            modelCatalogErrorMessage = userMessage(for: .modelCatalogUnavailable(error.localizedDescription))
        }
    }

    private func checkAPIAvailabilityAsync() async {
        let trimmedAPIKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            apiAvailabilityMessage = localized(AppError.missingAPIKey.localizationKey)
            apiAvailabilityMessageIsError = true
            return
        }

        if config.proxyEnabled {
            let validation = proxyValidationResult
            if let error = validation.error {
                apiAvailabilityMessage = displayMessage(for: error)
                apiAvailabilityMessageIsError = true
                return
            }
        }

        guard !isCheckingAPIAvailability else {
            return
        }

        isCheckingAPIAvailability = true
        apiAvailabilityMessage = nil
        apiAvailabilityMessageIsError = false
        defer { isCheckingAPIAvailability = false }

        do {
            let primaryRoute = try resolvePrimaryRoute()

            let models: [ModelCatalogItem]
            let usedFallback: Bool
            if primaryRoute == .proxy {
                do {
                    models = try await fetchModelCatalog(apiKey: trimmedAPIKey, route: .proxy)
                    usedFallback = false
                } catch let proxyError as AppError where proxyError.isRecoverableProxyFailure {
                    guard config.allowDirectFallback else {
                        throw AppError.directFallbackDisabled(proxyError.debugDetails)
                    }

                    models = try await fetchModelCatalog(apiKey: trimmedAPIKey, route: .directFallback)
                    usedFallback = true
                }
            } else {
                models = try await fetchModelCatalog(apiKey: trimmedAPIKey, route: primaryRoute)
                usedFallback = false
            }

            modelCatalogCache[trimmedAPIKey] = models
            applyModelCatalogs(from: models)

            let imageReadyCount = GeminiModelCatalogClient.filterImageReadyModels(from: models).count
            let textReadyCount = GeminiModelCatalogClient.filterTextReadyModels(from: models).count

            if usedFallback {
                apiAvailabilityMessage = localized(
                    "settings.api_check_success_fallback",
                    imageReadyCount,
                    textReadyCount
                )
            } else {
                apiAvailabilityMessage = localized(
                    "settings.api_check_success",
                    imageReadyCount,
                    textReadyCount
                )
            }
            apiAvailabilityMessageIsError = false
        } catch let appError as AppError {
            apiAvailabilityMessage = displayMessage(for: appError)
            apiAvailabilityMessageIsError = true
        } catch {
            apiAvailabilityMessage = userMessage(for: .network(error.localizedDescription))
            apiAvailabilityMessageIsError = true
        }
    }

    private func fetchModelCatalog(apiKey: String, route: NetworkRoute) async throws -> [ModelCatalogItem] {
        let session = try networkClientProvider.makeSession(config: config, route: route)
        return try await modelCatalogClient.fetchModels(
            apiKey: apiKey,
            timeoutSec: config.requestTimeoutSec,
            session: session,
            route: route
        )
    }

    private func appendHistory(_ record: HistoryRecord) {
        do {
            try historyStore?.append(record)
            history = historyStore?.load() ?? history
        } catch {
            print("[NanoBananaDesktop] Failed to persist history: \(error.localizedDescription)")
            history.insert(record, at: 0)
            history = Array(history.prefix(20))
        }
    }

    private func setError(_ error: AppError) {
        self.errorMessage = displayMessage(for: error)
    }

    private func displayMessage(for error: AppError) -> String {
        let message = userMessage(for: error)
        guard !error.debugDetails.isEmpty else {
            return message
        }
        return "\(message) (\(error.debugDetails))"
    }

    private func userMessage(for error: AppError) -> String {
        switch error {
        case .serverError(let code):
            return localized("error.server_with_code", code)
        case .invalidConfiguration(let details):
            let base = localized("error.invalid_configuration")
            if details.isEmpty {
                return base
            }
            return "\(base): \(details)"
        case .modelCatalogUnavailable(let details):
            let base = localized("error.model_catalog_unavailable")
            if details.isEmpty {
                return base
            }
            return "\(base): \(details)"
        case .proxyInvalidSettings(let details):
            let base = localized("error.proxy_invalid_settings")
            if details.isEmpty {
                return base
            }
            return "\(base): \(details)"
        case .network(let details):
            let base = localized("error.network")
            if details.isEmpty {
                return base
            }
            return "\(base): \(details)"
        case .ioError(let details):
            let base = localized("error.io")
            if details.isEmpty {
                return base
            }
            return "\(base): \(details)"
        case .unsupportedAttachmentFormat(let filename):
            return localized("error.unsupported_attachment_format", filename)
        case .unreadableAttachment(let filename):
            return localized("error.unreadable_attachment", filename)
        case .promptFromImageModelNotSupported:
            return localized("error.prompt_from_image_model_not_supported")
        default:
            return localized(error.localizationKey)
        }
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        default:
            return "image/png"
        }
    }

    private func detectSourceAspectRatio(from attachments: [AttachedImage]) -> ImageAspectRatio? {
        guard let firstURL = attachments.first?.fileURL else {
            return nil
        }
        return detectAspectRatio(for: firstURL)
    }

    private func detectAspectRatio(for imageURL: URL) -> ImageAspectRatio? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }

        let width = widthNumber.doubleValue
        let height = heightNumber.doubleValue
        guard width > 0, height > 0 else {
            return nil
        }

        return ImageAspectRatio.closest(forWidth: width, height: height)
    }

    private func applyModelCatalogs(from models: [ModelCatalogItem]) {
        let imageModels = GeminiModelCatalogClient.filterImageReadyModels(from: models)
        let textModels = GeminiModelCatalogClient.filterTextReadyModels(from: models)

        applyModelCatalog(imageModels)
        applyTextModelCatalog(textModels)

        if imageModels.isEmpty {
            modelCatalogErrorMessage = userMessage(for: .noImageReadyModels)
        } else if textModels.isEmpty {
            modelCatalogErrorMessage = userMessage(for: .noTextReadyModels)
        } else {
            modelCatalogErrorMessage = nil
        }
    }

    private func sortedModelCatalog(_ models: [ModelCatalogItem], selectedModel: String) -> [ModelCatalogItem] {
        let selected = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)

        return models.sorted { lhs, rhs in
            let lhsIsSelected = !selected.isEmpty && lhs.name == selected
            let rhsIsSelected = !selected.isEmpty && rhs.name == selected
            if lhsIsSelected != rhsIsSelected {
                return lhsIsSelected
            }

            let lhsDisplay = lhs.displayName.isEmpty ? lhs.name : lhs.displayName
            let rhsDisplay = rhs.displayName.isEmpty ? rhs.name : rhs.displayName
            let displayCompare = lhsDisplay.localizedCaseInsensitiveCompare(rhsDisplay)
            if displayCompare != .orderedSame {
                return displayCompare == .orderedAscending
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func mergedModelCatalog(models: [ModelCatalogItem], with selectedModel: String) -> [ModelCatalogItem] {
        let trimmedSelectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelectedModel.isEmpty else {
            return models
        }

        if let selectedIndex = models.firstIndex(where: { $0.name == trimmedSelectedModel }) {
            if selectedIndex == 0 {
                return models
            }

            var reordered = models
            let selectedItem = reordered.remove(at: selectedIndex)
            reordered.insert(selectedItem, at: 0)
            return reordered
        }

        var merged = models
        merged.insert(.custom(trimmedSelectedModel), at: 0)
        return merged
    }

    private func localizedStatic(_ key: String, language: AppLanguage, _ args: CVarArg...) -> String {
        Localizer.string(key, language: language, args)
    }
}

private struct AttachmentBuildResult {
    let attachments: [AttachedImage]
    let errors: [AppError]
}
