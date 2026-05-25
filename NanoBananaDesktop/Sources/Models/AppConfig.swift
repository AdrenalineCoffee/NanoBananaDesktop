import Foundation

struct AppConfig: Codable, Equatable {
    static let legacyDefaultImageModel = "gemini-3-pro-image-preview"
    static let legacyDefaultPromptEnhancementInstruction = "Улучши мой запрос для генерации изображения в Nano Banana Pro и пришли только исключительно улучшенный запрос без дополнительных слов"
    static let legacyDefaultPromptFromImageInstruction = """
Ты — PROMPT EXTRACTOR для генерации изображений (выход будет использоваться в Nano Banana).
Твоя задача: по предоставленному ИЗОБРАЖЕНИЮ(ям) создать максимально точный промпт, который воспроизводит:
1) стиль (материалы, текстуры, зерно/плёнка, цветокор, уровень реализма/иллюстративность),
2) окружение/фон,
3) композицию и кадрирование,
4) свет (тип, направление, мягкость, тени, отражения),
5) параметры камеры (примерно: угол, фокусное/перспектива, глубина резкости),
6) ВСЕ надписи на изображении (точный текст, регистр, пунктуация) + их расположение/размер/стиль.

КРИТИЧЕСКИ ВАЖНО:
- Ничего не “улучшай” художественно и не меняй стиль. Твоя цель — максимально точная реконструкция.
- Не добавляй новых объектов/надписей/логотипов, которых нет на изображении.
- Если что-то невозможно разобрать (текст, мелкая деталь) — напиши UNKNOWN вместо выдумывания.
- Текст на изображении должен быть воспроизведён дословно. Если язык/символы неясны — UNKNOWN.


=== ФОРМАТ ВЫВОДА (строго так, без лишних пояснений) ===
A) NANO BANANA PROMPT (лучше на английском, но допускается русский, кроме текста): один цельный промпт.
B) TEXT LAYOUT (если есть текст):
   - Text_1: "..." | font style | color | effects | position (x%, y%) | size (% of image height) | rotation (deg) | alignment
   - Text_2: ...
   (позиции указывать как проценты: левый верх = 0%,0%; правый низ = 100%,100%)
C) NEGATIVE PROMPT: 12–20 коротких запретов, релевантных стилю (без огромных списков).
D) OPTIONAL SETTINGS: aspect ratio, "studio/film grain", "high detail", "sharp/soft", если уместно.


=== ВХОДНЫЕ ДАННЫЕ ===
REFERENCE_IMAGE: (первое изображение, стиль/сцена/композиция — источник правды)
USER_NOTES: (опционально — что особенно важно сохранить: цвета, бренд, точность текста, формат)
"""
    static let defaultModel = "nano-banana-pro-preview"
    static let defaultPromptEnhancementModel = "gemini-3-flash-preview"
    static let defaultPromptFromImageInstruction = """
Ты — PROMPT EXTRACTOR для генерации изображений (выход будет использоваться в Nano Banana).
Твоя задача: по предоставленному ИЗОБРАЖЕНИЮ(ям) создать максимально точный промпт, который воспроизводит:
1) стиль (материалы, текстуры, зерно/плёнка, цветокор, уровень реализма/иллюстративность),
2) окружение/фон,
3) композицию и кадрирование,
4) свет (тип, направление, мягкость, тени, отражения),
5) параметры камеры (примерно: угол, фокусное/перспектива, глубина резкости),
6) ВСЕ надписи на изображении (точный текст, регистр, пунктуация) + их расположение/размер/стиль.

КРИТИЧЕСКИ ВАЖНО:
- Ничего не “улучшай” художественно и не меняй стиль. Твоя цель — максимально точная реконструкция.
- Не добавляй новых объектов/надписей/логотипов, которых нет на изображении.
- Если что-то невозможно разобрать (текст, мелкая деталь) — напиши UNKNOWN вместо выдумывания.
- Текст на изображении должен быть воспроизведён дословно. Если язык/символы неясны — UNKNOWN.


=== ФОРМАТ ВЫВОДА (строго так, без лишних пояснений) ===
A) NANO BANANA PROMPT (лучше на английском, но допускается русский, кроме текста): один цельный промпт.
B) TEXT LAYOUT (если есть текст):
   - Text_1: "..." | font style | color | effects | position (x%, y%) | size (% of image height) | rotation (deg) | alignment
   - Text_2: ...
   (позиции указывать как проценты: левый верх = 0%,0%; правый низ = 100%,100%)
C) NEGATIVE PROMPT: 12–20 коротких запретов, релевантных стилю (без огромных списков).

=== ВХОДНЫЕ ДАННЫЕ ===
REFERENCE_IMAGE: (первое изображение, стиль/сцена/композиция — источник правды)
USER_NOTES: (опционально — что особенно важно сохранить: цвета, бренд, точность текста, формат)
"""
    static let legacyDefaultConceptPromptAdditions = "all but this object are painted white"
    static let defaultConceptPromptAdditions = ", сделай этот объект на белом фоне без теней, будто он вырезан с фотографии"
    static let defaultGenerationCompletionNotificationsEnabled = true
    static let defaultPromptEnhancementInstruction = """
Ты — Prompt Refiner для Nano Banana Pro. Твоя задача: прочитать мой ОРИГИНАЛЬНЫЙ ПРОМПТ и переписать его так, чтобы итоговое изображение/кадр(ы) получились максимально качественными, но при этом полностью сохранились: замысел, стиль, настроение, сюжет, ключевые объекты, цвета/бренд (если задано), и любые явные ограничения.
ВАЖНО: не “улучшай” стиль от себя и не предлагай другой художественный язык. Не добавляй новых персонажей/объектов, если я их не просил. Не меняй эпоху, этничность, возраст, одежду, сеттинг, IP/фандом, если это не указано. Если в моём промпте стиль задан (аниме/реализм/3D/стопмоушн/комикс/фото и т.д.) — усиливай ТОЛЬКО в рамках этого стиля.

Принципы улучшения (следуй им всегда):
1) Перепиши промпт естественным языком, полными фразами (не “tag-soup”).
2) Обязательно структурируй содержание по блокам: Subject, Composition, Action, Location, Style.
3) Добавь уточнения про камеру/оптику/ракурс, свет, материалы/текстуры, фон, глубину резкости, но только такие, которые НЕ меняют задумку (только повышают качество и контроль).
4) Если есть текст на изображении — вынеси его в кавычки и задай правила: язык, шрифт/стиль, расположение, читабельность.
5) Сгенерируй отдельный Negative Prompt (10–20 коротких точных запретов), адаптированный к моему стилю (например: для фотореализма — убрать “cartoon/illustration”; для аниме — убрать “photoreal/skin pores” и т.п.). Не делай негатив слишком длинным.
6) Если мой запрос про анимацию/серии кадров: сохрани стиль и выдай “Storyboard/Shot list” из 4–8 кадров (кадр → действие → камера/ракурс → свет → ключевые неизменные детали персонажа/окружения). Без лишних сюжетных добавок.
7) Никаких вопросов мне не задавай. Если деталей мало — добавляй “безопасные” дефолтные уточнения (аккуратный свет, чистая композиция, фокус на главном), но не меняй смысл.

Формат ответа (строго так):
IMPROVED PROMPT: (единый улучшенный промпт для генерации), NEGATIVE PROMPT: (10–20 пунктов/слов через запятую)

Присылай в ответ только готовый промпт! Не пиши ничего лишнего!

МОЙ ОРИГИНАЛЬНЫЙ ПРОМПТ:
"""
    static let legacyDefaultRequestTimeoutSec = 120
    static let defaultRequestTimeoutSec = 180
    static let defaultNetworkPolicyVersion = 1
    static let defaultOpenAICompatibleBaseURL = "https://www.packyapi.com/v1"
    static let defaultCreditCostCurrency: CreditCostCurrency = .usd
    static let defaultCreditCostPer100Credits: Double = 1

    var apiKey: String
    var openAIAPIKey: String
    var openAICompatibleAPIKey: String
    var openAICompatibleBaseURL: String
    var kieAPIKey: String
    var geminiEnabled: Bool
    var openAIEnabled: Bool
    var openAICompatibleEnabled: Bool
    var kieEnabled: Bool
    var model: String
    var promptEnhancementModel: String
    var promptFromImageInstruction: String
    var conceptPromptAdditions: String
    var generationCompletionNotificationsEnabled: Bool
    var promptEnhancementInstruction: String
    var promptPresets: [PromptPreset]
    var language: AppLanguage
    var defaultOutputDir: String
    var requestTimeoutSec: Int
    var creditCostCurrency: CreditCostCurrency
    var creditCostPer100Credits: Double

    var proxyType: ProxyType
    var proxyHost: String
    var proxyPort: Int
    var proxyUsername: String
    var proxyPassword: String
    var proxyEnabled: Bool
    var allowDirectFallback: Bool
    var noProxyHosts: [String]
    var networkPolicyVersion: Int

    var proxySettings: ProxySettings {
        ProxySettings(
            type: proxyType,
            host: proxyHost,
            port: proxyPort,
            username: proxyUsername,
            password: proxyPassword,
            enabled: proxyEnabled,
            allowDirectFallback: allowDirectFallback,
            noProxyHosts: noProxyHosts
        )
    }

    static func defaultValue(
        currentWorkingDirectory: URL? = AppConfig.inferWorkingDirectory(),
        fileManager: FileManager = .default
    ) -> AppConfig {
        let outputDirectory = defaultOutputDirectory(currentWorkingDirectory: currentWorkingDirectory, fileManager: fileManager)
        return AppConfig(
            apiKey: "",
            openAIAPIKey: "",
            openAICompatibleAPIKey: "",
            openAICompatibleBaseURL: defaultOpenAICompatibleBaseURL,
            kieAPIKey: "",
            geminiEnabled: true,
            openAIEnabled: true,
            openAICompatibleEnabled: true,
            kieEnabled: true,
            model: defaultModel,
            promptEnhancementModel: defaultPromptEnhancementModel,
            promptFromImageInstruction: defaultPromptFromImageInstruction,
            conceptPromptAdditions: defaultConceptPromptAdditions,
            generationCompletionNotificationsEnabled: defaultGenerationCompletionNotificationsEnabled,
            promptEnhancementInstruction: defaultPromptEnhancementInstruction,
            promptPresets: [],
            language: .systemDefault(),
            defaultOutputDir: outputDirectory.path,
            requestTimeoutSec: defaultRequestTimeoutSec,
            creditCostCurrency: defaultCreditCostCurrency,
            creditCostPer100Credits: defaultCreditCostPer100Credits,
            proxyType: .http,
            proxyHost: "",
            proxyPort: 8080,
            proxyUsername: "",
            proxyPassword: "",
            proxyEnabled: false,
            allowDirectFallback: false,
            noProxyHosts: [],
            networkPolicyVersion: defaultNetworkPolicyVersion
        )
    }

    static func defaultOutputDirectory(currentWorkingDirectory: URL?, fileManager: FileManager) -> URL {
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("NanoBanana_img", isDirectory: true)
    }

    static func inferWorkingDirectory(fileManager: FileManager = .default) -> URL? {
        if let envPWD = ProcessInfo.processInfo.environment["PWD"], !envPWD.isEmpty {
            let url = URL(fileURLWithPath: envPWD, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }

        let current = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        return current.path == "/" ? nil : current
    }

    enum CodingKeys: String, CodingKey {
        case apiKey
        case openAIAPIKey
        case openAICompatibleAPIKey
        case openAICompatibleBaseURL
        case kieAPIKey
        case geminiEnabled
        case openAIEnabled
        case openAICompatibleEnabled
        case kieEnabled
        case model
        case promptEnhancementModel
        case promptFromImageInstruction
        case conceptPromptAdditions
        case generationCompletionNotificationsEnabled
        case promptEnhancementInstruction
        case promptPresets
        case language
        case defaultOutputDir
        case requestTimeoutSec
        case creditCostCurrency
        case creditCostPer100Credits
        case proxyType
        case proxyHost
        case proxyPort
        case proxyUsername
        case proxyPassword
        case proxyEnabled
        case allowDirectFallback
        case noProxyHosts
        case networkPolicyVersion
    }

    init(
        apiKey: String,
        openAIAPIKey: String,
        openAICompatibleAPIKey: String,
        openAICompatibleBaseURL: String,
        kieAPIKey: String,
        geminiEnabled: Bool,
        openAIEnabled: Bool,
        openAICompatibleEnabled: Bool,
        kieEnabled: Bool,
        model: String,
        promptEnhancementModel: String,
        promptFromImageInstruction: String,
        conceptPromptAdditions: String,
        generationCompletionNotificationsEnabled: Bool,
        promptEnhancementInstruction: String,
        promptPresets: [PromptPreset],
        language: AppLanguage,
        defaultOutputDir: String,
        requestTimeoutSec: Int,
        creditCostCurrency: CreditCostCurrency,
        creditCostPer100Credits: Double,
        proxyType: ProxyType,
        proxyHost: String,
        proxyPort: Int,
        proxyUsername: String,
        proxyPassword: String,
        proxyEnabled: Bool,
        allowDirectFallback: Bool,
        noProxyHosts: [String],
        networkPolicyVersion: Int
    ) {
        self.apiKey = apiKey
        self.openAIAPIKey = openAIAPIKey
        self.openAICompatibleAPIKey = openAICompatibleAPIKey
        self.openAICompatibleBaseURL = openAICompatibleBaseURL
        self.kieAPIKey = kieAPIKey
        self.geminiEnabled = geminiEnabled
        self.openAIEnabled = openAIEnabled
        self.openAICompatibleEnabled = openAICompatibleEnabled
        self.kieEnabled = kieEnabled
        self.model = model
        self.promptEnhancementModel = promptEnhancementModel
        self.promptFromImageInstruction = promptFromImageInstruction
        self.conceptPromptAdditions = conceptPromptAdditions
        self.generationCompletionNotificationsEnabled = generationCompletionNotificationsEnabled
        self.promptEnhancementInstruction = promptEnhancementInstruction
        self.promptPresets = promptPresets
        self.language = language
        self.defaultOutputDir = defaultOutputDir
        self.requestTimeoutSec = requestTimeoutSec
        self.creditCostCurrency = creditCostCurrency
        self.creditCostPer100Credits = creditCostPer100Credits
        self.proxyType = proxyType
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.proxyUsername = proxyUsername
        self.proxyPassword = proxyPassword
        self.proxyEnabled = proxyEnabled
        self.allowDirectFallback = allowDirectFallback
        self.noProxyHosts = noProxyHosts
        self.networkPolicyVersion = networkPolicyVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let defaults = AppConfig.defaultValue()

        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? defaults.apiKey
        openAIAPIKey = try container.decodeIfPresent(String.self, forKey: .openAIAPIKey) ?? defaults.openAIAPIKey
        openAICompatibleAPIKey = try container.decodeIfPresent(String.self, forKey: .openAICompatibleAPIKey)
            ?? defaults.openAICompatibleAPIKey
        openAICompatibleBaseURL = try container.decodeIfPresent(String.self, forKey: .openAICompatibleBaseURL)
            ?? defaults.openAICompatibleBaseURL
        kieAPIKey = try container.decodeIfPresent(String.self, forKey: .kieAPIKey) ?? defaults.kieAPIKey
        geminiEnabled = try container.decodeIfPresent(Bool.self, forKey: .geminiEnabled) ?? true
        openAIEnabled = try container.decodeIfPresent(Bool.self, forKey: .openAIEnabled) ?? true
        openAICompatibleEnabled = try container.decodeIfPresent(Bool.self, forKey: .openAICompatibleEnabled) ?? true
        kieEnabled = try container.decodeIfPresent(Bool.self, forKey: .kieEnabled) ?? true
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        promptEnhancementModel = try container.decodeIfPresent(String.self, forKey: .promptEnhancementModel) ?? defaults.promptEnhancementModel
        promptFromImageInstruction = try container.decodeIfPresent(String.self, forKey: .promptFromImageInstruction)
            ?? defaults.promptFromImageInstruction
        conceptPromptAdditions = try container.decodeIfPresent(String.self, forKey: .conceptPromptAdditions)
            ?? defaults.conceptPromptAdditions
        generationCompletionNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .generationCompletionNotificationsEnabled)
            ?? defaults.generationCompletionNotificationsEnabled
        promptEnhancementInstruction = try container.decodeIfPresent(String.self, forKey: .promptEnhancementInstruction) ?? defaults.promptEnhancementInstruction
        promptPresets = try container.decodeIfPresent([PromptPreset].self, forKey: .promptPresets) ?? defaults.promptPresets
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? defaults.language
        defaultOutputDir = try container.decodeIfPresent(String.self, forKey: .defaultOutputDir) ?? defaults.defaultOutputDir
        requestTimeoutSec = try container.decodeIfPresent(Int.self, forKey: .requestTimeoutSec) ?? defaults.requestTimeoutSec
        creditCostCurrency = try container.decodeIfPresent(CreditCostCurrency.self, forKey: .creditCostCurrency)
            ?? defaults.creditCostCurrency
        creditCostPer100Credits = try container.decodeIfPresent(Double.self, forKey: .creditCostPer100Credits)
            ?? defaults.creditCostPer100Credits

        proxyType = try container.decodeIfPresent(ProxyType.self, forKey: .proxyType) ?? defaults.proxyType
        proxyHost = try container.decodeIfPresent(String.self, forKey: .proxyHost) ?? defaults.proxyHost
        proxyPort = try container.decodeIfPresent(Int.self, forKey: .proxyPort) ?? defaults.proxyPort
        proxyUsername = try container.decodeIfPresent(String.self, forKey: .proxyUsername) ?? defaults.proxyUsername
        proxyPassword = try container.decodeIfPresent(String.self, forKey: .proxyPassword) ?? defaults.proxyPassword
        proxyEnabled = try container.decodeIfPresent(Bool.self, forKey: .proxyEnabled) ?? defaults.proxyEnabled
        allowDirectFallback = try container.decodeIfPresent(Bool.self, forKey: .allowDirectFallback) ?? defaults.allowDirectFallback

        if let decodedNoProxyHosts = try container.decodeIfPresent([String].self, forKey: .noProxyHosts) {
            noProxyHosts = decodedNoProxyHosts
        } else if let decodedNoProxyHostsString = try container.decodeIfPresent(String.self, forKey: .noProxyHosts) {
            noProxyHosts = decodedNoProxyHostsString
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            noProxyHosts = defaults.noProxyHosts
        }

        networkPolicyVersion = try container.decodeIfPresent(Int.self, forKey: .networkPolicyVersion) ?? defaults.networkPolicyVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(openAIAPIKey, forKey: .openAIAPIKey)
        try container.encode(openAICompatibleAPIKey, forKey: .openAICompatibleAPIKey)
        try container.encode(openAICompatibleBaseURL, forKey: .openAICompatibleBaseURL)
        try container.encode(kieAPIKey, forKey: .kieAPIKey)
        try container.encode(geminiEnabled, forKey: .geminiEnabled)
        try container.encode(openAIEnabled, forKey: .openAIEnabled)
        try container.encode(openAICompatibleEnabled, forKey: .openAICompatibleEnabled)
        try container.encode(kieEnabled, forKey: .kieEnabled)
        try container.encode(model, forKey: .model)
        try container.encode(promptEnhancementModel, forKey: .promptEnhancementModel)
        try container.encode(promptFromImageInstruction, forKey: .promptFromImageInstruction)
        try container.encode(conceptPromptAdditions, forKey: .conceptPromptAdditions)
        try container.encode(generationCompletionNotificationsEnabled, forKey: .generationCompletionNotificationsEnabled)
        try container.encode(promptEnhancementInstruction, forKey: .promptEnhancementInstruction)
        try container.encode(promptPresets, forKey: .promptPresets)
        try container.encode(language, forKey: .language)
        try container.encode(defaultOutputDir, forKey: .defaultOutputDir)
        try container.encode(requestTimeoutSec, forKey: .requestTimeoutSec)
        try container.encode(creditCostCurrency, forKey: .creditCostCurrency)
        try container.encode(creditCostPer100Credits, forKey: .creditCostPer100Credits)

        try container.encode(proxyType, forKey: .proxyType)
        try container.encode(proxyHost, forKey: .proxyHost)
        try container.encode(proxyPort, forKey: .proxyPort)
        try container.encode(proxyUsername, forKey: .proxyUsername)
        try container.encode(proxyPassword, forKey: .proxyPassword)
        try container.encode(proxyEnabled, forKey: .proxyEnabled)
        try container.encode(allowDirectFallback, forKey: .allowDirectFallback)
        try container.encode(noProxyHosts, forKey: .noProxyHosts)
        try container.encode(networkPolicyVersion, forKey: .networkPolicyVersion)
    }
}
