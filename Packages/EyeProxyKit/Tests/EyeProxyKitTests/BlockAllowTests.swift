import EyeProxyCore
import Foundation
import Synchronization
import Testing
@testable import EyeProxyKit

private final class Annotations: Sendable {
    private let list = Mutex<[FlowAnnotation]>([])
    var all: [FlowAnnotation] { list.withLock { $0 } }
    var context: FlowContext {
        FlowContext(id: .init(), clientAddress: "127.0.0.1", clientPort: 5000) { a in self.list.withLock { $0.append(a) } }
    }
}

private func request(_ url: String) -> FlowRequest {
    let c = URLComponents(string: url)!
    return FlowRequest(method: "GET", scheme: c.scheme!, host: c.host!, port: c.port ?? 443,
                       path: c.percentEncodedPath, headers: [], body: Data())
}

private let connectCtx = ConnectContext(clientAddress: "127.0.0.1", clientPort: 5000)

private func block(_ rules: [BlockRule], app: String? = nil, calls: Counter = Counter()) -> BlockInterceptor {
    BlockInterceptor(rules: RuleTree(nodes: rules.map { .rule($0) })) { _, _ in
        calls.bump()
        return app
    }
}

private func runBlock(_ i: BlockInterceptor, _ url: String) async -> (dropped: Bool, ann: [FlowAnnotation]) {
    let a = Annotations()
    let d = await i.intercept(request(url), context: a.context)
    if case .drop = d { return (true, a.all) }
    return (false, a.all)
}

@Test func blockActionsOnRequest() async {
    let m = MatchRule(url: "https://ads.example.com/*")
    for (action, dropped, ann) in [(BlockAction.blockAndHide, true, [FlowAnnotation.hidden]),
                                   (.blockAndDisplay, true, [.tool("Blocked: R")]),
                                   (.hideOnly, false, [.hidden])] {
        let r = await runBlock(block([BlockRule(name: "R", match: m, action: action)]), "https://ads.example.com/x")
        #expect(r.dropped == dropped && r.ann == ann)
        #expect(r.ann.compactMap(ToolMark.mark) == (action == .blockAndDisplay ? [.blocked] : []))
    }
    #expect(await runBlock(block([BlockRule(match: m)]), "https://api.example.com/x") == (false, []))
}

@Test func hostOnlyRuleBlocksAtConnect() async {
    let i = block([BlockRule(match: MatchRule(url: "ads.example.com"), action: .blockAndHide)])
    #expect(await i.intercept(host: "ads.example.com", port: 443, context: connectCtx) == ConnectVerdict(action: .drop, record: false))
    #expect(await i.intercept(host: "api.example.com", port: 443, context: connectCtx) == ConnectVerdict())
    let display = block([BlockRule(name: "Ads", match: MatchRule(url: "*.example.com/*"), action: .blockAndDisplay)])
    let v = await display.intercept(host: "ADS.example.com", port: 443, context: connectCtx)
    #expect(v == ConnectVerdict(action: .drop, note: "Blocked: Ads"))
    #expect(ToolMark.mark(of: .tool(v.note ?? "")) == .blocked)
    let hide = block([BlockRule(match: MatchRule(url: "https://ads.example.com/"), action: .hideOnly)])
    #expect(await hide.intercept(host: "ads.example.com", port: 443, context: connectCtx) == ConnectVerdict(record: false))
}

@Test func pathRuleDefersAtConnect() async {
    let i = block([BlockRule(match: MatchRule(url: "api.example.com/ads/*"), action: .blockAndHide)])
    #expect(await i.intercept(host: "api.example.com", port: 443, context: connectCtx) == ConnectVerdict())
}

@Test func blockAppByPath() async {
    let rule = BlockRule(name: "Foo", match: MatchRule(), action: .blockAndDisplay, appPath: "/Applications/Foo.app")
    #expect(await runBlock(block([rule], app: "/Applications/Foo.app"), "https://api.example.com/").dropped)
    #expect(await runBlock(block([rule], app: "/Applications/Bar.app"), "https://api.example.com/").dropped == false)
    let i = block([rule], app: "/Applications/Foo.app")
    #expect(await i.intercept(host: "api.example.com", port: 443, context: connectCtx) == ConnectVerdict(action: .drop, note: "Blocked: Foo"))
    let both = BlockRule(match: MatchRule(url: "ads.example.com"), appPath: "/Applications/Foo.app")
    #expect(await runBlock(block([both], app: "/Applications/Foo.app"), "https://api.example.com/").dropped == false)
}

@Test func appLookupSkippedWithoutAppRules() async {
    let calls = Counter()
    let i = block([BlockRule(match: MatchRule(url: "ads.example.com"))], calls: calls)
    _ = await runBlock(i, "https://ads.example.com/")
    _ = await i.intercept(host: "ads.example.com", port: 443, context: connectCtx)
    #expect(calls.value == 0)
    let withApp = block([BlockRule(appPath: "/Applications/Foo.app")], calls: calls)
    _ = await runBlock(withApp, "https://ads.example.com/")
    #expect(calls.value == 1)
}

@Test func allowListUnrecordsNonMatching() async {
    let i = AllowInterceptor(rules: RuleTree(nodes: [.rule(AllowRule(match: MatchRule(url: "api.example.com/*")))]))
    let a = Annotations()
    _ = await i.intercept(request("https://other.example.com/x"), context: a.context)
    #expect(a.all == [.unrecorded])
    let b = Annotations()
    _ = await i.intercept(request("https://api.example.com/x"), context: b.context)
    #expect(b.all.isEmpty)
    #expect(await i.intercept(host: "other.example.com", port: 443, context: connectCtx) == ConnectVerdict(action: .tunnel, record: false))
    #expect(await i.intercept(host: "api.example.com", port: 443, context: connectCtx) == ConnectVerdict())
}

@Test func emptyAllowListHasNoEffect() async {
    let i = AllowInterceptor(rules: RuleTree())
    #expect(await i.intercept(host: "a.example.com", port: 443, context: connectCtx) == ConnectVerdict())
    let a = Annotations()
    _ = await i.intercept(request("https://a.example.com/"), context: a.context)
    #expect(a.all.isEmpty)
}

@Test func proxymanCodingRoundTrip() throws {
    let r = BlockRule(id: "ABCD1234", name: "N", match: MatchRule(url: "x.example.com"), action: .hideOnly, appPath: "/Applications/Foo.app")
    #expect(try JSONDecoder().decode(BlockRule.self, from: JSONEncoder().encode(r)) == r)
    let a = AllowRule(id: "ABCD1234", match: MatchRule(url: "x.example.com"))
    #expect(try JSONDecoder().decode(AllowRule.self, from: JSONEncoder().encode(a)) == a)
    #expect(RuleFile<BlockRule>.blockList.name == "block-list.json" && RuleFile<AllowRule>.allowList.name == "allow-list.json")
}

@Test func allowRulesWithoutHostPatternStillDecryptAtConnect() async {
    for url in ["https://api\\.example\\.com/.*", "*", "https://*/x"] {
        let mode: MatchMode = url.contains("\\.") ? .regex : .wildcard
        let i = AllowInterceptor(rules: RuleTree(nodes: [.rule(AllowRule(match: MatchRule(url: url, mode: mode)))]))
        #expect(await i.intercept(host: "api.example.com", port: 443, context: connectCtx) == ConnectVerdict())
    }
    let http = AllowInterceptor(rules: RuleTree(nodes: [.rule(AllowRule(match: MatchRule(url: "http://api.example.com/*")))]))
    #expect(await http.intercept(host: "api.example.com", port: 443, context: connectCtx) == ConnectVerdict(action: .tunnel, record: false))
}
