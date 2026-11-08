import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

@Test func rowDerivesSortKeys() {
    var f = Flow.fixture(url: "https://api.example.com/v2?x=1", method: "POST", status: 404)
    f.response?.body = Data(count: 12); f.completedAt = f.startedAt.addingTimeInterval(0.0634)
    let r = FlowRow(flow: f, number: 7)
    #expect(r.number == 7 && r.method == "POST" && r.host == "api.example.com" && r.status == 404 && r.size == 12 && r.durationMS == 63)
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

@Test func toolMarkRoundTrip() {
    for m in ToolMark.allCases {
        #expect(ToolMark.mark(of: ToolMark.annotation(m, detail: "R")) == m)
        #expect(ToolMark.mark(of: ToolMark.annotation(m, detail: nil)) == m)
    }
    #expect(ToolMark.annotation(.mapLocal, detail: "R") == .tool("Map Local: R"))
    #expect(ToolMark.annotation(.blocked, detail: nil) == .tool("Blocked"))
    #expect(ToolMark.mark(of: .tool("Map Local 파일 없음: R")) == nil)
    #expect(ToolMark.mark(of: .tool("자동 복호화(규칙: R)")) == nil)
    #expect(ToolMark.mark(of: .tool("Map Localx")) == nil && ToolMark.mark(of: .hidden) == nil)
}

@Test func flowRowEditedMarks() {
    var f = Flow.fixture(client: "1", decrypted: true)
    f.annotations = [.tool("Map Remote: A"), .tool("Map Local: B"), .tool("자동 복호화(규칙: C)"), .tool("Map Local: B")]
    let r = FlowRow(flow: f, number: 1)
    #expect(r.editedMarks == [.mapRemote, .mapLocal] && r.edited == "Map Remote, Map Local")
    #expect(FlowRow(flow: Flow.fixture(client: "1", decrypted: true), number: 1).edited == "")
}

@Test func flowRowStateAndSizes() {
    var done = Flow.fixture(url: "https://a/", method: "POST", status: 200)
    done.request.body = Data(count: 5); done.response?.body = Data(count: 9); done.completedAt = done.startedAt
    let r = FlowRow(flow: done, number: 1)
    #expect(r.state == .completed && r.requestSize == 5 && r.responseSize == 9 && r.isSSL)
    var failed = Flow.fixture(client: "1", decrypted: false); failed.error = "x"; failed.completedAt = .now
    #expect(FlowRow(flow: failed, number: 1).state == .failed)
    let active = Flow.fixture(client: "1", decrypted: false)
    let a = FlowRow(flow: active, number: 1)
    #expect(a.state == .active && a.requestSize == 0 && a.responseSize == 0 && !a.isSSL)
}

@Test func durationTextLikeProxyman() {
    #expect(FlowRow.durationText(ms: -1) == "-")
    #expect(FlowRow.durationText(ms: 266) == "266 ms")
    #expect(FlowRow.durationText(ms: 1020) == "1.02 s" && FlowRow.durationText(ms: 59260) == "59.26 s")
    #expect(FlowRow.durationText(ms: 120600) == "2.01 min")
}
