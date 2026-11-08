import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private func request(_ url: String, method: String = "GET") -> FlowRequest {
    let c = URLComponents(string: url)!
    let scheme = c.scheme ?? "https"
    let host = (c.host ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    let port = c.port ?? (scheme == "http" ? 80 : 443)
    var path = c.percentEncodedPath
    if let q = c.percentEncodedQuery { path += "?" + q }
    return FlowRequest(method: method, scheme: scheme, host: host, port: port, path: path, headers: [], body: Data())
}

@Test(arguments: [
    ("https://api.example.com/v1/search?*", "w", false, false, "GET", "https://api.example.com/v1/search?q=1", true),
    ("https://api.example.com/v1/search?*", "w", false, false, "GET", "https://api.example.com/v1/search", false),
    ("https://api.example.com/v1/search", "w", false, true, "GET", "https://api.example.com/v1/search?q=1&p=2", true),
    ("https://api.example.com/v1/search", "w", false, true, "GET", "https://api.example.com/v1/search", true),
    ("https://api.example.com/v1/search", "w", false, false, "GET", "https://api.example.com/v1/search?q=1", false),
    ("https://api.example.com/v?/users", "w", false, true, "GET", "https://api.example.com/v2/users?x=1", true),
    ("api.example.com/v1/*", "w", false, false, "GET", "http://api.example.com/v1/a/b", true),
    ("api.example.com", "w", false, false, "GET", "https://api.example.com/any/path?x=1", true),
    ("https://api.example.com/v1/user", "w", true, false, "GET", "https://api.example.com/v1/user/9", true),
    ("https://api.example.com/v1/user", "w", true, false, "GET", "https://api.example.com/v1/userX", false),
    ("https:\\/\\/api\\.example\\.com\\/v1\\/.*", "r", false, false, "GET", "https://api.example.com/v1/x?y=1", true),
    ("https:\\/\\/api\\.example\\.com", "r", false, false, "GET", "https://api.example.com/v1", false),
    ("http://127.0.0.1:8080/x", "w", false, false, "GET", "http://127.0.0.1:8080/x", true),
    ("http://[::1]:8080/x", "w", false, false, "GET", "http://[::1]:8080/x", true),
    ("HTTPS://API.EXAMPLE.COM/a", "w", false, false, "get", "https://api.example.com/a", true),
] as [(String, String, Bool, Bool, String, String, Bool)])
func matchTable(pattern: String, mode: String, subpaths: Bool, ignoreQuery: Bool, method: String, url: String, expected: Bool) {
    let rule = MatchRule(url: pattern, mode: mode == "r" ? .regex : .wildcard, includeSubpaths: subpaths, ignoreQuery: ignoreQuery)
    #expect(rule.matches(request(url, method: method)) == expected)
}

@Test func methodExactFilters() {
    let rule = MatchRule(url: "https://api.example.com/a", methods: .exact(["POST"]))
    #expect(!rule.matches(request("https://api.example.com/a", method: "GET")))
    #expect(rule.matches(request("https://api.example.com/a", method: "post")))
}

@Test func invalidRegexNeverMatchesAndReportsError() {
    let rule = MatchRule(url: "([", mode: .regex)
    #expect(!rule.matches(request("https://api.example.com/a")))
    #expect(rule.validationError != nil)
    #expect(MatchRule(url: "a.*", mode: .regex).validationError == nil)
    #expect(MatchRule(url: "([", mode: .wildcard).validationError == nil)
}

@Test(arguments: [
    ("https://*.example.com/v1/*", "*.example.com"),
    ("api?.example.com/x", "api?.example.com"),
    ("https://api.example.com:8443/x", "api.example.com"),
    ("http://api.example.com/x", nil),
    ("*", nil),
    ("https://*/x", nil),
    ("https://API.Example.com/x", "api.example.com"),
] as [(String, String?)])
func hostPatternExtraction(pattern: String, expected: String?) {
    #expect(MatchRule(url: pattern).hostPattern == expected)
    #expect(MatchRule(url: pattern, mode: .regex).hostPattern == nil)
}

@Test func queryLikePatternDetection() {
    #expect(MatchRule(url: "https://api.example.com/v1/search?*").hasQueryLikePattern)
    #expect(!MatchRule(url: "https://api.example.com/v?/users").hasQueryLikePattern)
    #expect(MatchRule(url: "https://api.example.com/x?a=1").hasQueryLikePattern)
}
