import CFNetwork
import Foundation

protocol NetworkClientProvider {
    func validate(config: AppConfig) -> ProxyValidationResult
    func makeSession(config: AppConfig, route: NetworkRoute) throws -> URLSession
}

struct ProxySessionFactory: NetworkClientProvider {
    private let protocolClasses: [AnyClass]?

    init(protocolClasses: [AnyClass]? = nil) {
        self.protocolClasses = protocolClasses
    }

    func validate(config: AppConfig) -> ProxyValidationResult {
        if !config.proxyEnabled {
            return .valid
        }

        let host = config.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty {
            return .invalid(.proxyInvalidSettings("Proxy host is required."))
        }

        if config.proxyPort < 1 || config.proxyPort > 65535 {
            return .invalid(.proxyInvalidSettings("Proxy port must be between 1 and 65535."))
        }

        let username = config.proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = config.proxyPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        if !username.isEmpty && password.isEmpty {
            return .invalid(.proxyInvalidSettings("Proxy password is required when username is set."))
        }

        return .valid
    }

    func makeSession(config: AppConfig, route: NetworkRoute) throws -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        // Fail fast when connectivity is missing to avoid very long perceived hangs.
        configuration.waitsForConnectivity = false

        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }

        switch route {
        case .proxy:
            guard config.proxyEnabled else {
                throw AppError.proxyNotConfigured
            }

            let validation = validate(config: config)
            if let error = validation.error {
                throw error
            }

            configuration.connectionProxyDictionary = proxyDictionary(config: config)

        case .directFallback:
            configuration.connectionProxyDictionary = [:]
        }

        return URLSession(configuration: configuration)
    }

    private func proxyDictionary(config: AppConfig) -> [AnyHashable: Any] {
        let host = config.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = config.proxyPort

        var dictionary: [AnyHashable: Any] = [:]

        switch config.proxyType {
        case .http, .httpsConnect:
            dictionary[kCFNetworkProxiesHTTPEnable as String] = 1
            dictionary[kCFNetworkProxiesHTTPProxy as String] = host
            dictionary[kCFNetworkProxiesHTTPPort as String] = port

            dictionary[kCFNetworkProxiesHTTPSEnable as String] = 1
            dictionary[kCFNetworkProxiesHTTPSProxy as String] = host
            dictionary[kCFNetworkProxiesHTTPSPort as String] = port

            let username = config.proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            if !username.isEmpty {
                dictionary[kCFProxyUsernameKey as String] = username
                dictionary[kCFProxyPasswordKey as String] = config.proxyPassword
            }

        case .socks5:
            dictionary[kCFNetworkProxiesSOCKSEnable as String] = 1
            dictionary[kCFNetworkProxiesSOCKSProxy as String] = host
            dictionary[kCFNetworkProxiesSOCKSPort as String] = port

            let username = config.proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            if !username.isEmpty {
                dictionary[kCFStreamPropertySOCKSUser as String] = username
                dictionary[kCFStreamPropertySOCKSPassword as String] = config.proxyPassword
            }
        }

        if !config.noProxyHosts.isEmpty {
            dictionary[kCFNetworkProxiesExceptionsList as String] = config.noProxyHosts
        }

        return dictionary
    }
}
