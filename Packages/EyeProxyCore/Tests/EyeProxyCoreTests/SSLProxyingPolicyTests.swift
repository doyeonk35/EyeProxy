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

@Test func questionMarkMatchesOneCharacter() {
    let p = SSLProxyingPolicy(patterns: ["v?.example.net"])
    #expect(p.shouldDecrypt(host: "v1.example.net")); #expect(!p.shouldDecrypt(host: "v10.example.net")); #expect(!p.shouldDecrypt(host: "v.example.net"))
}
@Test func hostPatternSetExactAndWildcard() {
    let s = HostPatternSet(["API.example.com", "*.example.org"])
    #expect(s.matches("api.example.com")); #expect(!s.matches("x.api.example.com"))
    #expect(s.matches("a.example.org")); #expect(!s.matches("example.org"))
}
@Test func emptyPatternSetMatchesNothing() { #expect(HostPatternSet([]).isEmpty); #expect(!HostPatternSet([]).matches("a")) }
