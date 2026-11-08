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
