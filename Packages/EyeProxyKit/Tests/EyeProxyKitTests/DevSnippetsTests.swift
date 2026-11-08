import Testing
@testable import EyeProxyKit

private let pem = "/tmp/eyeproxy/ca.pem"

@Test func everyPlatformMentionsPemAndProxy() {
    for platform in DevPlatform.allCases {
        let guide = DevSnippets.guide(for: platform, pemPath: pem, proxyHost: "127.0.0.1", proxyPort: 9090)
        let text = guide.snippet + guide.steps.joined()
        if platform != .reactNative {
            #expect(text.contains(pem), "\(platform.rawValue)")
        }
        let proxy = platform == .docker ? "host.docker.internal:9090" : "127.0.0.1:9090"
        #expect(text.contains(proxy), "\(platform.rawValue)")
    }
}

@Test func nodeUsesExtraCACerts() {
    let guide = DevSnippets.guide(for: .nodeJS, pemPath: pem, proxyHost: "127.0.0.1", proxyPort: 9090)
    #expect(guide.snippet.contains("NODE_EXTRA_CA_CERTS="))
}

@Test func pythonUsesRequestsBundle() {
    let guide = DevSnippets.guide(for: .python, pemPath: pem, proxyHost: "127.0.0.1", proxyPort: 9090)
    #expect(guide.snippet.contains("REQUESTS_CA_BUNDLE="))
    #expect(guide.snippet.contains("SSL_CERT_FILE="))
}

@Test func snippetsUseProgNames() {
    let java = DevSnippets.guide(for: .java, pemPath: pem, proxyHost: "127.0.0.1", proxyPort: 9090)
    #expect(java.snippet.contains("-alias prog "))
    let docker = DevSnippets.guide(for: .docker, pemPath: pem, proxyHost: "127.0.0.1", proxyPort: 9090)
    #expect(docker.snippet.contains("/usr/local/share/ca-certificates/prog.crt"))
}

@Test func javaImportsWithoutPrompt() {
    let java = DevSnippets.guide(for: .java, pemPath: pem, proxyHost: "127.0.0.1", proxyPort: 9090)
    #expect(java.snippet.contains("-noprompt"))
    #expect(java.snippet.contains("-cacerts"))
}

@Test func trustStoreReplacingPlatformsUseCombinedBundle() {
    for platform in [DevPlatform.httpClients, .python, .ruby] {
        let guide = DevSnippets.guide(for: platform, pemPath: pem, proxyHost: "127.0.0.1", proxyPort: 9090)
        #expect(guide.snippet.contains("/etc/ssl/cert.pem"), "\(platform.rawValue)")
        #expect(guide.snippet.contains("prog-bundle.pem"), "\(platform.rawValue)")
        #expect(!guide.snippet.contains("SSL_CERT_FILE=\"\(pem)\""), "\(platform.rawValue)")
    }
}

@Test func everyGuideStartsWithSSLProxyingStep() {
    for platform in DevPlatform.allCases {
        let guide = DevSnippets.guide(for: platform, pemPath: pem, proxyHost: "127.0.0.1", proxyPort: 9090)
        #expect(guide.steps.first?.contains("SSL Proxying") == true, "\(platform.rawValue)")
    }
}
