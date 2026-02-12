import Foundation

enum Localizer {
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
        if let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            return NSLocalizedString(key, tableName: "Localizable", bundle: languageBundle, value: key, comment: "")
        }

        return NSLocalizedString(key, tableName: "Localizable", bundle: Bundle.module, value: key, comment: "")
    }
}
