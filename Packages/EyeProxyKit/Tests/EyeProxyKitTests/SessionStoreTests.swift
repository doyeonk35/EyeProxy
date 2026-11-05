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
