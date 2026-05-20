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
    private struct CompletedGeneratedAsset: Sendable {
        let image: GeneratedImageResult
    }

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
    @Published var lastActualGenerationCost: GenerationCostEstimate?
    @Published var kieBalanceCredits: Double?
    @Published var isLoadingKieBalance: Bool = false
    @Published var kieBalanceError: String?
    @Published var availableImageModels: [ModelCatalogItem] = []
    @Published var availableTextModels: [ModelCatalogItem] = []
    @Published var isLoadingModels: Bool = false
    @Published var modelCatalogErrorMessage: String?
    @Published var isCheckingAPIAvailability: Bool = false
    @Published var apiAvailabilityMessage: String?
    @Published var apiAvailabilityMessageIsError: Bool = false
    @Published var isEnhancingPrompt: Bool = false
    @Published var isGeneratingPromptFromImage: Bool = false
    @Published var isPresetNameSheetPresented: Bool = false
    @Published var presetNameDraft: String = ""
    @Published var isPresetOverwriteAlertPresented: Bool = false
    @Published var pendingPresetOverwriteName: String?
    @Published var selectedPromptPresetID: UUID?

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
    private let openAIImageAPIClient: OpenAIImageAPIClient
    private let openAITextAPIClient: OpenAITextAPIClient
    private let kieImageAPIClient: KieAIImageAPIClient
    private let kieTextAPIClient: KieAITextAPIClient
    private let kieAccountAPIClient: KieAccountAPIClient
    private let modelCatalogClient: GeminiModelCatalogClient
    private let openAIModelCatalogClient: OpenAIModelCatalogClient
    private let networkClientProvider: NetworkClientProvider
    private let mentionService: AttachmentMentionService
    private let generationNotificationService: any GenerationNotificationServiceProtocol

    private let supportedAttachmentExtensions = Set(["png", "jpg", "jpeg", "webp"])
    private var geminiModelCatalogCache: [String: [ModelCatalogItem]] = [:]
    private var openAIModelCatalogCache: [String: [ModelCatalogItem]] = [:]
    private var openAICompatibleModelCatalogCache: [String: [ModelCatalogItem]] = [:]
    private var lastSavedAPIKey: String = ""
    private var lastSavedOpenAIAPIKey: String = ""
    private var lastSavedOpenAICompatibleAPIKey: String = ""
    private var lastSavedOpenAICompatibleBaseURL: String = ""
    private var lastSavedKieAPIKey: String = ""
    private var lastSavedGeminiEnabled: Bool = true
    private var lastSavedOpenAIEnabled: Bool = true
    private var lastSavedOpenAICompatibleEnabled: Bool = true
    private var lastSavedKieEnabled: Bool = true

    init(
        fileManager: FileManager = .default,
        configStore: AppConfigStore? = nil,
        historyStore: HistoryStore? = nil,
        resolutionMapper: PromptResolutionMapper = PromptResolutionMapper(),
        filenameGenerator: FilenameGenerator = FilenameGenerator(),
        imagePersistenceService: ImagePersistenceService = ImagePersistenceService(),
        apiClient: GeminiAPIClient = GeminiAPIClient(),
        openAIImageAPIClient: OpenAIImageAPIClient = OpenAIImageAPIClient(),
        openAITextAPIClient: OpenAITextAPIClient = OpenAITextAPIClient(),
        kieImageAPIClient: KieAIImageAPIClient = KieAIImageAPIClient(),
        kieTextAPIClient: KieAITextAPIClient = KieAITextAPIClient(),
        kieAccountAPIClient: KieAccountAPIClient = KieAccountAPIClient(),
        modelCatalogClient: GeminiModelCatalogClient = GeminiModelCatalogClient(),
        openAIModelCatalogClient: OpenAIModelCatalogClient = OpenAIModelCatalogClient(),
        networkClientProvider: NetworkClientProvider = ProxySessionFactory(),
        mentionService: AttachmentMentionService = AttachmentMentionService(),
        generationNotificationService: any GenerationNotificationServiceProtocol = NoopGenerationNotificationService()
    ) {
        self.fileManager = fileManager
        self.resolutionMapper = resolutionMapper
        self.filenameGenerator = filenameGenerator
        self.imagePersistenceService = imagePersistenceService
        self.apiClient = apiClient
        self.openAIImageAPIClient = openAIImageAPIClient
        self.openAITextAPIClient = openAITextAPIClient
        self.kieImageAPIClient = kieImageAPIClient
        self.kieTextAPIClient = kieTextAPIClient
        self.kieAccountAPIClient = kieAccountAPIClient
        self.modelCatalogClient = modelCatalogClient
        self.openAIModelCatalogClient = openAIModelCatalogClient
        self.networkClientProvider = networkClientProvider
        self.mentionService = mentionService
        self.generationNotificationService = generationNotificationService

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
        self.lastSavedOpenAIAPIKey = self.config.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastSavedOpenAICompatibleAPIKey = self.config.openAICompatibleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastSavedOpenAICompatibleBaseURL = self.config.openAICompatibleBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastSavedKieAPIKey = self.config.kieAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastSavedGeminiEnabled = self.config.geminiEnabled
        self.lastSavedOpenAIEnabled = self.config.openAIEnabled
        self.lastSavedOpenAICompatibleEnabled = self.config.openAICompatibleEnabled
        self.lastSavedKieEnabled = self.config.kieEnabled
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
        let promptReady = currentImageModelRequiresPrompt
            ? !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : true
        let inputReady = currentImageModelRequiresInputImage ? !attachedImages.isEmpty : true
        return !isGenerating && !isGeneratingPromptFromImage && promptReady && inputReady
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

    var generationCostDisplayText: String {
        GenerationCostRegistry.displayText(for: generationCostEstimate, language: config.language)
    }

    var shouldShowKieBalance: Bool {
        config.kieEnabled && !config.kieAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var kieBalanceDisplayText: String {
        if isLoadingKieBalance {
            return localized("sidebar.kie_balance_loading")
        }

        if let kieBalanceCredits {
            let value: String
            if kieBalanceCredits.rounded() == kieBalanceCredits {
                value = String(format: "%.0f", kieBalanceCredits)
            } else {
                value = String(format: "%.2f", kieBalanceCredits)
            }
            return localized("sidebar.kie_balance", value)
        }

        if let kieBalanceError, !kieBalanceError.isEmpty {
            return localized("sidebar.kie_balance_error")
        }

        return localized("sidebar.kie_balance_unknown")
    }

    private var generationCostEstimate: GenerationCostEstimate {
        let provider = imageModelProvider(for: config.model)
        let apiModel = apiModelName(for: config.model)
        let resolvedResolution = resolutionMapper.resolve(
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            selection: resolutionSelection
        )

        if let actual = lastActualGenerationCost,
           actual.matches(
            provider: provider,
            model: apiModel,
            resolution: resolvedResolution,
            imageCount: imageCountSelection
           ) {
            return actual
        }

        return GenerationCostRegistry.estimate(
            provider: provider,
            model: apiModel,
            resolution: resolvedResolution,
            imageCount: imageCountSelection
        )
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
        mergedImageModelCatalog(models: availableImageModels, with: config.model)
    }

    var selectableTextModels: [ModelCatalogItem] {
        mergedTextModelCatalog(models: availableTextModels, with: config.promptEnhancementModel)
    }

    private var currentImageModelRequiresPrompt: Bool {
        guard imageModelProvider(for: config.model) == .kie,
              let spec = KieModelRegistry.spec(for: config.model) else {
            return true
        }
        return spec.kind.requiresPrompt
    }

    private var currentImageModelRequiresInputImage: Bool {
        guard imageModelProvider(for: config.model) == .kie,
              let spec = KieModelRegistry.spec(for: config.model) else {
            return false
        }
        return spec.requiresInputImage
    }

    var hasOutputToReveal: Bool {
        !lastOutputPaths.isEmpty
    }

    var sortedPromptPresets: [PromptPreset] {
        config.promptPresets.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var canSavePromptPreset: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var presetsMenuTitle: String {
        guard let selectedPromptPresetID,
              let preset = sortedPromptPresets.first(where: { $0.id == selectedPromptPresetID }) else {
            return localized("main.presets")
        }
        return preset.name
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
        refreshKieBalance()
    }

    func modelTitle(for item: ModelCatalogItem) -> String {
        let apiModelName = ModelProvider.apiModelName(from: item.name)
        let providerSuffix = item.provider == .openAICompatible || item.provider == .kie
            ? " • \(item.provider.displayName)"
            : ""

        if item.isCustomFallback {
            return localized("main.model_custom", apiModelName) + providerSuffix
        }

        if item.displayName.isEmpty {
            return apiModelName + providerSuffix
        }

        if item.displayName.caseInsensitiveCompare(apiModelName) == .orderedSame {
            return item.displayName + providerSuffix
        }

        return "\(item.displayName) (\(apiModelName))\(providerSuffix)"
    }

    func imageModelProvider(for modelName: String) -> ModelProvider {
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let knownModel = availableImageModels.first(where: { $0.name == trimmedModel }) {
            return knownModel.provider
        }
        return ModelProvider.inferImageProvider(from: trimmedModel)
    }

    func promptModelProvider(for modelName: String) -> ModelProvider {
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let knownModel = availableTextModels.first(where: { $0.name == trimmedModel }) {
            return knownModel.provider
        }
        return ModelProvider.inferTextProvider(from: trimmedModel)
    }

    func apiKey(for provider: ModelProvider) -> String {
        switch provider {
        case .gemini:
            return config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openAI:
            return config.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openAICompatible:
            return config.openAICompatibleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .kie:
            return config.kieAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func isProviderEnabled(_ provider: ModelProvider) -> Bool {
        switch provider {
        case .gemini:
            return config.geminiEnabled
        case .openAI:
            return config.openAIEnabled
        case .openAICompatible:
            return config.openAICompatibleEnabled
        case .kie:
            return config.kieEnabled
        }
    }

    func apiModelName(for selectedModelName: String) -> String {
        ModelProvider.apiModelName(from: selectedModelName)
    }

    func missingAPIKeyError(for provider: ModelProvider) -> AppError {
        switch provider {
        case .gemini:
            return .missingAPIKey
        case .openAI:
            return .missingOpenAIAPIKey
        case .openAICompatible:
            return .missingOpenAICompatibleAPIKey
        case .kie:
            return .missingKieAPIKey
        }
    }

    func providerDisabledError(for provider: ModelProvider) -> AppError {
        .providerDisabled(provider.displayName)
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
        config.openAIAPIKey = config.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedOpenAIAPIKey = config.openAIAPIKey
        config.openAICompatibleAPIKey = config.openAICompatibleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        config.openAICompatibleBaseURL = normalizedOpenAICompatibleBaseURLString(config.openAICompatibleBaseURL)
        config.kieAPIKey = config.kieAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedOpenAICompatibleAPIKey = config.openAICompatibleAPIKey
        let updatedOpenAICompatibleBaseURL = config.openAICompatibleBaseURL
        let updatedKieAPIKey = config.kieAPIKey
        let didAPIKeyChange = updatedAPIKey != lastSavedAPIKey
        let didOpenAIAPIKeyChange = updatedOpenAIAPIKey != lastSavedOpenAIAPIKey
        let didOpenAICompatibleAPIKeyChange = updatedOpenAICompatibleAPIKey != lastSavedOpenAICompatibleAPIKey
        let didOpenAICompatibleBaseURLChange = updatedOpenAICompatibleBaseURL != lastSavedOpenAICompatibleBaseURL
        let didKieAPIKeyChange = updatedKieAPIKey != lastSavedKieAPIKey
        let didProviderEnablementChange = config.geminiEnabled != lastSavedGeminiEnabled ||
            config.openAIEnabled != lastSavedOpenAIEnabled ||
            config.openAICompatibleEnabled != lastSavedOpenAICompatibleEnabled ||
            config.kieEnabled != lastSavedKieEnabled

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
            lastSavedOpenAIAPIKey = updatedOpenAIAPIKey
            lastSavedOpenAICompatibleAPIKey = updatedOpenAICompatibleAPIKey
            lastSavedOpenAICompatibleBaseURL = updatedOpenAICompatibleBaseURL
            lastSavedKieAPIKey = updatedKieAPIKey
            lastSavedGeminiEnabled = config.geminiEnabled
            lastSavedOpenAIEnabled = config.openAIEnabled
            lastSavedOpenAICompatibleEnabled = config.openAICompatibleEnabled
            lastSavedKieEnabled = config.kieEnabled
            if didAPIKeyChange ||
                didOpenAIAPIKeyChange ||
                didOpenAICompatibleAPIKeyChange ||
                didOpenAICompatibleBaseURLChange ||
                didKieAPIKeyChange ||
                didProviderEnablementChange {
                refreshAvailableModels(trigger: .keyChanged)
            }
            if didKieAPIKeyChange || didProviderEnablementChange {
                refreshKieBalance()
            }
        } catch let appError as AppError {
            setError(appError)
        } catch {
            setError(.ioError(error.localizedDescription))
        }
    }

    func refreshKieBalance() {
        Task { [weak self] in
            guard let self else {
                return
            }
            await self.refreshKieBalanceAsync()
        }
    }

    private func normalizedOpenAICompatibleBaseURLString(_ candidate: String) -> String {
        var trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = AppConfig.defaultOpenAICompatibleBaseURL
        }

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        return trimmed.isEmpty ? AppConfig.defaultOpenAICompatibleBaseURL : trimmed
    }

    func openAICompatibleBaseURL() throws -> URL {
        let normalized = normalizedOpenAICompatibleBaseURLString(config.openAICompatibleBaseURL)
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else {
            throw AppError.invalidOpenAICompatibleBaseURL(normalized)
        }
        return url
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

    func postGenerationCompletionNotificationIfEnabled(imageCount: Int) {
        guard config.generationCompletionNotificationsEnabled else {
            return
        }

        let language = config.language
        let normalizedImageCount = max(1, imageCount)
        Task {
            await generationNotificationService.notifyGenerationCompleted(
                language: language,
                imageCount: normalizedImageCount
            )
        }
    }

    func presentSavePresetSheet() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            setError(.emptyPrompt)
            return
        }

        clearTransientMessages()
        presetNameDraft = suggestedPresetName(from: trimmedPrompt)
        isPresetNameSheetPresented = true
    }

    func cancelPresetSaveFlow() {
        isPresetNameSheetPresented = false
        presetNameDraft = ""
    }

    func commitPresetFromDraft() {
        let trimmedName = presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = localized("error.preset_name_empty")
            return
        }

        if let existingPreset = existingPreset(named: trimmedName) {
            pendingPresetOverwriteName = existingPreset.name
            isPresetOverwriteAlertPresented = true
            isPresetNameSheetPresented = false
            return
        }

        guard saveCurrentPromptAsPreset(name: trimmedName, overwriteIfExists: false) else {
            return
        }

        isPresetNameSheetPresented = false
        presetNameDraft = ""
    }

    func confirmPresetOverwrite() {
        guard let pendingPresetOverwriteName else {
            isPresetOverwriteAlertPresented = false
            return
        }

        guard saveCurrentPromptAsPreset(name: pendingPresetOverwriteName, overwriteIfExists: true) else {
            return
        }

        isPresetOverwriteAlertPresented = false
        self.pendingPresetOverwriteName = nil
        presetNameDraft = ""
    }

    func cancelPresetOverwrite() {
        isPresetOverwriteAlertPresented = false
        pendingPresetOverwriteName = nil
    }

    func applyPreset(id: UUID) {
        guard let index = config.promptPresets.firstIndex(where: { $0.id == id }) else {
            return
        }

        clearTransientMessages()

        let preset = config.promptPresets[index]
        prompt = preset.prompt
        config.model = preset.imageModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppConfig.defaultModel
            : preset.imageModel
        resolutionSelection = preset.resolutionSelection
        aspectRatioSelection = preset.aspectRatioSelection
        imageCountSelection = min(max(preset.imageCount, 1), 4)
        selectedPromptPresetID = preset.id

        config.promptPresets[index].updatedAt = Date()
        normalizePresetOrdering()
        if persistConfigChanges() {
            successMessage = localized("status.preset_applied", preset.name)
        }
    }

    func updatePreset(id: UUID, newName: String, newPrompt: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = localized("error.preset_name_empty")
            return
        }
        guard !trimmedPrompt.isEmpty else {
            setError(.emptyPrompt)
            return
        }

        guard let index = config.promptPresets.firstIndex(where: { $0.id == id }) else {
            return
        }

        if let duplicate = existingPreset(named: trimmedName, excluding: id) {
            errorMessage = localized("error.preset_name_exists", duplicate.name)
            return
        }

        config.promptPresets[index].name = trimmedName
        config.promptPresets[index].prompt = trimmedPrompt
        config.promptPresets[index].updatedAt = Date()
        normalizePresetOrdering()

        if persistConfigChanges() {
            successMessage = localized("status.preset_updated", trimmedName)
        }
    }

    func renamePreset(id: UUID, newName: String) {
        guard let preset = config.promptPresets.first(where: { $0.id == id }) else {
            return
        }
        updatePreset(id: id, newName: newName, newPrompt: preset.prompt)
    }

    func deletePreset(id: UUID) {
        guard let index = config.promptPresets.firstIndex(where: { $0.id == id }) else {
            return
        }

        let deletedName = config.promptPresets[index].name
        config.promptPresets.remove(at: index)
        if selectedPromptPresetID == id {
            selectedPromptPresetID = nil
        }

        if persistConfigChanges() {
            successMessage = localized("status.preset_deleted", deletedName)
        }
    }

    func presetMetadataText(for preset: PromptPreset) -> String {
        let resolutionText: String
        switch preset.resolutionSelection {
        case .k2:
            resolutionText = ImageResolution.k2.rawValue
        case .k4:
            resolutionText = ImageResolution.k4.rawValue
        case .auto, .k1:
            resolutionText = ImageResolution.k1.rawValue
        }

        let aspectText: String
        if preset.aspectRatioSelection == .auto {
            aspectText = localized("main.aspect_ratio_auto_short")
        } else {
            aspectText = preset.aspectRatioSelection.manualAspectRatio?.rawValue ?? ImageAspectRatio.square.rawValue
        }

        return localized(
            "settings.preset_meta_format",
            preset.imageModel,
            resolutionText,
            aspectText,
            preset.imageCount
        )
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

        let selectedProvider = imageModelProvider(for: config.model)
        guard isProviderEnabled(selectedProvider) else {
            setError(providerDisabledError(for: selectedProvider))
            return
        }

        let selectedKieSpec = selectedProvider == .kie ? KieModelRegistry.spec(for: config.model) : nil
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedKieSpec?.kind.requiresPrompt ?? true,
           trimmedPrompt.isEmpty {
            setError(.emptyPrompt)
            return
        }

        let apiKey = self.apiKey(for: selectedProvider)
        guard !apiKey.isEmpty else {
            setError(missingAPIKeyError(for: selectedProvider))
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

        if selectedKieSpec?.requiresInputImage == true,
           inputImages.isEmpty {
            setError(.missingInputImage)
            return
        }

        let modeForHistory: GenerationMode = inputImages.isEmpty ? .generate : .edit
        let inputPaths = inputImages.map(\.fileURL.path)

        let request = GenerationRequest(
            mode: modeForHistory,
            prompt: trimmedPrompt,
            model: apiModelName(for: config.model),
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
        lastActualGenerationCost = nil
        let startedAt = Date()

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let primaryRoute = try self.resolvePrimaryRoute()

                var routeUsed = primaryRoute
                var fallbackUsed = false

                if request.imageCount > 1 &&
                    (primaryRoute != .proxy || !self.config.allowDirectFallback) {
                    try await self.performParallelDirectGenerationIncrementally(
                        request: request,
                        provider: selectedProvider,
                        outputDirectory: outputDirectory,
                        prompt: trimmedPrompt,
                        modeForHistory: modeForHistory,
                        inputPaths: inputPaths,
                        resolvedResolution: resolvedResolution,
                        route: primaryRoute,
                        proxyUsed: primaryRoute == .proxy,
                        fallbackUsed: false,
                        configuredProxySummary: configuredProxySummary,
                        startedAt: startedAt
                    )
                    self.isGenerating = false
                    return
                }

                let result: GenerationResult
                if primaryRoute == .proxy {
                    do {
                        result = try await self.performGeneration(request: request, provider: selectedProvider, route: .proxy)
                    } catch let proxyError as AppError where proxyError.isRecoverableProxyFailure {
                        guard self.config.allowDirectFallback else {
                            throw AppError.directFallbackDisabled(proxyError.debugDetails)
                        }

                        routeUsed = .directFallback
                        fallbackUsed = true
                        result = try await self.performGeneration(request: request, provider: selectedProvider, route: .directFallback)
                    }
                } else {
                    result = try await self.performGeneration(request: request, provider: selectedProvider, route: primaryRoute)
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
                        outputDirectory: outputDirectory,
                        metadata: ImageGenerationMetadata(prompt: trimmedPrompt, model: request.model)
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
                self.postGenerationCompletionNotificationIfEnabled(imageCount: savedURLs.count)
                let estimatedCost = GenerationCostRegistry.estimate(
                    provider: selectedProvider,
                    model: request.model,
                    resolution: resolvedResolution,
                    imageCount: savedURLs.count
                )
                self.lastActualGenerationCost = result.cost
                    ?? GenerationCostRegistry.combinedActualCost(from: result.images, fallback: estimatedCost)
                if selectedProvider == .kie {
                    await self.refreshKieBalanceAsync()
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

        let enhancementModel = config.promptEnhancementModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !enhancementModel.isEmpty else {
            setError(.invalidConfiguration("Prompt enhancement model cannot be empty"))
            return
        }

        let provider = promptModelProvider(for: enhancementModel)
        guard isProviderEnabled(provider) else {
            setError(providerDisabledError(for: provider))
            return
        }
        let apiKey = self.apiKey(for: provider)
        guard !apiKey.isEmpty else {
            setError(missingAPIKeyError(for: provider))
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
                            model: self.apiModelName(for: enhancementModel),
                            apiKey: apiKey,
                            provider: provider,
                            route: .proxy
                        )
                    } catch let proxyError as AppError where proxyError.isRecoverableProxyFailure {
                        guard self.config.allowDirectFallback else {
                            throw AppError.directFallbackDisabled(proxyError.debugDetails)
                        }

                        improvedPrompt = try await self.performPromptEnhancement(
                            prompt: enhancementInput,
                            model: self.apiModelName(for: enhancementModel),
                            apiKey: apiKey,
                            provider: provider,
                            route: .directFallback
                        )
                    }
                } else {
                    improvedPrompt = try await self.performPromptEnhancement(
                        prompt: enhancementInput,
                        model: self.apiModelName(for: enhancementModel),
                        apiKey: apiKey,
                        provider: provider,
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

        let promptModel = config.promptEnhancementModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptModel.isEmpty else {
            setError(.invalidConfiguration("Prompt model cannot be empty"))
            return
        }

        let provider = promptModelProvider(for: promptModel)
        guard isProviderEnabled(provider) else {
            setError(providerDisabledError(for: provider))
            return
        }
        let apiKey = self.apiKey(for: provider)
        guard !apiKey.isEmpty else {
            setError(missingAPIKeyError(for: provider))
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
                            model: self.apiModelName(for: promptModel),
                            apiKey: apiKey,
                            provider: provider,
                            images: [inputImage],
                            route: .proxy
                        )
                    } catch let proxyError as AppError where proxyError.isRecoverableProxyFailure {
                        guard self.config.allowDirectFallback else {
                            throw AppError.directFallbackDisabled(proxyError.debugDetails)
                        }

                        generatedPrompt = try await self.performPromptFromImage(
                            prompt: instruction,
                            model: self.apiModelName(for: promptModel),
                            apiKey: apiKey,
                            provider: provider,
                            images: [inputImage],
                            route: .directFallback
                        )
                    }
                } else {
                    generatedPrompt = try await self.performPromptFromImage(
                        prompt: instruction,
                        model: self.apiModelName(for: promptModel),
                        apiKey: apiKey,
                        provider: provider,
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

    private func executeImageGeneration(
        request: GenerationRequest,
        provider: ModelProvider,
        timeoutSec: Int,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> GenerationResult {
        switch provider {
        case .gemini:
            return try await apiClient.generateImage(
                request: request,
                timeoutSec: timeoutSec,
                session: session,
                route: route
            )
        case .openAI:
            return try await openAIImageAPIClient.generateImage(
                request: request,
                timeoutSec: timeoutSec,
                session: session,
                route: route
            )
        case .openAICompatible:
            return try await OpenAIImageAPIClient(baseURL: try openAICompatibleBaseURL())
                .generateImage(
                    request: request,
                    timeoutSec: timeoutSec,
                    session: session,
                    route: route
                )
        case .kie:
            return try await kieImageAPIClient.generateImage(
                request: request,
                timeoutSec: timeoutSec,
                session: session,
                route: route
            )
        }
    }

    private func performGeneration(request: GenerationRequest, provider: ModelProvider, route: NetworkRoute) async throws -> GenerationResult {
        let session = try networkClientProvider.makeSession(config: config, route: route)
        if request.imageCount <= 1 {
            return try await executeImageGeneration(
                request: request,
                provider: provider,
                timeoutSec: config.requestTimeoutSec,
                session: session,
                route: route
            )
        }

        if provider == .gemini {
            return try await performParallelDirectGeneration(
                request: request,
                provider: provider,
                session: session,
                route: route
            )
        }

        return try await performParallelDirectGeneration(
            request: request,
            provider: provider,
            session: session,
            route: route
        )
    }

    private func performParallelDirectGeneration(
        request: GenerationRequest,
        provider: ModelProvider,
        session: URLSession,
        route: NetworkRoute
    ) async throws -> GenerationResult {
        let targetCount = min(max(request.imageCount, 1), 4)
        var orderedImages = Array<GeneratedImageResult?>(repeating: nil, count: targetCount)
        let timeoutSec = config.requestTimeoutSec

        let requestTemplate: GenerationRequest = {
            var template = request
            template.imageCount = 1
            return template
        }()

        try await withThrowingTaskGroup(of: (Int, GeneratedImageResult).self) { taskGroup in
            for index in 0..<targetCount {
                taskGroup.addTask {
                    let singleResult = try await self.executeImageGeneration(
                        request: requestTemplate,
                        provider: provider,
                        timeoutSec: timeoutSec,
                        session: session,
                        route: route
                    )
                    guard let firstImage = singleResult.images.first else {
                        throw AppError.noImageInResponse
                    }
                    return (index, firstImage)
                }
            }

            for try await (index, image) in taskGroup {
                orderedImages[index] = image
            }
        }

        let images = orderedImages.compactMap { $0 }
        guard images.count == targetCount else {
            throw AppError.noImageInResponse
        }

        let estimatedCost = GenerationCostRegistry.estimate(
            provider: provider,
            model: request.model,
            resolution: request.resolution,
            imageCount: targetCount
        )
        return GenerationResult(
            images: images,
            usedResolution: request.resolution,
            cost: GenerationCostRegistry.combinedActualCost(from: images, fallback: estimatedCost)
        )
    }

    private func performParallelDirectGenerationIncrementally(
        request: GenerationRequest,
        provider: ModelProvider,
        outputDirectory: URL,
        prompt: String,
        modeForHistory: GenerationMode,
        inputPaths: [String],
        resolvedResolution: ImageResolution,
        route: NetworkRoute,
        proxyUsed: Bool,
        fallbackUsed: Bool,
        configuredProxySummary: String?,
        startedAt: Date
    ) async throws {
        let session = try networkClientProvider.makeSession(config: config, route: route)
        let targetCount = min(max(request.imageCount, 1), 4)
        let timeoutSec = config.requestTimeoutSec

        let requestTemplate: GenerationRequest = {
            var template = request
            template.imageCount = 1
            return template
        }()

        var completedAssets: [CompletedGeneratedAsset] = []
        var savedPaths: [String] = []
        var renderedImages: [NSImage] = []

        try await withThrowingTaskGroup(of: CompletedGeneratedAsset.self) { taskGroup in
            for _ in 0..<targetCount {
                taskGroup.addTask {
                    let singleResult = try await self.executeImageGeneration(
                        request: requestTemplate,
                        provider: provider,
                        timeoutSec: timeoutSec,
                        session: session,
                        route: route
                    )
                    guard let firstImage = singleResult.images.first else {
                        throw AppError.noImageInResponse
                    }
                    return CompletedGeneratedAsset(image: firstImage)
                }
            }

            for try await completedAsset in taskGroup {
                completedAssets.append(completedAsset)

                let imageFilename = filenameGenerator.generateFilename(
                    prompt: prompt,
                    outputDirectory: outputDirectory
                )
                let savedURL = try imagePersistenceService.savePNG(
                    imageData: completedAsset.image.imageData,
                    filename: imageFilename,
                    outputDirectory: outputDirectory,
                    metadata: ImageGenerationMetadata(prompt: prompt, model: request.model)
                )

                savedPaths.append(savedURL.path)
                lastOutputPaths = savedPaths
                lastOutputPath = savedPaths.first

                if let renderedImage = NSImage(contentsOf: savedURL) {
                    renderedImages.append(renderedImage)
                    lastGeneratedImages = renderedImages
                    lastGeneratedImage = renderedImages.first
                }

                let mergedModelText = completedAssets
                    .compactMap(\.image.modelText)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n\n")
                modelResponseText = mergedModelText.isEmpty ? nil : mergedModelText

                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                appendHistory(
                    HistoryRecord(
                        mode: modeForHistory,
                        prompt: prompt,
                        resolution: resolvedResolution,
                        inputImagePaths: inputPaths,
                        outputImagePath: savedURL.path,
                        status: .success,
                        errorMessage: nil,
                        durationMs: durationMs,
                        modelResponseText: completedAsset.image.modelText,
                        networkRoute: route,
                        proxyUsed: proxyUsed,
                        fallbackUsed: fallbackUsed,
                        proxySummary: configuredProxySummary
                    )
                )
            }
        }

        guard let firstSavedPath = savedPaths.first else {
            throw AppError.noImageInResponse
        }

        let estimatedCost = GenerationCostRegistry.estimate(
            provider: provider,
            model: request.model,
            resolution: resolvedResolution,
            imageCount: savedPaths.count
        )
        lastActualGenerationCost = GenerationCostRegistry.combinedActualCost(
            from: completedAssets.map(\.image),
            fallback: estimatedCost
        )
        if provider == .kie {
            await refreshKieBalanceAsync()
        }

        if savedPaths.count == 1 {
            successMessage = localized("status.success_saved", firstSavedPath)
        } else {
            successMessage = localized("status.success_saved_multiple", savedPaths.count)
        }
        postGenerationCompletionNotificationIfEnabled(imageCount: savedPaths.count)
    }

    private func performPromptEnhancement(
        prompt: String,
        model: String,
        apiKey: String,
        provider: ModelProvider,
        route: NetworkRoute
    ) async throws -> String {
        let session = try networkClientProvider.makeSession(config: config, route: route)
        switch provider {
        case .gemini:
            return try await apiClient.generateText(
                prompt: prompt,
                model: model,
                apiKey: apiKey,
                timeoutSec: config.requestTimeoutSec,
                session: session,
                route: route
            )
        case .openAI:
            return try await openAITextAPIClient.generateText(
                prompt: prompt,
                model: model,
                apiKey: apiKey,
                timeoutSec: config.requestTimeoutSec,
                session: session,
                route: route
            )
        case .openAICompatible:
            return try await OpenAITextAPIClient(baseURL: try openAICompatibleBaseURL())
                .generateText(
                    prompt: prompt,
                    model: model,
                    apiKey: apiKey,
                    timeoutSec: config.requestTimeoutSec,
                    session: session,
                    route: route
                )
        case .kie:
            return try await kieTextAPIClient.generateText(
                prompt: prompt,
                model: model,
                apiKey: apiKey,
                timeoutSec: config.requestTimeoutSec,
                session: session,
                route: route
            )
        }
    }

    private func performPromptFromImage(
        prompt: String,
        model: String,
        apiKey: String,
        provider: ModelProvider,
        images: [GenerationInputImage],
        route: NetworkRoute
    ) async throws -> String {
        let session = try networkClientProvider.makeSession(config: config, route: route)
        switch provider {
        case .gemini:
            return try await apiClient.generateTextFromImages(
                prompt: prompt,
                model: model,
                apiKey: apiKey,
                images: images,
                timeoutSec: config.requestTimeoutSec,
                session: session,
                route: route
            )
        case .openAI:
            return try await openAITextAPIClient.generateTextFromImages(
                prompt: prompt,
                model: model,
                apiKey: apiKey,
                images: images,
                timeoutSec: config.requestTimeoutSec,
                session: session,
                route: route
            )
        case .openAICompatible:
            return try await OpenAITextAPIClient(baseURL: try openAICompatibleBaseURL())
                .generateTextFromImages(
                    prompt: prompt,
                    model: model,
                    apiKey: apiKey,
                    images: images,
                    timeoutSec: config.requestTimeoutSec,
                    session: session,
                    route: route
                )
        case .kie:
            return try await kieTextAPIClient.generateTextFromImages(
                prompt: prompt,
                model: model,
                apiKey: apiKey,
                images: images,
                timeoutSec: config.requestTimeoutSec,
                session: session,
                route: route
            )
        }
    }

    private func refreshKieBalanceAsync() async {
        let apiKey = config.kieAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.kieEnabled, !apiKey.isEmpty else {
            kieBalanceCredits = nil
            kieBalanceError = nil
            isLoadingKieBalance = false
            return
        }

        guard !isLoadingKieBalance else {
            return
        }

        isLoadingKieBalance = true
        defer { isLoadingKieBalance = false }

        do {
            let primaryRoute = try resolvePrimaryRoute()
            let balance = try await fetchKieBalanceWithFallback(apiKey: apiKey, primaryRoute: primaryRoute)
            kieBalanceCredits = balance
            kieBalanceError = nil
        } catch let appError as AppError {
            kieBalanceError = displayMessage(for: appError)
        } catch {
            kieBalanceError = userMessage(for: .network(error.localizedDescription))
        }
    }

    private func fetchKieBalanceWithFallback(apiKey: String, primaryRoute: NetworkRoute) async throws -> Double {
        if primaryRoute == .proxy {
            do {
                return try await fetchKieBalance(apiKey: apiKey, route: .proxy)
            } catch let proxyError as AppError where proxyError.isRecoverableProxyFailure {
                guard config.allowDirectFallback else {
                    throw AppError.directFallbackDisabled(proxyError.debugDetails)
                }
                return try await fetchKieBalance(apiKey: apiKey, route: .directFallback)
            }
        }

        return try await fetchKieBalance(apiKey: apiKey, route: primaryRoute)
    }

    private func fetchKieBalance(apiKey: String, route: NetworkRoute) async throws -> Double {
        let session = try networkClientProvider.makeSession(config: config, route: route)
        return try await kieAccountAPIClient.fetchCreditBalance(
            apiKey: apiKey,
            timeoutSec: config.requestTimeoutSec,
            session: session,
            route: route
        )
    }

    private func refreshAvailableModelsAsync(trigger: ModelRefreshTrigger) async {
        let trimmedGeminiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIKey = config.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAICompatibleKey = config.openAICompatibleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKieKey = config.kieAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveGeminiKey = config.geminiEnabled ? trimmedGeminiKey : ""
        let effectiveOpenAIKey = config.openAIEnabled ? trimmedOpenAIKey : ""
        let effectiveOpenAICompatibleKey = config.openAICompatibleEnabled ? trimmedOpenAICompatibleKey : ""
        let effectiveKieKey = config.kieEnabled ? trimmedKieKey : ""
        let openAICompatibleCacheKey = openAICompatibleCatalogCacheKey()
        let kieImageModels = effectiveKieKey.isEmpty ? [] : KieModelRegistry.catalogItems
        let kieTextModels = effectiveKieKey.isEmpty ? [] : KieTextModelRegistry.catalogItems

        guard !(effectiveGeminiKey.isEmpty &&
                effectiveOpenAIKey.isEmpty &&
                effectiveOpenAICompatibleKey.isEmpty &&
                effectiveKieKey.isEmpty) else {
            modelCatalogErrorMessage = trigger == .manual ? localized(AppError.missingAPIKey.localizationKey) : nil
            availableImageModels = []
            availableTextModels = []
            return
        }

        if isLoadingModels {
            return
        }

        if trigger != .manual,
           let cachedCatalogs = cachedModelCatalogs(
            geminiKey: effectiveGeminiKey,
            openAIKey: effectiveOpenAIKey,
            openAICompatibleKey: effectiveOpenAICompatibleKey.isEmpty ? "" : openAICompatibleCacheKey
           ) {
            applyModelCatalogs(
                geminiModels: cachedCatalogs.gemini,
                openAIModels: cachedCatalogs.openAI,
                openAICompatibleModels: cachedCatalogs.openAICompatible,
                kieImageModels: kieImageModels,
                kieTextModels: kieTextModels
            )
            return
        }

        isLoadingModels = true
        modelCatalogErrorMessage = nil
        defer { isLoadingModels = false }

        do {
            let primaryRoute = try resolvePrimaryRoute()

            var geminiModels: [ModelCatalogItem] = []
            var openAIModels: [ModelCatalogItem] = []
            var openAICompatibleModels: [ModelCatalogItem] = []
            var providerErrors: [String] = []

            if !effectiveGeminiKey.isEmpty {
                do {
                    geminiModels = try await fetchGeminiModelCatalog(
                        apiKey: effectiveGeminiKey,
                        primaryRoute: primaryRoute
                    )
                    geminiModelCatalogCache[effectiveGeminiKey] = geminiModels
                } catch let appError as AppError {
                    providerErrors.append("Gemini: \(userMessage(for: appError))")
                } catch {
                    providerErrors.append("Gemini: \(userMessage(for: .modelCatalogUnavailable(error.localizedDescription)))")
                }
            }

            if !effectiveOpenAIKey.isEmpty {
                do {
                    openAIModels = try await fetchOpenAIModelCatalog(
                        apiKey: effectiveOpenAIKey,
                        primaryRoute: primaryRoute
                    )
                    openAIModelCatalogCache[effectiveOpenAIKey] = openAIModels
                } catch let appError as AppError {
                    providerErrors.append("OpenAI: \(userMessage(for: appError))")
                } catch {
                    providerErrors.append("OpenAI: \(userMessage(for: .modelCatalogUnavailable(error.localizedDescription)))")
                }
            }

            if !effectiveOpenAICompatibleKey.isEmpty {
                do {
                    openAICompatibleModels = try await fetchOpenAICompatibleModelCatalog(
                        apiKey: effectiveOpenAICompatibleKey,
                        primaryRoute: primaryRoute
                    )
                    openAICompatibleModelCatalogCache[openAICompatibleCacheKey] = openAICompatibleModels
                } catch let appError as AppError {
                    providerErrors.append("OpenAI-compatible: \(userMessage(for: appError))")
                } catch {
                    providerErrors.append("OpenAI-compatible: \(userMessage(for: .modelCatalogUnavailable(error.localizedDescription)))")
                }
            }

            applyModelCatalogs(
                geminiModels: geminiModels,
                openAIModels: openAIModels,
                openAICompatibleModels: openAICompatibleModels,
                kieImageModels: kieImageModels,
                kieTextModels: kieTextModels
            )
            if availableImageModels.isEmpty {
                modelCatalogErrorMessage = providerErrors.isEmpty
                    ? userMessage(for: .noImageReadyModels)
                    : providerErrors.joined(separator: "\n")
            } else {
                modelCatalogErrorMessage = nil
            }
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
        let trimmedGeminiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIKey = config.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAICompatibleKey = config.openAICompatibleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKieKey = config.kieAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveGeminiKey = config.geminiEnabled ? trimmedGeminiKey : ""
        let effectiveOpenAIKey = config.openAIEnabled ? trimmedOpenAIKey : ""
        let effectiveOpenAICompatibleKey = config.openAICompatibleEnabled ? trimmedOpenAICompatibleKey : ""
        let effectiveKieKey = config.kieEnabled ? trimmedKieKey : ""
        let openAICompatibleCacheKey = openAICompatibleCatalogCacheKey()
        let kieImageModels = effectiveKieKey.isEmpty ? [] : KieModelRegistry.catalogItems
        let kieTextModels = effectiveKieKey.isEmpty ? [] : KieTextModelRegistry.catalogItems

        guard !(effectiveGeminiKey.isEmpty &&
                effectiveOpenAIKey.isEmpty &&
                effectiveOpenAICompatibleKey.isEmpty &&
                effectiveKieKey.isEmpty) else {
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

            var geminiModels: [ModelCatalogItem] = []
            var openAIModels: [ModelCatalogItem] = []
            var openAICompatibleModels: [ModelCatalogItem] = []
            var messages: [String] = []
            var hadError = false

            if !effectiveGeminiKey.isEmpty {
                do {
                    geminiModels = try await fetchGeminiModelCatalog(
                        apiKey: effectiveGeminiKey,
                        primaryRoute: primaryRoute
                    )
                    geminiModelCatalogCache[effectiveGeminiKey] = geminiModels
                    messages.append(
                        "Gemini: " + localized(
                            "settings.api_check_success",
                            GeminiModelCatalogClient.filterImageReadyModels(from: geminiModels).count,
                            GeminiModelCatalogClient.filterTextReadyModels(from: geminiModels).count
                        )
                    )
                } catch let appError as AppError {
                    messages.append("Gemini: \(displayMessage(for: appError))")
                    hadError = true
                } catch {
                    messages.append("Gemini: \(userMessage(for: .modelCatalogUnavailable(error.localizedDescription)))")
                    hadError = true
                }
            }

            if !effectiveOpenAIKey.isEmpty {
                do {
                    openAIModels = try await fetchOpenAIModelCatalog(
                        apiKey: effectiveOpenAIKey,
                        primaryRoute: primaryRoute
                    )
                    openAIModelCatalogCache[effectiveOpenAIKey] = openAIModels
                    let openAICount = OpenAIModelCatalogClient.filterImageReadyModels(from: openAIModels).count
                    let openAITextCount = OpenAIModelCatalogClient.filterTextReadyModels(from: openAIModels).count
                    if config.language == .ru {
                        messages.append("OpenAI: моделей для изображений \(openAICount), текстовых \(openAITextCount).")
                    } else {
                        messages.append("OpenAI: image models \(openAICount), text models \(openAITextCount).")
                    }
                } catch let appError as AppError {
                    messages.append("OpenAI: \(displayMessage(for: appError))")
                    hadError = true
                } catch {
                    messages.append("OpenAI: \(userMessage(for: .modelCatalogUnavailable(error.localizedDescription)))")
                    hadError = true
                }
            }

            if !effectiveOpenAICompatibleKey.isEmpty {
                do {
                    openAICompatibleModels = try await fetchOpenAICompatibleModelCatalog(
                        apiKey: effectiveOpenAICompatibleKey,
                        primaryRoute: primaryRoute
                    )
                    openAICompatibleModelCatalogCache[openAICompatibleCacheKey] = openAICompatibleModels
                    let imageCount = OpenAIModelCatalogClient.filterImageReadyModels(from: openAICompatibleModels).count
                    let textCount = OpenAIModelCatalogClient.filterTextReadyModels(from: openAICompatibleModels).count
                    messages.append("OpenAI-compatible: image models \(imageCount), text models \(textCount).")
                } catch let appError as AppError {
                    messages.append("OpenAI-compatible: \(displayMessage(for: appError))")
                    hadError = true
                } catch {
                    messages.append("OpenAI-compatible: \(userMessage(for: .modelCatalogUnavailable(error.localizedDescription)))")
                    hadError = true
                }
            }

            if !effectiveKieKey.isEmpty {
                let generationCount = KieModelRegistry.specs.filter { $0.kind == .textToImage || $0.kind == .imageToImage }.count
                let utilityCount = KieModelRegistry.specs.filter { $0.kind == .upscale || $0.kind == .removeBackground }.count
                let textCount = KieTextModelRegistry.specs.count
                if config.language == .ru {
                    messages.append("Kie.ai: моделей генерации \(generationCount), текстовых \(textCount), утилит \(utilityCount).")
                } else {
                    messages.append("Kie.ai: generation models \(generationCount), text models \(textCount), utility models \(utilityCount).")
                }
            }

            applyModelCatalogs(
                geminiModels: geminiModels,
                openAIModels: openAIModels,
                openAICompatibleModels: openAICompatibleModels,
                kieImageModels: kieImageModels,
                kieTextModels: kieTextModels
            )
            if !effectiveKieKey.isEmpty {
                await refreshKieBalanceAsync()
            }
            apiAvailabilityMessage = messages.joined(separator: " ")
            apiAvailabilityMessageIsError = hadError
        } catch let appError as AppError {
            apiAvailabilityMessage = displayMessage(for: appError)
            apiAvailabilityMessageIsError = true
        } catch {
            apiAvailabilityMessage = userMessage(for: .network(error.localizedDescription))
            apiAvailabilityMessageIsError = true
        }
    }

    private func fetchGeminiModelCatalog(apiKey: String, primaryRoute: NetworkRoute) async throws -> [ModelCatalogItem] {
        try await fetchModelCatalogWithFallback(primaryRoute: primaryRoute) { route in
            let session = try networkClientProvider.makeSession(config: config, route: route)
            return try await modelCatalogClient.fetchModels(
                apiKey: apiKey,
                timeoutSec: config.requestTimeoutSec,
                session: session,
                route: route
            )
        }
    }

    private func fetchOpenAIModelCatalog(apiKey: String, primaryRoute: NetworkRoute) async throws -> [ModelCatalogItem] {
        try await fetchModelCatalogWithFallback(primaryRoute: primaryRoute) { route in
            let session = try networkClientProvider.makeSession(config: config, route: route)
            return try await openAIModelCatalogClient.fetchModels(
                apiKey: apiKey,
                timeoutSec: config.requestTimeoutSec,
                session: session,
                route: route
            )
        }
    }

    private func fetchOpenAICompatibleModelCatalog(apiKey: String, primaryRoute: NetworkRoute) async throws -> [ModelCatalogItem] {
        let baseURL = try openAICompatibleBaseURL()
        return try await fetchModelCatalogWithFallback(primaryRoute: primaryRoute) { route in
            let session = try networkClientProvider.makeSession(config: config, route: route)
            return try await OpenAIModelCatalogClient(baseURL: baseURL, provider: .openAICompatible)
                .fetchModels(
                    apiKey: apiKey,
                    timeoutSec: config.requestTimeoutSec,
                    session: session,
                    route: route
                )
        }
    }

    private func fetchModelCatalogWithFallback(
        primaryRoute: NetworkRoute,
        fetcher: (NetworkRoute) async throws -> [ModelCatalogItem]
    ) async throws -> [ModelCatalogItem] {
        if primaryRoute == .proxy {
            do {
                return try await fetcher(.proxy)
            } catch let proxyError as AppError where proxyError.isRecoverableProxyFailure {
                guard config.allowDirectFallback else {
                    throw AppError.directFallbackDisabled(proxyError.debugDetails)
                }
                return try await fetcher(.directFallback)
            }
        }

        return try await fetcher(primaryRoute)
    }

    private func cachedModelCatalogs(
        geminiKey: String,
        openAIKey: String,
        openAICompatibleKey: String
    ) -> (gemini: [ModelCatalogItem], openAI: [ModelCatalogItem], openAICompatible: [ModelCatalogItem])? {
        let cachedGemini: [ModelCatalogItem]
        if geminiKey.isEmpty {
            cachedGemini = []
        } else if let value = geminiModelCatalogCache[geminiKey] {
            cachedGemini = value
        } else {
            return nil
        }

        let cachedOpenAI: [ModelCatalogItem]
        if openAIKey.isEmpty {
            cachedOpenAI = []
        } else if let value = openAIModelCatalogCache[openAIKey] {
            cachedOpenAI = value
        } else {
            return nil
        }

        let cachedOpenAICompatible: [ModelCatalogItem]
        if openAICompatibleKey.isEmpty {
            cachedOpenAICompatible = []
        } else if let value = openAICompatibleModelCatalogCache[openAICompatibleKey] {
            cachedOpenAICompatible = value
        } else {
            return nil
        }

        return (cachedGemini, cachedOpenAI, cachedOpenAICompatible)
    }

    private func openAICompatibleCatalogCacheKey() -> String {
        let key = config.openAICompatibleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return ""
        }
        let baseURL = normalizedOpenAICompatibleBaseURLString(config.openAICompatibleBaseURL)
        return "\(baseURL)|\(key)"
    }

    private func appendHistory(_ record: HistoryRecord) {
        do {
            try historyStore?.append(record)
            history = historyStore?.load() ?? history
        } catch {
            print("[NanoBananaDesktop] Failed to persist history: \(error.localizedDescription)")
            history.insert(record, at: 0)
            history.sort { $0.timestamp > $1.timestamp }
        }
    }

    func appendExternalHistory(_ record: HistoryRecord) {
        appendHistory(record)
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

    @discardableResult
    private func saveCurrentPromptAsPreset(name: String, overwriteIfExists: Bool) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = localized("error.preset_name_empty")
            return false
        }
        guard !trimmedPrompt.isEmpty else {
            setError(.emptyPrompt)
            return false
        }

        let now = Date()
        if let existingIndex = config.promptPresets.firstIndex(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmedName.lowercased()
        }) {
            guard overwriteIfExists else {
                return false
            }

            let existingPreset = config.promptPresets[existingIndex]
            config.promptPresets[existingIndex] = PromptPreset(
                id: existingPreset.id,
                name: trimmedName,
                prompt: trimmedPrompt,
                imageModel: config.model,
                resolutionSelection: resolutionSelection,
                aspectRatioSelection: aspectRatioSelection,
                imageCount: imageCountSelection,
                updatedAt: now
            )
            selectedPromptPresetID = existingPreset.id
        } else {
            let newPreset = PromptPreset(
                name: trimmedName,
                prompt: trimmedPrompt,
                imageModel: config.model,
                resolutionSelection: resolutionSelection,
                aspectRatioSelection: aspectRatioSelection,
                imageCount: imageCountSelection,
                updatedAt: now
            )
            config.promptPresets.append(newPreset)
            selectedPromptPresetID = newPreset.id
        }

        normalizePresetOrdering()
        guard persistConfigChanges() else {
            return false
        }

        successMessage = localized("status.preset_saved", trimmedName)
        return true
    }

    private func existingPreset(named name: String, excluding id: UUID? = nil) -> PromptPreset? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return config.promptPresets.first { preset in
            if let id, preset.id == id {
                return false
            }
            return preset.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
        }
    }

    private func normalizePresetOrdering() {
        config.promptPresets.sort { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func persistConfigChanges() -> Bool {
        do {
            try configStore?.save(config)
            return true
        } catch let appError as AppError {
            setError(appError)
            return false
        } catch {
            setError(.ioError(error.localizedDescription))
            return false
        }
    }

    private func suggestedPresetName(from prompt: String) -> String {
        let words = prompt
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
            .prefix(4)
        let candidate = words.joined(separator: " ")
        if !candidate.isEmpty {
            return candidate
        }
        return localized("main.preset_default_name", config.promptPresets.count + 1)
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

    private func applyModelCatalogs(
        geminiModels: [ModelCatalogItem],
        openAIModels: [ModelCatalogItem],
        openAICompatibleModels: [ModelCatalogItem],
        kieImageModels: [ModelCatalogItem] = [],
        kieTextModels: [ModelCatalogItem] = []
    ) {
        let imageModels = GeminiModelCatalogClient.filterImageReadyModels(from: geminiModels)
            + OpenAIModelCatalogClient.filterImageReadyModels(from: openAIModels)
            + OpenAIModelCatalogClient.filterImageReadyModels(from: openAICompatibleModels)
            + kieImageModels
        let textModels = GeminiModelCatalogClient.filterTextReadyModels(from: geminiModels)
            + OpenAIModelCatalogClient.filterTextReadyModels(from: openAIModels)
            + OpenAIModelCatalogClient.filterTextReadyModels(from: openAICompatibleModels)
            + kieTextModels

        applyModelCatalog(imageModels)
        applyTextModelCatalog(textModels)
        switchSelectedModelsToAvailableFallbackIfNeeded()

        if imageModels.isEmpty {
            modelCatalogErrorMessage = userMessage(for: .noImageReadyModels)
        } else {
            modelCatalogErrorMessage = nil
        }
    }

    private func switchSelectedModelsToAvailableFallbackIfNeeded() {
        if !availableImageModels.isEmpty,
           !availableImageModels.contains(where: { $0.name == config.model }) {
            config.model = availableImageModels[0].name
        }

        if !availableTextModels.isEmpty,
           !availableTextModels.contains(where: { $0.name == config.promptEnhancementModel }) {
            config.promptEnhancementModel = availableTextModels[0].name
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

            if lhs.provider != rhs.provider {
                return lhs.provider.rawValue < rhs.provider.rawValue
            }

            if lhs.provider == .openAI || lhs.provider == .openAICompatible {
                let lhsPriority = openAIImageSortPriority(for: lhs.name)
                let rhsPriority = openAIImageSortPriority(for: rhs.name)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
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

    private func openAIImageSortPriority(for modelName: String) -> Int {
        let normalized = ModelProvider.apiModelName(from: modelName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "gpt-image-2" {
            return 0
        }
        if normalized.hasPrefix("gpt-image-") {
            return 1
        }
        return 2
    }

    private func mergedImageModelCatalog(models: [ModelCatalogItem], with selectedModel: String) -> [ModelCatalogItem] {
        mergedModelCatalog(
            models: models,
            selectedModel: selectedModel,
            providerResolver: ModelProvider.inferImageProvider(from:)
        )
    }

    private func mergedTextModelCatalog(models: [ModelCatalogItem], with selectedModel: String) -> [ModelCatalogItem] {
        mergedModelCatalog(
            models: models,
            selectedModel: selectedModel,
            providerResolver: ModelProvider.inferTextProvider(from:)
        )
    }

    private func mergedModelCatalog(
        models: [ModelCatalogItem],
        selectedModel: String,
        providerResolver: (String) -> ModelProvider
    ) -> [ModelCatalogItem] {
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

        let selectedProvider = providerResolver(trimmedSelectedModel)
        guard isProviderEnabled(selectedProvider) else {
            return models
        }

        var merged = models
        merged.insert(.custom(trimmedSelectedModel, provider: selectedProvider), at: 0)
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
