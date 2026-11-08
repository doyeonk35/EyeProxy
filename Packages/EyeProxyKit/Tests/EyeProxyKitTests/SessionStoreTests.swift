import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

@Test @MainActor func storeAppliesResponseToMatchingFlow() {
    let s = SessionStore(); let f = Flow.fixture(client: "1", decrypted: true)
    s.apply(.requestStarted(f)); s.apply(.responseReceived(id: f.id, response: .init(status: 200, reason: "OK", headers: [], body: Data()), completedAt: .now))
    #expect(s.flows.count == 1 && s.flows[0].response?.status == 200 && s.flows[0].completedAt != nil)
}

@Test @MainActor func storeFailsIgnoresUnknownAndCapsLog() {
    let s = SessionStore(); let f = Flow.fixture(client: "1", decrypted: false)
    s.apply(.failed(id: f.id, error: "x", completedAt: .now)); #expect(s.flows.isEmpty)
    s.apply(.requestStarted(f)); s.apply(.failed(id: f.id, error: "boom", completedAt: .now))
    #expect(s.flow(f.id)?.error == "boom")
    for i in 0..<1005 { s.apply(.connectionLog(.init(id: UUID(), date: .now, clientAddress: "1", host: "h", port: i, message: "m"))) }
    #expect(s.connectionLog.count == 1000 && s.connectionLog[0].port == 5)
    s.replace(flows: [f]); #expect(s.connectionLog.isEmpty && s.flow(f.id) != nil)
    s.clear(); #expect(s.flows.isEmpty && s.flow(f.id) == nil)
}

@Test @MainActor func replaceRestoresConnectionLogAndIndex() {
    let s = SessionStore(); let f = Flow.fixture(client: "1", decrypted: true)
    let entry = ConnectionLogEntry(id: UUID(), date: .now, clientAddress: "1", host: "h", port: 1, message: "m")
    s.replace(flows: [f], connectionLog: [entry])
    #expect(s.flow(f.id) != nil && s.connectionLog.count == 1)
    s.replace(flows: [])
    #expect(s.connectionLog.isEmpty)
}

@Test @MainActor func storeNumbersFlowsInArrivalOrderAndResets() {
    let s = SessionStore(); let a = Flow.fixture(client: "1", decrypted: false), b = Flow.fixture(client: "2", decrypted: false)
    s.apply(.requestStarted(a)); s.apply(.requestStarted(b))
    #expect(s.number(a.id) == 1 && s.number(b.id) == 2)
    s.clear(); let c = Flow.fixture(client: "3", decrypted: false); s.apply(.requestStarted(c))
    #expect(s.number(c.id) == 1 && s.number(a.id) == nil)
    s.replace(flows: [b, a]); #expect(s.number(b.id) == 1 && s.number(a.id) == 2)
}
@Test @MainActor func storeAppendsAnnotationToMatchingFlow() {
    let s = SessionStore(); let f = Flow.fixture(client: "1", decrypted: false)
    s.apply(.annotated(id: f.id, .hidden)); #expect(s.flows.isEmpty)
    s.apply(.requestStarted(f)); s.apply(.annotated(id: f.id, .tool("Map Local")))
    #expect(s.flows[0].annotations == [.tool("Map Local")])
}

@Test @MainActor func commentsSetClearAndRemoval() {
    let s = SessionStore(); let a = Flow.fixture(client: "1", decrypted: false), b = Flow.fixture(client: "2", decrypted: false)
    s.apply(.requestStarted(a)); s.apply(.requestStarted(b))
    s.setComment("hello", for: a.id); s.setComment("bye", for: b.id)
    #expect(s.comments == [a.id: "hello", b.id: "bye"])
    s.setComment("", for: a.id); #expect(s.comments[a.id] == nil)
    s.setComment(nil, for: b.id); #expect(s.comments.isEmpty)
    s.setComment("x", for: FlowID()); #expect(s.comments.isEmpty)   // 없는 흐름은 무시
    s.setComment("b", for: b.id); s.apply(.annotated(id: b.id, .unrecorded))
    #expect(s.comments.isEmpty)
    s.setComment("a", for: a.id); s.clear(); #expect(s.comments.isEmpty)
    s.replace(flows: [a], comments: [a.id: "c", FlowID(): "orphan"]); #expect(s.comments == [a.id: "c"])
    s.replace(flows: []); #expect(s.comments.isEmpty)
}

@Test @MainActor func unrecordedLatestDoesNotLeaveGap() {
    let s = SessionStore(); let a = Flow.fixture(client: "1", decrypted: false), b = Flow.fixture(client: "2", decrypted: false)
    s.apply(.requestStarted(a)); s.apply(.requestStarted(b)); s.apply(.annotated(id: b.id, .unrecorded))
    let c = Flow.fixture(client: "3", decrypted: false); s.apply(.requestStarted(c))
    #expect(s.number(a.id) == 1 && s.number(b.id) == nil && s.number(c.id) == 2)
}

@Test @MainActor func unrecordedEarlierLeavesGap() {
    let s = SessionStore(); let a = Flow.fixture(client: "1", decrypted: false), b = Flow.fixture(client: "2", decrypted: false)
    s.apply(.requestStarted(a)); s.apply(.requestStarted(b)); s.apply(.annotated(id: a.id, .unrecorded))
    let c = Flow.fixture(client: "3", decrypted: false); s.apply(.requestStarted(c))
    #expect(s.number(a.id) == nil && s.number(b.id) == 2 && s.number(c.id) == 3)
    #expect(s.flows.map(\.id) == [b.id, c.id] && s.flow(b.id) != nil && s.flow(c.id) != nil)   // index는 위치로 다시 맞춰짐
}

@Test @MainActor func numbersStayStableAfterRemoval() {
    let s = SessionStore(); let fs = (1...3).map { Flow.fixture(client: "\($0)", decrypted: false) }
    fs.forEach { s.apply(.requestStarted($0)) }
    s.remove(ids: [fs[1].id])
    #expect(s.flows.map(\.id) == [fs[0].id, fs[2].id] && s.number(fs[0].id) == 1 && s.number(fs[2].id) == 3)
    #expect(s.flow(fs[2].id)?.id == fs[2].id)   // index 재구성
    let d = Flow.fixture(client: "4", decrypted: false); s.apply(.requestStarted(d))
    #expect(s.number(d.id) == 4)
}

@Test @MainActor func removingNewestDoesNotReuseNumber() {
    let s = SessionStore(); let a = Flow.fixture(client: "1", decrypted: false), b = Flow.fixture(client: "2", decrypted: false)
    s.apply(.requestStarted(a)); s.apply(.requestStarted(b)); s.remove(ids: [b.id])
    let c = Flow.fixture(client: "3", decrypted: false); s.apply(.requestStarted(c))
    #expect(s.number(c.id) == 3)
}

@Test @MainActor func removeKeepsOtherNumbersAndDropsAnnotations() {
    let s = SessionStore(); let fs = (1...4).map { Flow.fixture(client: "\($0)", decrypted: false) }
    fs.forEach { s.apply(.requestStarted($0)) }
    for f in fs { s.setComment("c", for: f.id) }
    s.setHighlight(.red, for: Set(fs.map(\.id)))
    s.remove(ids: [fs[0].id, fs[2].id, FlowID()])   // 없는 id는 무시
    #expect(s.flows.map(\.id) == [fs[1].id, fs[3].id])
    #expect(s.number(fs[1].id) == 2 && s.number(fs[3].id) == 4 && s.number(fs[0].id) == nil)
    #expect(Set(s.comments.keys) == [fs[1].id, fs[3].id] && Set(s.highlights.keys) == [fs[1].id, fs[3].id])
    #expect(s.flow(fs[0].id) == nil && s.flow(fs[3].id)?.id == fs[3].id)
    // 남은 흐름에 대한 이벤트가 올바른 위치로 간다.
    s.apply(.failed(id: fs[3].id, error: "boom", completedAt: .now)); #expect(s.flows[1].error == "boom")
}

@Test @MainActor func highlightSetResetAndStrikeToggle() {
    let s = SessionStore(); let a = Flow.fixture(client: "1", decrypted: false), b = Flow.fixture(client: "2", decrypted: false)
    s.apply(.requestStarted(a)); s.apply(.requestStarted(b))
    s.setHighlight(.blue, for: [a.id, FlowID()])   // 없는 흐름은 무시
    #expect(s.highlights == [a.id: FlowHighlight(color: .blue, strikethrough: false)])
    s.setHighlight(.green, for: [a.id]); #expect(s.highlights[a.id]?.color == .green)   // 새 색이 덮어씀
    // 혼합 선택: b가 꺼져 있으므로 전부 켬
    s.toggleStrikethrough(for: [a.id]); s.toggleStrikethrough(for: [a.id, b.id])
    #expect(s.highlights[a.id]?.strikethrough == true && s.highlights[b.id] == FlowHighlight(color: nil, strikethrough: true))
    // 전부 켜져 있으면 전부 끔 → b는 빈 값이라 저장하지 않음
    s.toggleStrikethrough(for: [a.id, b.id])
    #expect(s.highlights == [a.id: FlowHighlight(color: .green, strikethrough: false)])
    // nil = 색만 지움(취소선 유지)
    s.toggleStrikethrough(for: [a.id]); s.setHighlight(nil, for: [a.id])
    #expect(s.highlights == [a.id: FlowHighlight(color: nil, strikethrough: true)])
    s.setHighlight(.red, for: [a.id, b.id]); s.resetHighlight(for: [a.id])
    #expect(s.highlights == [b.id: FlowHighlight(color: .red, strikethrough: false)])
    s.apply(.annotated(id: b.id, .unrecorded)); #expect(s.highlights.isEmpty)
    s.replace(flows: [a], highlights: [a.id: .init(color: .gray, strikethrough: false), FlowID(): .init(color: .red, strikethrough: false)])
    #expect(s.highlights == [a.id: .init(color: .gray, strikethrough: false)])
    s.replace(flows: [a], highlights: [a.id: .init(color: nil, strikethrough: false)]); #expect(s.highlights.isEmpty)
    #expect(HighlightColor.allCases == [.red, .yellow, .green, .blue, .purple, .gray])
}
