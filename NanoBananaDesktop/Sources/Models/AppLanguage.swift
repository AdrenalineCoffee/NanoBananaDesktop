import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case ru
    case en

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .ru:
            return "ru"
        case .en:
            return "en"
        }
    }

    static func systemDefault() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("ru") ? .ru : .en
    }
}
