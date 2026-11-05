import Testing
@testable import EyeProxyCore

@Test func wildcardMatching() {
    let p = SSLProxyingPolicy(patterns: ["*.tving.com", "example.org"])
    #expect(p.shouldDecrypt(host: "api.tving.com"))
    #expect(p.shouldDecrypt(host: "API.TVING.COM"))
    #expect(!p.shouldDecrypt(host: "tving.com"))        // *.는 서브도메인만
    #expect(p.shouldDecrypt(host: "example.org"))
    #expect(!p.shouldDecrypt(host: "notexample.org"))
}
@Test func disabledNeverDecrypts() { #expect(!SSLProxyingPolicy(isEnabled: false, patterns: ["*"]).shouldDecrypt(host: "a")) }
@Test func starMatchesEverything() { #expect(SSLProxyingPolicy(patterns: ["*"]).shouldDecrypt(host: "x.y")) }
