import EyeProxyCore
import Foundation
import Synchronization
import Testing
@testable import EyeProxyKit

private final class Annotations: Sendable {
    private let list = Mutex<[FlowAnnotation]>([])
    var all: [FlowAnnotation] { list.withLock { $0 } }
    var context: FlowContext {
        FlowContext(id: .init(), clientAddress: "127.0.0.1") { a in self.list.withLock { $0.append(a) } }
    }
}

private func request(_ url: String) -> FlowRequest {
    let c = URLComponents(string: url)!
    return FlowRequest(method: "GET", scheme: c.scheme!, host: c.host!, port: c.port ?? (c.scheme == "http" ? 80 : 443),
                       path: c.percentEncodedPath + (c.percentEncodedQuery.map { "?" + $0 } ?? ""),
                       headers: [HTTPHeader(name: "host", value: c.host!)], body: Data())
}

private func run(_ rule: MapRemoteRule, _ url: String, _ ann: Annotations = Annotations()) async -> FlowRequest? {
    let d = await MapRemoteInterceptor(rules: RuleTree(nodes: [.rule(rule)])).intercept(request(url), context: ann.context)
    if case .continue(let r) = d { return r }
    return nil
}

private func rule(_ pattern: String, _ to: MapTarget, name: String = "R", hostHeader: Bool = false, original: Bool = false) -> MapRemoteRule {
    MapRemoteRule(name: name, match: MatchRule(url: pattern, includeSubpaths: true), mapTo: to,
                  preserveHostHeader: hostHeader, preserveOriginalURL: original)
}

@Test func replacesHostKeepsPathAndQuery() async throws {
    let r = try #require(await run(rule("https://api.example.com/v1/user", MapTarget(host: "staging.example.com")),
                                   "https://api.example.com/v1/user/9?id=1"))
    #expect(r.url == "https://staging.example.com/v1/user/9?id=1")
    #expect(r.header("Host") == "staging.example.com")
    #expect(r.headers.count == 1)
}

@Test func preserveHostHeaderKeepsOriginalHost() async throws {
    let r = try #require(await run(rule("https://api.example.com/*", MapTarget(host: "staging.example.com"), hostHeader: true),
                                   "https://api.example.com/v1"))
    #expect(r.host == "staging.example.com" && r.header("Host") == "api.example.com")
}

@Test func subpathPrefixReplacement() async throws {
    let r = try #require(await run(rule("https://api.example.com/v1/*", MapTarget(path: "v2/api")), "https://api.example.com/v1/a/b?x=1"))
    #expect(r.path == "/v2/api/a/b?x=1")
}

@Test func emptyFieldsKeepComponents() async throws {
    let r = try #require(await run(rule("https://api.example.com/*", MapTarget(scheme: "http", host: "", port: 8080, path: "", query: "")),
                                   "https://api.example.com/v1/a?q=2"))
    #expect(r.url == "http://api.example.com:8080/v1/a?q=2")
    #expect(r.header("Host") == "api.example.com:8080")
}

@Test func schemeChangeFollowsDefaultPort() async throws {
    let r = try #require(await run(rule("https://api.example.com/*", MapTarget(scheme: "http")), "https://api.example.com/x"))
    #expect(r.port == 80 && r.url == "http://api.example.com/x")
}

@Test func queryReplacement() async throws {
    let r = try #require(await run(rule("https://api.example.com/*", MapTarget(query: "id=123")), "https://api.example.com/v1?id=1&b=2"))
    #expect(r.path == "/v1?id=123")
}

@Test func pastedURLParsing() {
    #expect(MapTarget.parse(pastedURL: "https://staging.example.com:8443/v2/api?x=1")
        == MapTarget(scheme: "https", host: "staging.example.com", port: 8443, path: "/v2/api", query: "x=1"))
    #expect(MapTarget.parse(pastedURL: "staging.example.com:8443/v2")
        == MapTarget(scheme: nil, host: "staging.example.com", port: 8443, path: "/v2", query: nil))
}

@Test func annotations() async throws {
    let a = Annotations()
    _ = await run(rule("https://api.example.com/*", MapTarget(host: "staging.example.com")), "https://api.example.com/x", a)
    #expect(a.all == [.tool("Map Remote: R")])
    let b = Annotations()
    _ = await run(rule("https://api.example.com/*", MapTarget(host: "staging.example.com"), original: true), "https://api.example.com/x", b)
    #expect(b.all == [.tool("Map Remote: R"), .originalURL("https://api.example.com/x")])
}

@Test func noMatchPassesThrough() async throws {
    let req = request("https://other.example.com/x")
    let d = await MapRemoteInterceptor(rules: RuleTree(nodes: [.rule(rule("https://api.example.com/*", MapTarget(host: "s.example.com")))]))
        .intercept(req, context: Annotations().context)
    guard case .continue(let r) = d else { Issue.record("not continue"); return }
    #expect(r == req)
}

@Test func proxymanCodingRoundTripAndMissingToURL() throws {
    var rl = rule("https://api.example.com/*", MapTarget(scheme: "https", host: "staging.example.com", port: 8443, path: "/v2", query: "a=1"))
    rl.preserveOriginalURL = true
    let tree = RuleTree(nodes: [.rule(rl)])
    let data = try tree.encoded()
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains(#""toURL""#) && text.contains(#""protocol":"https""#) && text.contains(#""isPreserveOriginalURL":true"#))
    let (back, skipped) = try RuleTree<MapRemoteRule>.decodeLenient(data)
    #expect(skipped == 0 && back == tree)
    let bad = Data(#"[{"_0":{"id":"A","name":"n","isEnabled":true,"url":"x"}}]"#.utf8)
    #expect(try RuleTree<MapRemoteRule>.decodeLenient(bad).skipped == 1)
}
