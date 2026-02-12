import Foundation

enum ProxyType: String, Codable, CaseIterable, Identifiable {
    case http
    case httpsConnect
    case socks5

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .http:
            return "proxy.type.http"
        case .httpsConnect:
            return "proxy.type.https_connect"
        case .socks5:
            return "proxy.type.socks5"
        }
    }
}

enum NetworkRoute: String, Codable, CaseIterable, Identifiable {
    case proxy
    case directFallback

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .proxy:
            return "route.proxy"
        case .directFallback:
            return "route.direct_fallback"
        }
    }
}

enum HistoryRouteFilter: String, CaseIterable, Identifiable {
    case all
    case proxy
    case directFallback

    var id: String { rawValue }
}

struct ProxySettings: Codable, Equatable {
    var type: ProxyType
    var host: String
    var port: Int
    var username: String
    var password: String
    var enabled: Bool
    var allowDirectFallback: Bool
    var noProxyHosts: [String]
}

struct ProxyValidationResult {
    let isValid: Bool
    let error: AppError?

    static let valid = ProxyValidationResult(isValid: true, error: nil)

    static func invalid(_ error: AppError) -> ProxyValidationResult {
        ProxyValidationResult(isValid: false, error: error)
    }
}
