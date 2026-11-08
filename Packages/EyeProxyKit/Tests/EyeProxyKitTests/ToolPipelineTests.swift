import EyeProxyCore
import Foundation
import NIOCore
import NIOPosix
import Synchronization
import Testing
@testable import EyeProxyKit

private func tree<R: ToolRule>(_ rules: R...) -> RuleTree<R> { RuleTree(nodes: rules.map { .rule($0) }) }

private func typeNames(_ list: [Any]) -> [String] { list.map { String(describing: type(of: $0)) } }

private let noApp: AppPathLookup = { _, _ in nil }

private func allSwitches(_ on: Bool) -> ToolSwitches {
    var s = ToolSwitches()
    (s.breakpoint, s.mapLocal, s.mapRemote, s.blockList, s.allowList, s.networkConditions, s.noCaching) = (on, on, on, on, on, on, on)
    return s
}

private let ncRule = NetworkConditionRule(id: "n", name: "N", url: "x.example.com", isEnabled: true,
                                          networkProfile: NetworkProfile(name: "T", downloadBandwidth: 0, uploadBandwidth: 0))

private func request(_ url: String) -> FlowRequest {
    let c = URLComponents(string: url)!
    return FlowRequest(method: "GET", scheme: c.scheme!, host: c.host!, port: c.port ?? (c.scheme == "http" ? 80 : 443),
                       path: c.percentEncodedPath, headers: [], body: Data())
}

private let connectCtx = ConnectContext(clientAddress: "127.0.0.1", clientPort: nil)

private final class AnnotationLog: Sendable {
    private let list = Mutex<[FlowAnnotation]>([])
    var all: [FlowAnnotation] { list.withLock { $0 } }
    var context: FlowContext { FlowContext(id: .init(), clientAddress: "127.0.0.1") { a in self.list.withLock { $0.append(a) } } }
}

@MainActor private func waitPending(_ center: BreakpointCenter, _ count: Int) async -> Int {
    for _ in 0..<200 where center.pending.count != count { try? await Task.sleep(for: .milliseconds(10)) }
    return center.pending.count
}

@Suite(.timeLimit(.minutes(1)))
struct ToolPipelineTests {
    @Test @MainActor func chainOrderFollowsSpec() throws {
        let base: [any RequestInterceptor] = [CAProfileResponder(certificateAuthority: try CertificateAuthority.generate())]
        let rules = RuleSet(networkConditions: [ncRule])
        let chain = ToolPipeline.chain(rules: rules, switches: allSwitches(true), sslPolicy: SSLProxyingPolicy(), breakpoints: BreakpointCenter(), appPath: noApp, base: base)
        #expect(typeNames(chain.request) == ["CAProfileResponder", "AllowInterceptor", "BlockInterceptor", "NoCachingInterceptor",
                                             "MapRemoteInterceptor", "MapLocalInterceptor", "BreakpointInterceptor",
                                             "NetworkConditionsInterceptor"])
        #expect(typeNames(chain.response) == ["NoCachingInterceptor", "BreakpointInterceptor", "NetworkConditionsInterceptor"])
        #expect(typeNames(chain.connect) == ["AllowInterceptor", "BlockInterceptor", "AutoDecryptInterceptor", "NetworkConditionsInterceptor"])
    }

    @Test @MainActor func disabledToolsAreAbsent() throws {
        let base: [any RequestInterceptor] = [CAProfileResponder(certificateAuthority: try CertificateAuthority.generate())]
        let chain = ToolPipeline.chain(rules: RuleSet(networkConditions: [ncRule]), switches: allSwitches(false), sslPolicy: SSLProxyingPolicy(),
                                       breakpoints: BreakpointCenter(), appPath: noApp, base: base)
        #expect(typeNames(chain.request) == ["CAProfileResponder"])
        #expect(chain.response.isEmpty)
        #expect(typeNames(chain.connect) == ["AutoDecryptInterceptor"])
    }

    @Test @MainActor func networkConditionsNeedsEnabledRule() {
        var off = ncRule
        off.isEnabled = false
        let chain = ToolPipeline.chain(rules: RuleSet(networkConditions: [off]), switches: allSwitches(true), sslPolicy: SSLProxyingPolicy(),
                                       breakpoints: BreakpointCenter(), appPath: noApp, base: [])
        #expect(!typeNames(chain.request).contains("NetworkConditionsInterceptor"))
        #expect(!typeNames(chain.connect).contains("NetworkConditionsInterceptor"))
    }

    @Test func autoDecryptHostsSkipRegexAndWildcardOnly() {
        let rules = RuleSet(mapLocal: tree(
            MapLocalRule(name: "R", match: MatchRule(url: "https://api.example.com/x")),
            MapLocalRule(name: "Re", match: MatchRule(url: #"https://re\.example\.com/.*"#, mode: .regex)),
            MapLocalRule(name: "W", match: MatchRule(url: "https://*/x")),
            MapLocalRule(name: "Off", isEnabled: false, match: MatchRule(url: "https://off.example.com/x"))))
        var s = ToolSwitches()
        s.mapLocal = true
        let hosts = ToolPipeline.autoDecryptHosts(rules: rules, switches: s)
        #expect(hosts.map(\.pattern) == ["api.example.com"] && hosts.map(\.ruleName) == ["R"])
    }

    @Test func autoDecryptRespectsSwitches() {
        let rules = RuleSet(mapLocal: tree(MapLocalRule(name: "R", match: MatchRule(url: "https://api.example.com/x"))))
        #expect(ToolPipeline.autoDecryptHosts(rules: rules, switches: ToolSwitches()).isEmpty)
    }

    @Test func autoDecryptBlockAllowOnlyPathRules() {
        let rules = RuleSet(
            mapRemote: tree(MapRemoteRule(name: "M", match: MatchRule(url: "https://*.remote.com"))),
            breakpoint: tree(BreakpointRule(name: "B", match: MatchRule(url: "bp.example.com/a"))),
            block: tree(BlockRule(name: "HostOnly", match: MatchRule(url: "blockhost.com")),
                        BlockRule(name: "Path", match: MatchRule(url: "https://block.com/ads/*"))),
            allow: tree(AllowRule(name: "AHost", match: MatchRule(url: "allowhost.com/*")),
                        AllowRule(name: "APath", match: MatchRule(url: "allow.com/api"))))
        let hosts = ToolPipeline.autoDecryptHosts(rules: rules, switches: allSwitches(true))
        #expect(Set(hosts.map(\.pattern)) == ["bp.example.com", "*.remote.com", "block.com", "allow.com"])
    }

    @Test func autoDecryptInterceptorDecryptsMatchingHosts() async {
        let i = ToolPipeline.AutoDecryptInterceptor(hosts: [("*.example.com", "R")], sslPolicy: SSLProxyingPolicy())
        #expect(await i.intercept(host: "API.example.com", port: 443, context: connectCtx)
                == ConnectVerdict(action: .decrypt, note: "자동 복호화(규칙: R)"))
        #expect(await i.intercept(host: "other.com", port: 443, context: connectCtx) == ConnectVerdict())
    }

    /// SSL Proxying 전체 스위치가 꺼지면 규칙 호스트도 복호화하지 않는다.
    @Test @MainActor func autoDecryptOffWhenSSLProxyingDisabled() async {
        let rules = RuleSet(mapLocal: tree(MapLocalRule(name: "R", match: MatchRule(url: "https://api.example.com/x"))))
        var s = ToolSwitches()
        s.mapLocal = true
        let chain = ToolPipeline.chain(rules: rules, switches: s, sslPolicy: SSLProxyingPolicy(isEnabled: false),
                                       breakpoints: BreakpointCenter(), appPath: noApp, base: [])
        #expect(await chain.runConnect(host: "api.example.com", port: 443, context: connectCtx) == ConnectVerdict())
    }

    /// SSL Proxying 목록이 이미 복호화하는 호스트에는 자동 복호화 메모를 달지 않는다.
    @Test func autoDecryptSkipsHostsAlreadyInSSLList() async {
        let i = ToolPipeline.AutoDecryptInterceptor(hosts: [("*.example.com", "R")],
                                                    sslPolicy: SSLProxyingPolicy(patterns: ["api.example.com"]))
        #expect(await i.intercept(host: "api.example.com", port: 443, context: connectCtx) == ConnectVerdict())
        #expect(await i.intercept(host: "img.example.com", port: 443, context: connectCtx)
                == ConnectVerdict(action: .decrypt, note: "자동 복호화(규칙: R)"))
    }

    @Test @MainActor func mapRemoteThenMapLocalMatchesNewURL() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-\(UUID().uuidString).txt")
        try Data("local".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let rules = RuleSet(
            mapLocal: tree(MapLocalRule(name: "L", match: MatchRule(url: "https://b.example.com/*"),
                                        localFile: LocalFileRef(name: "x", path: file.path))),
            mapRemote: tree(MapRemoteRule(name: "R", match: MatchRule(url: "https://a.example.com", includeSubpaths: true),
                                          mapTo: MapTarget(host: "b.example.com"))))
        var s = ToolSwitches()
        (s.mapRemote, s.mapLocal) = (true, true)
        let chain = ToolPipeline.chain(rules: rules, switches: s, sslPolicy: SSLProxyingPolicy(), breakpoints: BreakpointCenter(), appPath: noApp, base: [])
        let (decision, _) = await chain.runRequest(request("https://a.example.com/v1"), context: FlowContext(id: .init(), clientAddress: "127.0.0.1"))
        guard case .respond(let r) = decision else { Issue.record("Map Local 응답이 아님: \(decision)"); return }
        #expect(r.body == Data("local".utf8))
    }

    @Test @MainActor func ruleStoreRuleSetReadsAllTrees() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ruleset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RuleStore(directory: dir)
        store.set(tree(BlockRule(name: "B", match: MatchRule(url: "x.com"))), for: .blockList)
        store.networkConditions = [ncRule]
        let set = store.ruleSet
        #expect(set.block.enabledRules.map(\.name) == ["B"] && set.networkConditions == [ncRule] && set.mapLocal.nodes.isEmpty)
    }
}

// MARK: - SessionStore · FlowFilter

@Test @MainActor func unrecordedAnnotationRemovesFlow() {
    let s = SessionStore()
    let a = Flow.fixture(client: "1", decrypted: false), b = Flow.fixture(client: "2", decrypted: false), c = Flow.fixture(client: "3", decrypted: false)
    for f in [a, b, c] { s.apply(.requestStarted(f)) }
    s.apply(.annotated(id: b.id, .unrecorded))
    #expect(s.flows.map(\.id) == [a.id, c.id])
    #expect(s.number(b.id) == nil && s.flow(b.id) == nil)
    #expect(s.number(a.id) == 1 && s.number(c.id) == 2 && s.flow(c.id)?.clientAddress == "3")
    // 뒤따르는 이벤트는 남은 흐름에 정확히 반영된다.
    s.apply(.responseReceived(id: c.id, response: .init(status: 204, reason: "", headers: [], body: Data()), completedAt: .now))
    #expect(s.flows[1].response?.status == 204)
    let d = Flow.fixture(client: "4", decrypted: false)
    s.apply(.requestStarted(d))
    #expect(s.number(d.id) == 3)
    s.apply(.annotated(id: b.id, .hidden))   // 이미 지운 흐름: 무시
    #expect(s.flows.count == 3)
}

@Test @MainActor func requestSentReplacesStoredRequest() {
    let s = SessionStore(); let f = Flow.fixture(client: "1", decrypted: false)
    s.apply(.requestStarted(f))
    var sent = f.request
    (sent.host, sent.path) = ("b.example.com", "/v2")
    sent.headers = [HTTPHeader(name: "X", value: "1")]
    s.apply(.requestSent(id: f.id, request: sent))
    #expect(s.flows[0].request == sent)
}

/// `.sentURL`(Preserve the Original URL)이면 표시 URL은 두고 헤더·본문만 바꾸며, 주석을 최종 URL로 고친다.
@Test @MainActor func requestSentKeepsURLWhenSentURLAnnotated() {
    let s = SessionStore(); let f = Flow.fixture(client: "1", decrypted: false)
    s.apply(.requestStarted(f))
    s.apply(.annotated(id: f.id, .sentURL("https://b.example.com/v1")))
    var sent = f.request
    (sent.host, sent.path, sent.body) = ("c.example.com", "/v2", Data("x".utf8))
    s.apply(.requestSent(id: f.id, request: sent))
    #expect(s.flows[0].request.url == f.request.url && s.flows[0].request.body == Data("x".utf8))
    #expect(s.flows[0].annotations == [.sentURL("https://c.example.com/v2")])
}

/// Allow 비일치 요청은 체인에서 바로 `.passthrough`로 나오고 다른 도구 주석·멈춤이 없다.
@Test @MainActor func allowNonMatchPassesThroughChainUntouched() async throws {
    let all = "https://a.example.com/*"
    let rules = RuleSet(
        mapLocal: tree(MapLocalRule(name: "L", match: MatchRule(url: all), localFile: LocalFileRef(name: "x", path: "/dev/null"))),
        mapRemote: tree(MapRemoteRule(name: "R", match: MatchRule(url: all), mapTo: MapTarget(host: "b.example.com"))),
        breakpoint: tree(BreakpointRule(name: "B", match: MatchRule(url: all))),
        allow: tree(AllowRule(name: "A", match: MatchRule(url: "https://a.example.com/v1/*"))))
    let center = BreakpointCenter()
    let chain = ToolPipeline.chain(rules: rules, switches: allSwitches(true), sslPolicy: SSLProxyingPolicy(), breakpoints: center, appPath: noApp, base: [])
    let notes = AnnotationLog()
    let req = request("https://a.example.com/v2/x")
    let (decision, _) = await chain.runRequest(req, context: notes.context)
    guard case .passthrough(let r) = decision else { Issue.record("not passthrough: \(decision)"); return }
    #expect(r == req && notes.all == [.unrecorded] && center.pending.isEmpty)
}

@Test @MainActor func duplicateAnnotationsAreSkipped() {
    let s = SessionStore(); let f = Flow.fixture(client: "1", decrypted: false)
    s.apply(.requestStarted(f))
    s.apply(.annotated(id: f.id, .hidden)); s.apply(.annotated(id: f.id, .hidden)); s.apply(.annotated(id: f.id, .tool("A")))
    #expect(s.flows[0].annotations == [.hidden, .tool("A")])
}

@Test func hiddenFlowsFilteredByDefault() {
    var f = Flow.fixture(client: "1", decrypted: false)
    #expect(FlowFilter().matches(f))
    f.annotations = [.hidden]
    #expect(!FlowFilter().matches(f))
    var all = FlowFilter()
    all.includeHidden = true
    #expect(all.matches(f))
}

@Test func annotationLabelsForHeader() {
    var f = Flow.fixture(client: "1", decrypted: false)
    f.annotations = [.hidden, .tool("Map Remote: R"), .originalURL("https://a.com/x"), .unrecorded]
    #expect(f.annotationLabels == ["Map Remote: R", "원래 URL: https://a.com/x"])
}

// MARK: - ProxyServer 통합

private func loopbackServer(_ chain: InterceptorChain, host: String = "127.0.0.1") async throws -> (ProxyServer, Int) {
    let server = ProxyServer(configuration: .init(bindHost: host, port: 0), certificateAuthority: try CertificateAuthority.generate(),
                             interceptors: chain)
    return (server, try await server.start())
}

/// 루프백이 아닌 이 Mac의 IPv4 주소(없으면 nil).
private let lanAddress: String? = (try? System.enumerateDevices())?
    .compactMap { $0.address?.ipAddress }
    .first { !$0.hasPrefix("127.") && !$0.contains(":") }

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ToolPipelineServerTests {
    private func mapRemoteChain(to port: Int) async -> InterceptorChain {
        let rules = RuleSet(mapRemote: tree(MapRemoteRule(name: "R", match: MatchRule(url: "http://remote.example.test", includeSubpaths: true),
                                                          mapTo: MapTarget(scheme: "http", host: "127.0.0.1", port: port))))
        var s = ToolSwitches()
        s.mapRemote = true
        return await ToolPipeline.chain(rules: rules, switches: s, sslPolicy: SSLProxyingPolicy(), breakpoints: BreakpointCenter(), appPath: noApp, base: [])
    }

    @Test func mapRemoteRewriteReachesOrigin() async throws {
        let origin = TestOrigin { r in FlowResponse(status: 200, reason: "OK", headers: [], body: Data("origin \(r.path)".utf8)) }
        let originPort = try await origin.start()
        let (server, port) = try await loopbackServer(await mapRemoteChain(to: originPort))
        let (status, body) = try await fetch("http://remote.example.test/x", proxyHost: "127.0.0.1", proxyPort: port)
        #expect(status == 200 && String(decoding: body, as: UTF8.self) == "origin /x")
        await server.stop()
        await origin.stop()
    }

    /// LAN 클라이언트는 Map Remote로 바뀐 루프백 목적지에 닿지 못한다(§5.3 보안).
    @Test(.enabled(if: lanAddress != nil)) func mapRemoteToLoopbackBlockedForLANClient() async throws {
        let hits = Counter()
        let origin = TestOrigin { _ in hits.bump(); return FlowResponse(status: 200, reason: "OK", headers: [], body: Data()) }
        let originPort = try await origin.start()
        let lan = try #require(lanAddress)
        let (server, port) = try await loopbackServer(await mapRemoteChain(to: originPort), host: lan)
        let (status, _) = try await fetch("http://remote.example.test/x", proxyHost: lan, proxyPort: port)
        #expect(status == 403 && hits.value == 0)
        await server.stop()
        await origin.stop()
    }

    /// 원본 서버가 받은 경로·Host·Pragma를 본문으로 돌려준다(ETag 응답 헤더 포함).
    private func echoOrigin() -> TestOrigin {
        TestOrigin { r in
            FlowResponse(status: 200, reason: "OK", headers: [HTTPHeader(name: "ETag", value: "e1")],
                         body: Data("origin \(r.path) host=\(r.header("Host") ?? "-") pragma=\(r.header("Pragma") ?? "-")".utf8))
        }
    }

    /// §4.5 1단계·§5.5: Allow 규칙에 안 맞는 요청은 다른 도구가 손대지 않고 원본에 그대로 간다(응답 체인도 건너뜀).
    @Test @MainActor func allowNonMatchIsNotTouchedByOtherTools() async throws {
        let origin = echoOrigin()
        let op = try await origin.start()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("allow-\(UUID().uuidString).txt")
        try Data("local".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let all = "http://127.0.0.1:\(op)/*"
        let rules = RuleSet(
            mapLocal: tree(MapLocalRule(name: "L", match: MatchRule(url: all), localFile: LocalFileRef(name: "x", path: file.path))),
            mapRemote: tree(MapRemoteRule(name: "R", match: MatchRule(url: all), mapTo: MapTarget(path: "/mapped"))),
            breakpoint: tree(BreakpointRule(name: "B", match: MatchRule(url: all))),
            allow: tree(AllowRule(name: "A", match: MatchRule(url: "http://127.0.0.1:\(op)/v1/*"))))
        var s = ToolSwitches()
        (s.allowList, s.mapLocal, s.mapRemote, s.breakpoint, s.noCaching) = (true, true, true, true, true)
        let center = BreakpointCenter()
        let (server, port) = try await loopbackServer(ToolPipeline.chain(rules: rules, switches: s, sslPolicy: SSLProxyingPolicy(),
                                                                         breakpoints: center, appPath: noApp, base: []))
        let (status, headers, body) = try await fetchWithHeaders("http://127.0.0.1:\(op)/v2/x", proxyPort: port)
        #expect(status == 200 && body == "origin /v2/x host=127.0.0.1:\(op) pragma=-")
        #expect(headers["etag"] == "e1" && headers["expires"] == nil)
        #expect(center.pending.isEmpty)
        await server.stop()
        await origin.stop()
    }

    /// 프록시를 거친 요청의 이벤트를 SessionStore에 반영해 응답까지 기다린다.
    @MainActor private func recordOne(_ chain: InterceptorChain, url: String) async throws -> (Flow, String) {
        let (server, port) = try await loopbackServer(chain)
        let session = SessionStore()
        let consumer = Task { @MainActor in
            for await e in server.events {
                session.apply(e)
                if case .responseReceived = e { return }
            }
        }
        let (_, _, body) = try await fetchWithHeaders(url, proxyPort: port)
        await consumer.value
        await server.stop()
        return (try #require(session.flows.first), body)
    }

    private func preserveChain(to port: Int, originalURL: Bool = false, hostHeader: Bool = false) async -> InterceptorChain {
        let rules = RuleSet(mapRemote: tree(MapRemoteRule(name: "R", match: MatchRule(url: "http://remote.example.test", includeSubpaths: true),
                                                          mapTo: MapTarget(scheme: "http", host: "127.0.0.1", port: port),
                                                          preserveHostHeader: hostHeader, preserveOriginalURL: originalURL)))
        var s = ToolSwitches()
        s.mapRemote = true
        return await ToolPipeline.chain(rules: rules, switches: s, sslPolicy: SSLProxyingPolicy(), breakpoints: BreakpointCenter(), appPath: noApp, base: [])
    }

    /// §5.3: Preserve the Original URL 끔 → 기록된 요청은 실제로 보낸 것, 상세에 원래 URL.
    @Test @MainActor func mapRemoteRecordsSentRequest() async throws {
        let origin = echoOrigin()
        let op = try await origin.start()
        let (flow, _) = try await recordOne(await preserveChain(to: op), url: "http://remote.example.test/x")
        #expect(flow.request.url == "http://127.0.0.1:\(op)/x")
        #expect(flow.annotationLabels == ["Map Remote: R", "원래 URL: http://remote.example.test/x"])
        await origin.stop()
    }

    /// §5.3: Preserve the Original URL 켬 → 목록·상세는 원래 URL, 상세에 실제 전송 URL도.
    @Test @MainActor func mapRemotePreserveOriginalURLKeepsDisplayedURL() async throws {
        let origin = echoOrigin()
        let op = try await origin.start()
        let (flow, _) = try await recordOne(await preserveChain(to: op, originalURL: true), url: "http://remote.example.test/x")
        #expect(flow.request.url == "http://remote.example.test/x")
        #expect(flow.annotationLabels == ["Map Remote: R", "실제 전송 URL: http://127.0.0.1:\(op)/x"])
        await origin.stop()
    }

    /// §5.3·§8: Preserve Host Header 두 경우를 원본 서버가 받은 Host로 확인한다.
    @Test @MainActor func mapRemoteHostHeaderBothStates() async throws {
        let origin = echoOrigin()
        let op = try await origin.start()
        let (_, rewritten) = try await recordOne(await preserveChain(to: op), url: "http://remote.example.test/x")
        #expect(rewritten == "origin /x host=127.0.0.1:\(op) pragma=-")
        let (_, preserved) = try await recordOne(await preserveChain(to: op, hostHeader: true), url: "http://remote.example.test/x")
        #expect(preserved == "origin /x host=remote.example.test pragma=-")
        await origin.stop()
    }

    @Test @MainActor func breakpointReleasedWhenClientDisconnects() async throws {
        let origin = TestOrigin { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data()) }
        let originPort = try await origin.start()
        let center = BreakpointCenter()
        var s = ToolSwitches()
        s.breakpoint = true
        let rules = RuleSet(breakpoint: tree(BreakpointRule(name: "BP", match: MatchRule(url: "http://127.0.0.1:\(originPort)/*"))))
        let (server, port) = try await loopbackServer(ToolPipeline.chain(rules: rules, switches: s, sslPolicy: SSLProxyingPolicy(), breakpoints: center, appPath: noApp, base: []))
        let client = try await rawConnect(port: port, sending: "GET http://127.0.0.1:\(originPort)/bp HTTP/1.1\r\nHost: 127.0.0.1:\(originPort)\r\n\r\n")
        #expect(await waitPending(center, 1) == 1)
        try await client.close()
        #expect(await waitPending(center, 0) == 0)
        await server.stop()
        await origin.stop()
    }
}
