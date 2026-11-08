import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

/// 테스트 전용 규칙: 공통 필드 + 임의 필드 `note`를 Proxyman 키로 코딩한다.
private struct TestRule: ToolRule {
    var id: String
    var name: String = ""
    var isEnabled: Bool = true
    var match = MatchRule(url: "https://api.example.com/*")
    var note: String?

    init(id: String, isEnabled: Bool = true, note: String? = nil) {
        self.id = id
        self.isEnabled = isEnabled
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ProxymanKey.self)
        id = try c.decode(String.self, forKey: "id")
        name = try c.decode(String.self, forKey: "name")
        isEnabled = try c.decode(Bool.self, forKey: "isEnabled")
        match = try MatchRule(proxymanFields: c)
        note = try c.decodeIfPresent(String.self, forKey: "note")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ProxymanKey.self)
        try c.encode(id, forKey: "id")
        try c.encode(name, forKey: "name")
        try c.encode(isEnabled, forKey: "isEnabled")
        try match.encode(proxymanFields: &c)
        try c.encodeIfPresent(note, forKey: "note")
    }
}

private typealias Tree = RuleTree<TestRule>

/// 실제 Proxyman 6.3.0 Map Local 노드(모든 키).
private let proxymanNode = """
{"nodeType":{"node":{"_0":{"id":"19A8BA07","name":"search","isEnabled":true,"url":"https://api.example.com/v1/search?*","regex":"useWildcard","method":{"exact":[{"name":"GET"}]},"isIncludingPaths":false,"graphQLQueryName":null,"isLocalFileEnable":true,"localFile":{"name":"default_message","path":"/abs/path.json"},"isDirectoryFileEnable":false,"directoryFile":null,"advanceSettings":{"delayTimePreset":10}}}}}
"""

private func ruleNode(_ id: String, regex: String = "useWildcard", method: String = #"{"any":{}}"#, extra: String = "") -> String {
    #"{"nodeType":{"node":{"_0":{"id":"\#(id)","name":"\#(id)","isEnabled":true,"url":"https://api.example.com/\#(id)","regex":"\#(regex)","method":\#(method)\#(extra)}}}}"#
}

private func decode(_ json: String) throws -> (tree: Tree, skipped: Int) {
    try Tree.decodeLenient(Data(json.utf8))
}

private func request(_ url: String) -> FlowRequest {
    let c = URLComponents(string: url)!
    return FlowRequest(method: "GET", scheme: c.scheme!, host: c.host!, port: 443, path: c.percentEncodedPath, headers: [], body: Data())
}

@Test func decodesDiskFormatAndExportFormat() throws {
    let nodes = "\(proxymanNode),\(ruleNode("B"))"
    let disk = try decode(#"{"nodes":[\#(nodes)]}"#)
    let export = try decode("[\(nodes)]")
    #expect(disk.tree == export.tree)
    #expect(disk.skipped == 0 && export.skipped == 0)
    #expect(disk.tree.enabledRules.map(\.id) == ["19A8BA07", "B"])
    let first = try #require(disk.tree.enabledRules.first)
    #expect(first.match == MatchRule(url: "https://api.example.com/v1/search?*", methods: .exact(["GET"]), queryMode: .exact))
}

@Test func skipsUnknownNodeKindsAndBrokenNodes() throws {
    let weird = #"{"nodeType":{"weird":{"_0":{"id":"W"}}}}"#
    let noURL = #"{"nodeType":{"node":{"_0":{"id":"X","name":"X","isEnabled":true}}}}"#
    let result = try decode("[\(ruleNode("A")),\(weird),\(noURL)]")
    #expect(result.tree.enabledRules.map(\.id) == ["A"])
    #expect(result.tree.nodes.count == 1)
    #expect(result.skipped == 2)
}

@Test func skipsBrokenNodesInsideFoldersAndBrokenFolders() throws {
    let noURL = #"{"nodeType":{"node":{"_0":{"id":"X","name":"X","isEnabled":true}}}}"#
    let folder = #"{"nodeType":{"folder":{"_0":{"id":"F","name":"F","isEnabled":true,"children":[\#(ruleNode("A")),\#(noURL),5]}}}}"#
    let brokenFolder = #"{"nodeType":{"folder":{"_0":{"id":"G","children":[\#(ruleNode("B")),\#(noURL)]}}}}"#
    let result = try decode("[\(folder),\(brokenFolder),\(ruleNode("C"))]")
    #expect(result.tree.enabledRules.map(\.id) == ["A", "C"])
    #expect(result.skipped == 3)
}

@Test func nonJSONThrows() {
    #expect(throws: (any Error).self) { try decode("hello") }
}

@Test func firstMatchSkipsDisabledAndDisabledFolders() {
    let tree = Tree(nodes: [
        .rule(TestRule(id: "R1", isEnabled: false)),
        .folder(RuleFolder(id: "F", name: "F", isEnabled: false, children: [.rule(TestRule(id: "R2"))])),
        .rule(TestRule(id: "R3")),
        .rule(TestRule(id: "R4")),
    ])
    #expect(tree.firstMatch(request("https://api.example.com/x"))?.id == "R3")
    #expect(tree.firstMatch(request("https://other.example.com/x")) == nil)
}

@Test func folderOrderIsDepthFirst() {
    let tree = Tree(nodes: [
        .folder(RuleFolder(id: "F", name: "F", isEnabled: true, children: [.rule(TestRule(id: "A")), .rule(TestRule(id: "B"))])),
        .rule(TestRule(id: "C")),
    ])
    #expect(tree.enabledRules.map(\.id) == ["A", "B", "C"])
    #expect(tree.firstMatch(request("https://api.example.com/x"))?.id == "A")
}

@Test func ignoreQueryDefaultsFalseWhenAbsentAndRoundTrips() throws {
    var tree = try decode("[\(ruleNode("A"))]").tree
    #expect(tree.enabledRules.first?.match.queryMode == .exact)

    guard case .rule(var rule) = tree.nodes[0] else { Issue.record("not a rule"); return }
    rule.match.queryMode = .ignore
    rule.note = "hi"
    tree.nodes[0] = .rule(rule)
    let data = try tree.encoded()
    #expect(String(decoding: data, as: UTF8.self).contains(#""eyeproxy":{"ignoreQuery":true,"queryMode":"ignore"}"#))
    let again = try Tree.decodeLenient(data)
    #expect(again.tree == tree)
    #expect(again.skipped == 0)
    #expect(again.tree.enabledRules.first?.match.queryMode == .ignore)
}

@Test func codecRoundTripAndLegacy() throws {
    var tree = try decode("[\(ruleNode("A"))]").tree
    guard case .rule(var rule) = tree.nodes[0] else { Issue.record("not a rule"); return }
    rule.match.queryMode = .selected
    rule.match.queryConditions = [
        QueryCondition(key: "screenCode", value: "CSSD1400", isEnabled: true),
        QueryCondition(key: "page", value: "*", isEnabled: false),
    ]
    tree.nodes[0] = .rule(rule)
    let data = try tree.encoded()
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains(#""eyeproxy":{"ignoreQuery":false,"queryItems":[{"isEnabled":true,"key":"screenCode","value":"CSSD1400"},{"isEnabled":false,"key":"page","value":"*"}],"queryMode":"selected"}"#))
    let again = try Tree.decodeLenient(data).tree
    #expect(again == tree)
    #expect(again.enabledRules.first?.match.queryConditions.map(\.key) == ["screenCode", "page"])

    // .exact는 ignoreQuery false, 조건은 쓰지 않는다.
    rule.match.queryMode = .exact
    tree.nodes[0] = .rule(rule)
    let exactText = String(decoding: try tree.encoded(), as: UTF8.self)
    #expect(exactText.contains(#""eyeproxy":{"ignoreQuery":false,"queryMode":"exact"}"#))

    // 구버전: ignoreQuery만 있는 파일, eyeproxy 없는 파일(Proxyman).
    let legacyOn = try decode("[\(ruleNode("B", extra: #","eyeproxy":{"ignoreQuery":true}"#))]").tree
    let legacyOff = try decode("[\(ruleNode("C", extra: #","eyeproxy":{"ignoreQuery":false}"#))]").tree
    let proxyman = try decode("[\(ruleNode("D"))]").tree
    #expect(legacyOn.enabledRules.first?.match.queryMode == .ignore)
    #expect(legacyOff.enabledRules.first?.match.queryMode == .exact)
    #expect(proxyman.enabledRules.first?.match.queryMode == .exact)
}

@Test func methodAndRegexFieldsRoundTrip() throws {
    let nodes = [
        ruleNode("ANY"),
        ruleNode("EX", method: #"{"exact":[{"name":"GET"},{"name":"POST"}]}"#),
        ruleNode("RE", regex: "useRegex"),
        ruleNode("FOO", regex: "useFoo", extra: #","isIncludingPaths":true,"graphQLQueryName":"Search""#),
    ]
    let tree = try decode("[\(nodes.joined(separator: ","))]").tree
    let m = tree.enabledRules.map(\.match)
    #expect(m.map(\.methods) == [.any, .exact(["GET", "POST"]), .any, .any])
    #expect(m.map(\.mode) == [.wildcard, .wildcard, .regex, .wildcard])
    #expect(m[3].includeSubpaths && m[3].graphQLQueryName == "Search")

    let export = try tree.encodedAsProxymanExport()
    let text = String(decoding: export, as: UTF8.self)
    #expect(text.hasPrefix(#"[{"nodeType":{"node":{"_0":{"#))
    #expect(text.contains(#""method":{"any":{}}"#) && text.contains(#""graphQLQueryName":null"#))
    let again = try Tree.decodeLenient(export)
    #expect(again.tree == tree)
    #expect(again.skipped == 0)
    let disk = try Tree.decodeLenient(try tree.encoded())
    #expect(disk.tree == tree)
}
