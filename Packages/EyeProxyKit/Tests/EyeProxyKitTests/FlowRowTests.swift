import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

@Test func rowDerivesSortKeys() {
    var f = Flow.fixture(url: "https://api.tving.com/v2?x=1", method: "POST", status: 404)
    f.response?.body = Data(count: 12); f.completedAt = f.startedAt.addingTimeInterval(0.0634)
    let r = FlowRow(flow: f, number: 7)
    #expect(r.number == 7 && r.method == "POST" && r.host == "api.tving.com" && r.status == 404 && r.size == 12 && r.durationMS == 63)
    var p = Flow.fixture(client: "1", decrypted: false); #expect(FlowRow(flow: p, number: 1).status == -1 && FlowRow(flow: p, number: 1).size == -1 && FlowRow(flow: p, number: 1).durationMS == -1)
    p.error = "x"; #expect(FlowRow(flow: p, number: 1).status == -2)
}

@Test func rowsSortPendingToOneEnd() {
    let done = FlowRow(flow: Flow.fixture(url: "https://a/", method: "GET", status: 200), number: 1)
    let pending = FlowRow(flow: Flow.fixture(client: "1", decrypted: false), number: 2)
    let asc = [done, pending].sorted(using: [KeyPathComparator(\FlowRow.status)])
    #expect(asc.map(\.number) == [2, 1])
    let desc = [done, pending].sorted(using: [KeyPathComparator(\FlowRow.status, order: .reverse)])
    #expect(desc.map(\.number) == [1, 2])
}
