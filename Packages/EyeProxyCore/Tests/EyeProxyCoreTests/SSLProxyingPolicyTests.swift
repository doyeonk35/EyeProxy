import Testing
@testable import EyeProxyCore

@Test func wildcardMatching() {
    let p = SSLProxyingPolicy(patterns: ["*.example.com", "example.org"])
    #expect(p.shouldDecrypt(host: "api.example.com"))
    #expect(p.shouldDecrypt(host: "API.EXAMPLE.COM"))
    #expect(!p.shouldDecrypt(host: "example.com"))        // *.는 서브도메인만
    #expect(p.shouldDecrypt(host: "example.org"))
    #expect(!p.shouldDecrypt(host: "notexample.org"))
}
@Test func disabledNeverDecrypts() { #expect(!SSLProxyingPolicy(isEnabled: false, patterns: ["*"]).shouldDecrypt(host: "a")) }
@Test func starMatchesEverything() { #expect(SSLProxyingPolicy(patterns: ["*"]).shouldDecrypt(host: "x.y")) }
