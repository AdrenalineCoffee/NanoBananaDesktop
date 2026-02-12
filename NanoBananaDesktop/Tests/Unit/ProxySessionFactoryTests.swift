import Foundation
import Testing
@testable import NanoBananaDesktop

@Test
func proxyFactoryValidatesHostAndPort() {
    let factory = ProxySessionFactory()
    var config = AppConfig.defaultValue()
    config.proxyEnabled = true
    config.proxyHost = ""
    config.proxyPort = 0

    let validation = factory.validate(config: config)
    #expect(validation.isValid == false)
}

@Test
func proxyFactoryBuildsHTTPProxyDictionary() throws {
    let factory = ProxySessionFactory()
    var config = AppConfig.defaultValue()
    config.proxyEnabled = true
    config.proxyType = .http
    config.proxyHost = "proxy.example.com"
    config.proxyPort = 8080

    let session = try factory.makeSession(config: config, route: .proxy)
    let dictionary = session.configuration.connectionProxyDictionary ?? [:]

    #expect(dictionary[kCFNetworkProxiesHTTPEnable as String] as? Int == 1)
    #expect(dictionary[kCFNetworkProxiesHTTPProxy as String] as? String == "proxy.example.com")
    #expect(dictionary[kCFNetworkProxiesHTTPPort as String] as? Int == 8080)
}

@Test
func proxyFactoryBuildsSocksProxyDictionaryWithAuth() throws {
    let factory = ProxySessionFactory()
    var config = AppConfig.defaultValue()
    config.proxyEnabled = true
    config.proxyType = .socks5
    config.proxyHost = "socks.example.com"
    config.proxyPort = 1080
    config.proxyUsername = "user"
    config.proxyPassword = "pass"

    let session = try factory.makeSession(config: config, route: .proxy)
    let dictionary = session.configuration.connectionProxyDictionary ?? [:]

    #expect(dictionary[kCFNetworkProxiesSOCKSEnable as String] as? Int == 1)
    #expect(dictionary[kCFNetworkProxiesSOCKSProxy as String] as? String == "socks.example.com")
    #expect(dictionary[kCFNetworkProxiesSOCKSPort as String] as? Int == 1080)
    #expect(dictionary[kCFStreamPropertySOCKSUser as String] as? String == "user")
}

@Test
func proxyFactoryReturnsDirectSessionForFallbackRoute() throws {
    let factory = ProxySessionFactory()
    let config = AppConfig.defaultValue()

    let session = try factory.makeSession(config: config, route: .directFallback)
    let dictionary = session.configuration.connectionProxyDictionary ?? [:]

    #expect(dictionary.isEmpty)
}
