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

private func request(_ url: String, method: String = "GET") -> FlowRequest {
    let c = URLComponents(string: url)!
    return FlowRequest(method: method, scheme: c.scheme!, host: c.host!, port: c.port ?? 443,
                       path: c.percentEncodedPath + (c.percentEncodedQuery.map { "?" + $0 } ?? ""), headers: [], body: Data())
}

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("maplocal-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// 픽스처 트리. `FIXTURES` 자리표시자를 번들 안 픽스처 폴더 절대 경로로 바꾼다.
private func fixtureTree() throws -> RuleTree<MapLocalRule> {
    let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("Proxyman")
    let raw = try String(contentsOf: root.appendingPathComponent("MapLocalFiles-RuleTree.json"), encoding: .utf8)
    let (tree, skipped) = try RuleTree<MapLocalRule>.decodeLenient(Data(raw.replacingOccurrences(of: "FIXTURES", with: root.path).utf8))
    #expect(skipped == 0)
    return tree
}

private func fileRule(_ path: String, delay: Int? = nil) -> RuleTree<MapLocalRule> {
    RuleTree(nodes: [.rule(MapLocalRule(name: "R", match: MatchRule(url: "https://api.example.com/*"),
                                        localFile: LocalFileRef(name: "x", path: path), delaySeconds: delay))])
}

@Test func decodesProxymanFixture() throws {
    let tree = try fixtureTree()
    #expect(tree.enabledRules.count == 1)
    let r = try #require(tree.enabledRules.first)
    #expect(r.id == "19A8BA07" && r.name == "search")
    #expect(r.match.url == "https://api.example.com/v1/search?*")
    #expect(r.match.methods == .exact(["GET"]))
    #expect(r.match.ignoreQuery == false)
    #expect(r.useLocalFile && !r.useDirectory && r.directoryPath == nil)
    #expect(r.delaySeconds == 10)
    #expect(r.localFile?.name == "default_message")
}

@Test func encodesProxymanKeysAndRoundTrips() throws {
    var tree = try fixtureTree()
    guard case .rule(var r) = tree.nodes[0] else { Issue.record("not a rule"); return }
    let text = String(decoding: try tree.encoded(), as: UTF8.self)
    #expect(text.contains(#""advanceSettings":{"delayTimePreset":10}"#))
    #expect(text.contains(#""directoryFile":null"#) && text.contains(#""isDirectoryFileEnable":false"#))
    #expect(text.contains(#""isLocalFileEnable":true"#) && text.contains(#""localFile":{"name":"default_message","path":"#))

    r.delaySeconds = nil
    r.useDirectory = true
    r.directoryPath = "/tmp/site"
    tree.nodes[0] = .rule(r)
    let data = try tree.encoded()
    let again = String(decoding: data, as: UTF8.self)
    #expect(again.contains(#""advanceSettings":{}"#) && again.contains(#""directoryFile":{"path":"\/tmp\/site"}"#))
    #expect(try RuleTree<MapLocalRule>.decodeLenient(data).tree == tree)
}

@Test func directoryFileAcceptsPlainString() throws {
    let json = #"[{"nodeType":{"node":{"_0":{"id":"D","name":"D","isEnabled":true,"url":"api.example.com","regex":"useWildcard","method":{"any":{}},"isLocalFileEnable":false,"isDirectoryFileEnable":true,"directoryFile":"/tmp/site"}}}}]"#
    let (tree, skipped) = try RuleTree<MapLocalRule>.decodeLenient(Data(json.utf8))
    #expect(skipped == 0)
    #expect(tree.enabledRules.first?.directoryPath == "/tmp/site")
    #expect(tree.enabledRules.first?.delaySeconds == nil)
}

@Test func newRuleDefaults() {
    let r = MapLocalRule()
    #expect(r.name == "Untitled" && r.isEnabled && r.match.ignoreQuery)
    #expect(r.id.count == 8 && r.id.allSatisfy { $0.isHexDigit && !$0.isLowercase })
    #expect(MapLocalRule.delayPresets == [nil, 1, 2, 3, 5, 10, 30])
    #expect(RuleFile<MapLocalRule>.mapLocal.name == "map-local.json")
}

@Test func respondsWithMessageFile() async throws {
    let a = Annotations()
    let rule = try #require(try fixtureTree().enabledRules.first)
    var fast = rule
    fast.delaySeconds = nil
    let i = MapLocalInterceptor(rules: RuleTree(nodes: [.rule(fast)]))
    guard case .respond(let res) = await i.intercept(request("https://api.example.com/v1/search?q=1"), context: a.context) else {
        Issue.record("not respond"); return
    }
    #expect(res.status == 200 && res.body == Data(#"{"items":[]}"#.utf8))
    #expect(res.header("Content-Type") == "application/json; charset=utf-8")
    #expect(a.all == [.tool("Map Local: search")])
}

@Test func nonMatchingRequestContinuesUntouched() async throws {
    let a = Annotations()
    let i = MapLocalInterceptor(rules: try fixtureTree())
    let q = request("https://api.example.com/v1/search")
    guard case .continue(let out) = await i.intercept(q, context: a.context) else { Issue.record("not continue"); return }
    #expect(out == q && a.all.isEmpty)
}

@Test func missingFileContinuesWithAnnotation() async throws {
    let a = Annotations()
    let i = MapLocalInterceptor(rules: fileRule("/nonexistent-\(UUID().uuidString)/x.http"))
    let q = request("https://api.example.com/a")
    guard case .continue(let out) = await i.intercept(q, context: a.context) else { Issue.record("not continue"); return }
    #expect(out == q)
    #expect(a.all == [.tool("Map Local 파일 없음: R")])
}

@Test func plainFileBecomesBody() async throws {
    let dir = try tempDir()
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    try png.write(to: dir.appendingPathComponent("a.png"))
    let i = MapLocalInterceptor(rules: fileRule(dir.appendingPathComponent("a.png").path))
    guard case .respond(let res) = await i.intercept(request("https://api.example.com/a"), context: Annotations().context) else {
        Issue.record("not respond"); return
    }
    #expect(res.status == 200 && res.body == png && res.header("Content-Type") == "image/png")
}

@Test func jsonWithoutStatusLineBecomesBody() async throws {
    let dir = try tempDir()
    let body = Data(#"{"a":1}"#.utf8)
    try body.write(to: dir.appendingPathComponent("plain.json"))
    let i = MapLocalInterceptor(rules: fileRule(dir.appendingPathComponent("plain.json").path))
    guard case .respond(let res) = await i.intercept(request("https://api.example.com/a"), context: Annotations().context) else {
        Issue.record("not respond"); return
    }
    #expect(res.status == 200 && res.body == body && res.header("Content-Type") == "application/json")
}

@Test(arguments: [
    ("api.example.com/build/v1/*", "w", "https://api.example.com/build/v1/js/main.js?v=3", "js/main.js"),
    ("api.example.com", "w", "https://api.example.com/build/v1/index.html", "build/v1/index.html"),
    (#"https:\/\/api\.example\.com\/build\/v1\/(.*)"#, "r", "https://api.example.com/build/v1/a/b.css", "a/b.css"),
])
func directoryRelativePath(pattern: String, mode: String, url: String, expected: String) {
    let r = MapLocalRule(match: MatchRule(url: pattern, mode: mode == "r" ? .regex : .wildcard), useLocalFile: false, useDirectory: true)
    #expect(r.match.matches(request(url)))
    #expect(r.relativePath(for: request(url)) == expected)
}

@Test func directoryRelativePathRejectsParentComponents() {
    let r = MapLocalRule(match: MatchRule(url: "api.example.com/static/*"), useLocalFile: false, useDirectory: true)
    #expect(r.relativePath(for: request("https://api.example.com/static/../secret")) == nil)
    #expect(r.relativePath(for: request("https://api.example.com/static/%2E%2E/secret")) == nil)
}

@Test func directoryServesFile() async throws {
    let dir = try tempDir()
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("js"), withIntermediateDirectories: true)
    try Data("x()".utf8).write(to: dir.appendingPathComponent("js/main.js"))
    let rule = MapLocalRule(name: "D", match: MatchRule(url: "api.example.com/build/*"), useLocalFile: false, useDirectory: true, directoryPath: dir.path)
    let i = MapLocalInterceptor(rules: RuleTree(nodes: [.rule(rule)]))

    let a = Annotations()
    guard case .respond(let res) = await i.intercept(request("https://api.example.com/build/js/main.js?v=3"), context: a.context) else {
        Issue.record("not respond"); return
    }
    #expect(res.status == 200 && res.body == Data("x()".utf8))
    #expect(a.all == [.tool("Map Local: D")])
}

@Test func directoryMissingFileFallsThrough() async throws {
    let rule = MapLocalRule(name: "D", match: MatchRule(url: "api.example.com/build/*"), useLocalFile: false, useDirectory: true, directoryPath: try tempDir().path)
    let i = MapLocalInterceptor(rules: RuleTree(nodes: [.rule(rule)]))
    let a = Annotations()
    let q = request("https://api.example.com/build/none.js")
    guard case .continue(let out) = await i.intercept(q, context: a.context) else { Issue.record("not continue"); return }
    #expect(out == q && a.all.isEmpty)
}

@Test func delayIsApplied() async throws {
    let dir = try tempDir()
    try Data("hi".utf8).write(to: dir.appendingPathComponent("a.txt"))
    let i = MapLocalInterceptor(rules: fileRule(dir.appendingPathComponent("a.txt").path, delay: 1))
    let start = ContinuousClock.now
    guard case .respond = await i.intercept(request("https://api.example.com/a"), context: Annotations().context) else {
        Issue.record("not respond"); return
    }
    #expect(ContinuousClock.now - start >= .seconds(1))
}
