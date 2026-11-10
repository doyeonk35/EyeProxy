import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private func rule(_ key: FilterKey, _ match: FilterMatch, _ text: String, enabled: Bool = true) -> FilterRule {
    FilterRule(isEnabled: enabled, key: key, match: match, text: text)
}

private func subject(_ url: String, method: String = "GET", status: Int = 200) -> FilterSubject {
    FilterSubject(flow: .fixture(url: url, method: method, status: status))
}

@Test func everyKeyExtractsExpectedValue() throws {
    var f = Flow.fixture(url: "https://api.example.com:8443/v2/search?q=cat&page=2", method: "POST", status: 201)
    f.completedAt = f.startedAt.addingTimeInterval(1.5)
    f.request.headers = [HTTPHeader(name: "X-Token", value: "abc")]
    f.request.body = Data(#"{"name":"kitty"}"#.utf8)
    let gz = try gzip(Data("hello world".utf8))
    f.response?.headers = [HTTPHeader(name: "Content-Type", value: "application/json"), HTTPHeader(name: "Content-Encoding", value: "gzip")]
    f.response?.body = gz
    let s = FilterSubject(flow: f, number: 7, comment: "note", highlight: FlowHighlight(color: .red), client: "Safari")

    let expected: [FilterKey: String] = [
        .url: "https://api.example.com:8443/v2/search?q=cat&page=2",
        .host: "api.example.com",
        .queryString: "q=cat&page=2",
        .requestHeader: "X-Token: abc",
        .responseHeader: "Content-Type: application/json\nContent-Encoding: gzip",
        .requestBody: #"{"name":"kitty"}"#,
        .responseBody: "hello world",
        .method: "POST",
        .statusCode: "201",
        .client: "Safari",
        .ipAddress: "192.168.0.21",
        .comment: "note",
        .color: "red",
        .duration: "1500",
        .requestBodySize: String(Double(f.request.body.count) / 1024),
        .responseBodySize: String(Double(gz.count) / 1024),
    ]
    #expect(Set(expected.keys) == Set(FilterKey.allCases) && FilterKey.allCases.count == 16)
    for (key, value) in expected { #expect(s.value(for: key) == value, "\(key)") }
    #expect(s.number == 7)
    #expect(s.numericValue(for: .statusCode) == 201 && s.numericValue(for: .duration) == 1500)
    #expect(s.numericValue(for: .responseBodySize) == Double(gz.count) / 1024 && s.numericValue(for: .url) == nil)
    #expect(FilterKey.allCases.filter(\.isNumeric) == [.statusCode, .duration, .requestBodySize, .responseBodySize])
    #expect(FilterRule(key: .requestBody, match: .contains, text: "x").needsBody && FilterRule(key: .responseBody, match: .contains, text: "x").needsBody)
    #expect(!FilterRule(key: .url, match: .contains, text: "x").needsBody)
    #expect(FilterKey.duration.rawValue == "Duration (ms)" && FilterMatch.lessThan.rawValue == "<")

    // 기본값과 응답 없는 흐름: 숫자 없음, 문자열은 빈 값.
    var pending = Flow.fixture(url: "https://api.example.com/", method: "GET", status: 200); pending.response = nil
    let p = FilterSubject(flow: pending)
    #expect(p.value(for: .statusCode) == "" && p.numericValue(for: .statusCode) == nil && p.numericValue(for: .duration) == nil)
    #expect(p.value(for: .comment) == "" && p.value(for: .color) == "" && p.value(for: .responseBody) == "" && p.value(for: .queryString) == "")
}

@Test func everyMatchModeBehaves() {
    let s = subject("https://api.example.com/v2/Search?q=1")
    let cases: [(FilterMatch, String, Bool)] = [
        (.contains, "SEARCH", true), (.contains, "nope", false),
        (.notContains, "nope", true), (.notContains, "search", false),
        (.startWith, "HTTPS://API", true), (.startWith, "api", false),
        (.endWith, "Q=1", true), (.endWith, "search", false),
        (.equal, "HTTPS://API.EXAMPLE.COM/v2/search?q=1", true), (.equal, "https://api.example.com", false),
        (.notEqual, "https://api.example.com", true), (.notEqual, "https://api.example.com/v2/search?q=1", false),
        (.matchWildcard, "*.EXAMPLE.com/*", true), (.matchWildcard, "https://api.example.com/v?/search*", true),
        (.matchWildcard, "*.example.org/*", false), (.matchWildcard, "example", false),
        (.notMatchWildcard, "*.example.org/*", true), (.notMatchWildcard, "*example*", false),
        (.matchRegex, #"V\d+/search"#, true), (.matchRegex, "^api", false),
        (.notMatchRegex, "^api", true), (.notMatchRegex, "search", false),
    ]
    for (match, text, want) in cases { #expect(rule(.url, match, text).matches(s) == want, "\(match.rawValue) \(text)") }
    #expect(Set(cases.map(\.0)).count == FilterMatch.allCases.count - 2)
}

@Test func numericMatchesOnlyNumericKeys() {
    #expect(FilterMatch.allCases.filter(\.isNumericOnly) == [.lessThan, .greaterOrEqual])
    let s = subject("https://api.example.com/500", status: 404)
    #expect(rule(.statusCode, .lessThan, "500").matches(s) && !rule(.statusCode, .lessThan, "404").matches(s))
    #expect(rule(.statusCode, .greaterOrEqual, "404").matches(s) && !rule(.statusCode, .greaterOrEqual, "405").matches(s))
    #expect(!rule(.statusCode, .lessThan, "abc").matches(s))
    // 숫자 키가 아니면 URL에 숫자가 있어도 맞지 않는다.
    #expect(!rule(.url, .lessThan, "999").matches(s) && !rule(.url, .greaterOrEqual, "0").matches(s))
    // 텍스트 매칭은 숫자 키에도 된다.
    #expect(rule(.statusCode, .startWith, "4").matches(s))

    var pending = Flow.fixture(url: "https://api.example.com/", method: "GET", status: 200); pending.response = nil
    #expect(!rule(.statusCode, .lessThan, "1000").matches(FilterSubject(flow: pending)))
    #expect(!rule(.duration, .greaterOrEqual, "0").matches(FilterSubject(flow: pending)))

    var big = Flow.fixture(url: "https://api.example.com/", method: "GET", status: 200)
    big.response?.body = Data(count: 3 * 1024); big.completedAt = big.startedAt.addingTimeInterval(0.25)
    let b = FilterSubject(flow: big)
    #expect(rule(.responseBodySize, .greaterOrEqual, "3").matches(b) && rule(.responseBodySize, .lessThan, "3.5").matches(b))
    #expect(rule(.duration, .lessThan, "300").matches(b) && !rule(.duration, .greaterOrEqual, "300").matches(b))
}

@Test func multipleRulesCombineWithAndOr() {
    let flow = Flow.fixture(url: "https://api.example.com/v2", method: "GET", status: 200)
    var f = FlowFilter()
    f.rules = [rule(.host, .contains, "api"), rule(.method, .equal, "post")]
    #expect(!f.matches(flow))
    f.combineWithOr = true
    #expect(f.matches(flow))
    f.rules = [rule(.host, .contains, "nope"), rule(.method, .equal, "post")]
    #expect(!f.matches(flow))
    f.combineWithOr = false
    f.rules = [rule(.host, .contains, "api"), rule(.method, .equal, "GET")]
    #expect(f.matches(flow))
    // 최대 10개.
    f.rules = Array(repeating: rule(.url, .contains, "a"), count: 12)
    #expect(f.rules.count == FlowFilter.maxRules && FlowFilter.maxRules == 10)
}

@Test func disabledAndEmptyRulesPass() {
    let flow = Flow.fixture(url: "https://api.example.com/v2", method: "GET", status: 200)
    var f = FlowFilter()
    f.rules = [rule(.host, .contains, "nope", enabled: false), rule(.method, .equal, "")]
    #expect(f.matches(flow))
    #expect(f.rules.allSatisfy { !$0.isActive })
    // OR에서도 꺼진·빈 규칙은 "맞음"으로 세지 않는다.
    f.combineWithOr = true
    f.rules = [rule(.method, .equal, ""), rule(.host, .contains, "nope")]
    #expect(!f.matches(flow))
    f.rules = [rule(.method, .equal, ""), rule(.host, .contains, "nope", enabled: false)]
    #expect(f.matches(flow))
    let defaults = FilterRule()
    #expect(defaults.isEnabled && defaults.key == .url && defaults.match == .contains && defaults.text.isEmpty)
}

@Test func invalidRegexIsIgnoredAndFlagged() {
    let flow = Flow.fixture(url: "https://api.example.com/v2", method: "GET", status: 200)
    let bad = rule(.url, .matchRegex, "([")
    #expect(bad.isInvalid && rule(.url, .notMatchRegex, "([").isInvalid)
    #expect(!rule(.url, .contains, "([").isInvalid && !rule(.url, .matchRegex, "v2$").isInvalid && !rule(.url, .matchWildcard, "([").isInvalid)
    var f = FlowFilter()
    f.rules = [bad]
    #expect(f.matches(flow))
    f.rules = [bad, rule(.url, .matchRegex, "nope")]
    #expect(!f.matches(flow))
}

@Test func legacyTextMigratesToURLContainsRule() throws {
    let legacy = try JSONDecoder().decode(FlowFilter.self, from: Data(#"{"text":"search"}"#.utf8))
    #expect(legacy.rules.count == 1)
    let r = try #require(legacy.rules.first)
    #expect(r.isEnabled && r.key == .url && r.match == .contains && r.text == "search" && !legacy.combineWithOr)
    #expect(try JSONDecoder().decode(FlowFilter.self, from: Data(#"{"text":""}"#.utf8)).rules.isEmpty)
    #expect(try JSONDecoder().decode(FlowFilter.self, from: Data("{}".utf8)).rules.isEmpty)

    var f = FlowFilter()
    f.rules = [rule(.statusCode, .greaterOrEqual, "400"), rule(.host, .endWith, "example.com", enabled: false)]
    f.combineWithOr = true
    let back = try JSONDecoder().decode(FlowFilter.self, from: JSONEncoder().encode(f))
    #expect(back.rules == f.rules && back.combineWithOr)
}

@Test func bodyRuleMatchingRunsOffMain() async throws {
    let needle = "needle-7f3a"
    let megabyte = Data(repeating: UInt8(ascii: "x"), count: 1_000_000)
    let bigHit = megabyte + Data(needle.utf8)
    let gzHit = try gzip(Data(repeating: UInt8(ascii: "y"), count: 1_000_000) + Data(needle.uppercased().utf8))
    var flows: [Flow] = []
    var expected: Set<FlowID> = []
    for i in 0..<5_000 {
        var f = Flow.fixture(url: "https://api.example.com/item/\(i)", method: "GET", status: 200)
        switch i % 10 {
        case 0: f.response?.body = bigHit; expected.insert(f.id)
        case 1: f.response?.body = megabyte
        case 2: f.response?.body = gzHit; f.response?.headers = [HTTPHeader(name: "Content-Encoding", value: "gzip")]; expected.insert(f.id)
        case 3: f.response?.body = Data(#"{"k":"\#(needle)"}"#.utf8); expected.insert(f.id)
        default: f.response?.body = Data(#"{"k":"v"}"#.utf8)
        }
        flows.append(f)
    }
    var filter = FlowFilter()
    filter.rules = [FilterRule(key: .responseBody, match: .contains, text: needle)]
    #expect(filter.rules.contains { $0.needsBody })
    let snapshot = filter
    let subjects = flows.map { FilterSubject(flow: $0) }
    let start = ContinuousClock.now
    let matched = await Task.detached { subjects.filter { snapshot.matches($0) }.map(\.flow.id) }.value
    print("bodyRuleMatchingRunsOffMain: \(ContinuousClock.now - start) for \(subjects.count) flows")
    #expect(Set(matched) == expected && matched.count == 1_500)
}

@Test func preparedFilterUsesPrecomputedBodyHits() {
    var flow = Flow.fixture(url: "https://api.example.com/v2", method: "GET", status: 200)
    flow.response?.body = Data(#"{"token":"abc"}"#.utf8)
    let s = FilterSubject(flow: flow)
    var f = FlowFilter()
    f.rules = [rule(.host, .contains, "api"), rule(.responseBody, .contains, "nope"), rule(.url, .matchRegex, "(["),
               rule(.requestBody, .notContains, "x"), rule(.responseBody, .contains, "TOKEN", enabled: false)]
    #expect(f.hasActiveRules && f.activeBodyRules.map(\.key) == [.responseBody, .requestBody])
    let p = f.prepared()
    #expect(p.bodyRules == f.activeBodyRules)  // 꺼진·잘못된 규칙은 빠진다
    #expect(p.bodyHits(s) == [false, true])
    #expect(!p.matches(s) && !p.matches(s, bodyHits: [false, true]))
    // 미리 판정한 결과를 그대로 쓴다(본문을 다시 보지 않는다).
    #expect(p.matches(s, bodyHits: [true, true]))
    #expect(!p.matches(s, bodyHits: []))  // 판정 전 흐름은 본문 규칙에 맞지 않는다
    f.combineWithOr = true
    #expect(f.prepared().matches(s, bodyHits: []))  // OR: 가벼운 규칙(Host)만으로 통과
    #expect(!FlowFilter().hasActiveRules && FlowFilter().activeBodyRules.isEmpty)
}
