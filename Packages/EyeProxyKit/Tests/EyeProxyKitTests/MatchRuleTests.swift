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
    ("api.example.com/cb?u=https://x/*", "w", false, false, "GET", "https://api.example.com/cb?u=https://x/y", true),
] as [(String, String, Bool, Bool, String, String, Bool)])
func matchTable(pattern: String, mode: String, subpaths: Bool, ignoreQuery: Bool, method: String, url: String, expected: Bool) {
    let rule = MatchRule(url: pattern, mode: mode == "r" ? .regex : .wildcard, includeSubpaths: subpaths, queryMode: ignoreQuery ? .ignore : .exact)
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
    ("api.example.com/cb?u=https://x/*", "api.example.com"),
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

// MARK: - 쿼리 항목별 선택 매칭

@Test(arguments: [
    ([("screenCode", "CSSD1400", true)], "https://api.example.com/info?screenCode=CSSD1400&apiKey=x", true),
    ([("screenCode", "CSSD1400", true)], "https://api.example.com/info?screenCode=CSSD0100", false),
    ([("screenCode", "CSSD1400", true)], "https://api.example.com/info", false),
    ([("apiKey", "*", true)], "https://api.example.com/info?apiKey=abc", true),
    ([("apiKey", "*", true)], "https://api.example.com/info?other=1", false),
    ([("page", "1", false)], "https://api.example.com/info?page=9", true),
    ([("code", "CS??1400", true)], "https://api.example.com/info?code=CSSD1400", true),
    ([("q", "a b", true)], "https://api.example.com/info?q=a%20b", true),
    ([("k", "v", true)], "https://api.example.com/info?k=x&k=v", true),
    ([], "https://api.example.com/info?x=1", true),
] as [([(String, String, Bool)], String, Bool)])
func selectedQueryMatching(conditions: [(String, String, Bool)], url: String, expected: Bool) {
    let rule = MatchRule(
        url: "https://api.example.com/info", queryMode: .selected,
        queryConditions: conditions.map { QueryCondition(key: $0.0, value: $0.1, isEnabled: $0.2) })
    #expect(rule.matches(request(url)) == expected)
}

@Test func selectedQueryIsCaseSensitiveAndSkipsEmptyKeys() {
    let rule = MatchRule(url: "https://api.example.com/info", queryMode: .selected, queryConditions: [
        QueryCondition(key: "Code", value: "abc", isEnabled: true),
        QueryCondition(key: "", value: "zzz", isEnabled: true),
    ])
    #expect(rule.matches(request("https://api.example.com/info?Code=abc")))
    #expect(!rule.matches(request("https://api.example.com/info?code=abc")))
    #expect(!rule.matches(request("https://api.example.com/info?Code=ABC")))
    #expect(!rule.matches(request("https://api.example.com/other?Code=abc")))
}

@Test func exactModeIsProxymanBehaviour() {
    let any = MatchRule(url: "https://api.example.com/v1/search?*", queryMode: .exact)
    #expect(any.matches(request("https://api.example.com/v1/search?q=1")))
    #expect(!any.matches(request("https://api.example.com/v1/search")))
    let bare = MatchRule(url: "https://api.example.com/v1/search", queryMode: .exact)
    #expect(!bare.matches(request("https://api.example.com/v1/search?q=1")))
    #expect(bare.matches(request("https://api.example.com/v1/search")))
}

@Test func prefilledHasUncheckedConditions() {
    let req = request("https://api.example.com/info?a=1&b=2", method: "POST")
    let rule = MatchRule(prefilledFrom: req)
    #expect(rule.url == "https://api.example.com/info")
    #expect(rule.queryMode == .ignore)
    #expect(rule.queryConditions == [
        QueryCondition(key: "a", value: "1", isEnabled: false),
        QueryCondition(key: "b", value: "2", isEnabled: false),
    ])
    #expect(rule.matches(req))
}

@Test(arguments: [
    ("https://api.example.com/info?a=1&b=*", "https://api.example.com/info", 2),
    ("https://api.example.com/v?/users", "https://api.example.com/v?/users", 0),
    ("api.example.com/search?*", "api.example.com/search?*", 0),
] as [(String, String, Int)])
func splitQueryFromPattern(pattern: String, url: String, count: Int) {
    let split = MatchRule.splitQuery(fromPattern: pattern)
    #expect(split.url == url)
    #expect(split.conditions.count == count)
    #expect(split.conditions.allSatisfy { $0.isEnabled })
}

/// 정규식의 `?`는 수량자·이스케이프된 리터럴이라 쿼리로 떼지 않는다.
@Test(arguments: [#"https:\/\/api\.example\.com\/x\?a=1"#, #".*/users?id=\d+"#, "api.example.com/info?a=1"])
func splitQueryNeverSplitsRegex(pattern: String) {
    let split = MatchRule.splitQuery(fromPattern: pattern, mode: .regex)
    #expect(split.url == pattern)
    #expect(split.conditions.isEmpty)
}

@Test func splitQueryDecodesAndKeepsOrder() {
    let split = MatchRule.splitQuery(fromPattern: "api.example.com/info?q=a%20b&k=")
    #expect(split.conditions == [QueryCondition(key: "q", value: "a b", isEnabled: true), QueryCondition(key: "k", value: "", isEnabled: true)])
}

@Test func queryDescriptionText() {
    let on = QueryCondition(key: "a", value: "1", isEnabled: true)
    let off = QueryCondition(key: "b", value: "2", isEnabled: false)
    #expect(MatchRule(queryMode: .selected, queryConditions: [on, off, on]).queryDescription == "쿼리 2개")
    #expect(MatchRule(queryMode: .selected, queryConditions: [off]).queryDescription == nil)
    #expect(MatchRule(queryMode: .exact).queryDescription == "쿼리 전체 일치")
    #expect(MatchRule(queryMode: .ignore, queryConditions: [on]).queryDescription == nil)
}
