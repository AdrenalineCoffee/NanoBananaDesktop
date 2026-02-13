import Foundation

enum Localizer {
    private static let resourceBundleName = "NanoBananaDesktop_NanoBananaDesktop.bundle"
    private static let localizationBundle: Bundle = resolveLocalizationBundle()

    static func string(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        string(key, language: language, arguments)
    }

    static func string(_ key: String, language: AppLanguage, _ arguments: [CVarArg]) -> String {
        let value = localizedValue(for: key, language: language)
        guard !arguments.isEmpty else {
            return value
        }

        return withVaList(arguments) { pointer in
            NSString(
                format: value,
                locale: Locale(identifier: language.localeIdentifier),
                arguments: pointer
            ) as String
        }
    }

    private static func localizedValue(for key: String, language: AppLanguage) -> String {
        if let path = localizationBundle.path(forResource: language.rawValue, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            return NSLocalizedString(key, tableName: "Localizable", bundle: languageBundle, value: key, comment: "")
        }

        return NSLocalizedString(key, tableName: "Localizable", bundle: localizationBundle, value: key, comment: "")
    }

    private static func resolveLocalizationBundle() -> Bundle {
        let fileManager = FileManager.default
        let mainBundle = Bundle.main
        var candidateURLs: [URL] = []

        if let resourceURL = mainBundle.resourceURL {
            candidateURLs.append(resourceURL.appendingPathComponent(resourceBundleName, isDirectory: true))
        }
        candidateURLs.append(mainBundle.bundleURL.appendingPathComponent(resourceBundleName, isDirectory: true))
        if let executableDir = mainBundle.executableURL?.deletingLastPathComponent() {
            candidateURLs.append(executableDir.appendingPathComponent(resourceBundleName, isDirectory: true))
        }

        for candidateURL in candidateURLs {
            guard fileManager.fileExists(atPath: candidateURL.path) else {
                continue
            }
            if let bundle = Bundle(url: candidateURL) {
                return bundle
            }
        }

        let allBundles = Bundle.allBundles + Bundle.allFrameworks
        if let bundle = allBundles.first(where: { $0.bundleURL.lastPathComponent == resourceBundleName }) {
            return bundle
        }

        return mainBundle
    }
}
