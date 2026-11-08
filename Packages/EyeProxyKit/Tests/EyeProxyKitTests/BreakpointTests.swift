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

private let original = FlowRequest(method: "GET", scheme: "https", host: "api.example.com", port: 443,
                                   path: "/v1/items?x=1", headers: [HTTPHeader(name: "A", value: "1")], body: Data("b".utf8))
private let originalResponse = FlowResponse(status: 200, reason: "OK", headers: [HTTPHeader(name: "R", value: "1")], body: Data("r".utf8))

private func interceptor(_ rules: [BreakpointRule], _ center: BreakpointCenter) -> BreakpointInterceptor {
    BreakpointInterceptor(rules: RuleTree(nodes: rules.map { .rule($0) }), center: center)
}

private func rule(request: Bool = true, response: Bool = false, url: String = "https://api.example.com/*") -> BreakpointRule {
    BreakpointRule(name: "BP", match: MatchRule(url: url), onRequest: request, onResponse: response)
}

/// 최대 2초 동안 `pending`이 `count`개가 되기를 기다린다.
@MainActor private func waitPending(_ center: BreakpointCenter, _ count: Int) async -> [PausedItem] {
    for _ in 0..<200 where center.pending.count < count {
        try? await Task.sleep(for: .milliseconds(10))
    }
    return center.pending
}

private func continued(_ d: RequestDecision) -> FlowRequest? {
    if case .continue(let r) = d { return r }
    return nil
}

private func responded(_ d: RequestDecision) -> FlowResponse? {
    if case .respond(let r) = d { return r }
    return nil
}

private func continued(_ d: ResponseDecision) -> FlowResponse? {
    if case .continue(let r) = d { return r }
    return nil
}

@Suite(.timeLimit(.minutes(1)))
@MainActor struct BreakpointTests {
    @Test func pauseWaitsForResolve() async throws {
        let center = BreakpointCenter()
        let bp = interceptor([rule()], center)
        let a = Annotations()
        let ctx = a.context
        let task = Task { await bp.intercept(original, context: ctx) }
        let item = try #require(await waitPending(center, 1).first)
        #expect(item.phase == .request && item.ruleName == "BP" && item.request == original && item.response == nil)
        #expect(item.flowID == ctx.id)
        var edited = original
        edited.method = "POST"
        center.resolve(item.id, with: .executeRequest(edited))
        #expect(continued(await task.value) == edited)
        #expect(center.pending.isEmpty)
        #expect(a.all == [.tool("Breakpoint: 편집됨")] && a.all.compactMap(ToolMark.mark) == [.breakpoint])
    }

    @Test func cancellationRemovesPending() async throws {
        let center = BreakpointCenter()
        let bp = interceptor([rule()], center)
        let ctx = Annotations().context
        let task = Task { await bp.intercept(original, context: ctx) }
        let item = try #require(await waitPending(center, 1).first)
        task.cancel()
        #expect(continued(await task.value) == original)
        #expect(center.pending.isEmpty)
        center.resolve(item.id, with: .drop) // 이미 풀린 건: 아무 일도 없어야 한다
        #expect(center.pending.isEmpty)
    }

    @Test func alreadyCancelledIsNotListed() async {
        let center = BreakpointCenter()
        let item = PausedItem(flowID: FlowID(), phase: .request, ruleName: "BP", request: original)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await center.pause(item)
        }
        #expect(await task.value == .continueOriginal)
        #expect(center.pending.isEmpty)
    }

    @Test func abortReturns429And503() async throws {
        for (status, reason) in [(429, "Too Many Requests"), (503, "Service Unavailable")] {
            let center = BreakpointCenter()
            let bp = interceptor([rule()], center)
            let a = Annotations()
            let ctx = a.context
            let task = Task { await bp.intercept(original, context: ctx) }
            let item = try #require(await waitPending(center, 1).first)
            center.resolve(item.id, with: .abort(status: status))
            let r = try #require(responded(await task.value))
            #expect(r == FlowResponse(status: status, reason: reason, headers: [HTTPHeader(name: "Content-Length", value: "0")], body: Data()))
            #expect(a.all == [.tool("Breakpoint: 중단 \(status)")])
        }
    }

    @Test func dropAndContinueOriginal() async throws {
        let center = BreakpointCenter()
        let bp = interceptor([rule()], center)
        let a = Annotations()
        let ctx = a.context
        let t1 = Task { await bp.intercept(original, context: ctx) }
        let i1 = try #require(await waitPending(center, 1).first)
        center.resolve(i1.id, with: .drop)
        guard case .drop = await t1.value else { Issue.record("drop 아님"); return }
        #expect(a.all == [.tool("Breakpoint: 연결 끊김")] && a.all.compactMap(ToolMark.mark) == [.breakpoint])
        // 응답 전용 규칙은 요청 단계에서 멈추지 않는다.
        let none = interceptor([rule(request: false, response: true)], center)
        #expect(continued(await none.intercept(original, context: ctx)) == original)
        #expect(center.pending.isEmpty)
    }

    @Test func responsePhaseEdits() async throws {
        let center = BreakpointCenter()
        // 위의 요청 전용 규칙이 아래 응답 규칙을 가리지 않는다.
        let bp = interceptor([rule(request: true, response: false), rule(request: false, response: true)], center)
        let a = Annotations()
        let ctx = a.context
        let task = Task { await bp.intercept(originalResponse, for: original, context: ctx) }
        let item = try #require(await waitPending(center, 1).first)
        #expect(item.phase == .response && item.response == originalResponse && item.request == original)
        var edited = originalResponse
        edited.status = 418
        center.resolve(item.id, with: .executeResponse(edited))
        #expect(continued(await task.value)?.status == 418)
        #expect(a.all == [.tool("Breakpoint: 편집됨")] && a.all.compactMap(ToolMark.mark) == [.breakpoint])

        let t2 = Task { await bp.intercept(originalResponse, for: original, context: ctx) }
        let i2 = try #require(await waitPending(center, 1).first)
        center.resolve(i2.id, with: .abort(status: 503))
        #expect(continued(await t2.value)?.status == 503)
        #expect(a.all.last == .tool("Breakpoint: 중단 503"))

        let t3 = Task { await bp.intercept(originalResponse, for: original, context: ctx) }
        let i3 = try #require(await waitPending(center, 1).first)
        center.resolve(i3.id, with: .drop)
        guard case .drop = await t3.value else { Issue.record("drop 아님"); return }
        #expect(a.all.last == .tool("Breakpoint: 연결 끊김"))
    }

    @Test func releaseAllContinuesOriginal() async throws {
        let center = BreakpointCenter()
        let bp = interceptor([rule(request: true, response: true)], center)
        let ctx = Annotations().context
        let t1 = Task { await bp.intercept(original, context: ctx) }
        let t2 = Task { await bp.intercept(originalResponse, for: original, context: ctx) }
        #expect(await waitPending(center, 2).count == 2)
        center.releaseAll()
        #expect(continued(await t1.value) == original)
        #expect(continued(await t2.value) == originalResponse)
        #expect(center.pending.isEmpty)
    }

    @Test nonisolated func templateApplyReplacesOnlySetFields() throws {
        let rt = BreakpointTemplate(name: "T", kind: .request, method: "POST", url: nil, headers: [HTTPHeader(name: "X", value: "1")])
        var expected = original
        expected.method = "POST"
        expected.headers = [HTTPHeader(name: "X", value: "1")]
        #expect(rt.apply(to: original) == expected)

        let ut = BreakpointTemplate(name: "U", kind: .request, url: "http://other.test:8080/a/b?q=2", headers: [])
        let u = ut.apply(to: original)
        #expect(u.scheme == "http" && u.host == "other.test" && u.port == 8080 && u.path == "/a/b?q=2" && u.method == "GET")
        #expect(u.headers.isEmpty && u.body == original.body)

        let st = BreakpointTemplate(name: "S", kind: .response, status: 404, headers: [HTTPHeader(name: "Y", value: "2")])
        let s = st.apply(to: originalResponse)
        #expect(s.status == 404 && s.headers == [HTTPHeader(name: "Y", value: "2")] && s.body == originalResponse.body)
        let keep = BreakpointTemplate(name: "K", kind: .response, headers: [])
        #expect(keep.apply(to: originalResponse).status == 200)

        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode([rt, st])) as? [[String: Any]])
        #expect(json[0]["kind"] as? String == "request" && json[1]["kind"] as? String == "response")
        #expect(try JSONDecoder().decode([BreakpointTemplate].self, from: JSONEncoder().encode([rt, st])) == [rt, st])
    }

    @Test nonisolated func ruleCodingUsesProxymanKeys() throws {
        let json = #"{"id":"AB12CD34","name":"R","isEnabled":true,"url":"https://a.test/*","regex":"useWildcard","isRequest":true}"#
        let r = try JSONDecoder().decode(BreakpointRule.self, from: Data(json.utf8))
        #expect(r.onRequest && !r.onResponse && r.match.url == "https://a.test/*")
        let obj = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        #expect(obj["isRequest"] as? Bool == true && obj["isResponse"] as? Bool == false)
        #expect(try JSONDecoder().decode(BreakpointRule.self, from: JSONEncoder().encode(r)) == r)
        #expect(BreakpointRule().id.count == 8 && BreakpointRule().name == "Untitled")
        #expect(RuleFile<BreakpointRule>.breakpoint.name == "breakpoint.json")
    }

    @Test func templatesPersistInRuleStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let t = BreakpointTemplate(name: "T", kind: .response, status: 500, headers: [])
        RuleStore(directory: dir).breakpointTemplates = [t]
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("breakpoint-templates.json").path))
        #expect(RuleStore(directory: dir).breakpointTemplates == [t])
    }
}
