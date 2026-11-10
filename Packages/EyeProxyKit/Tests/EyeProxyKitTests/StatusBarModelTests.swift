import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

@Test func activeToolBadgesFollowSwitches() {
    var s = ToolSwitches()
    #expect(ActiveToolBadge.active(switches: s, proxyOverridden: false, sslEnabled: true) == [])
    // Repeat의 No Cache는 도구 배지가 아니다.
    s.repeatNoCache = true
    #expect(ActiveToolBadge.active(switches: s, proxyOverridden: false, sslEnabled: true) == [])
    s.breakpoint = true
    s.networkConditions = true
    s.noCaching = true
    #expect(ActiveToolBadge.active(switches: s, proxyOverridden: false, sslEnabled: true) == [.breakpoint, .networkConditions, .noCaching])
    s.mapLocal = true; s.mapRemote = true; s.blockList = true; s.allowList = true
    #expect(ActiveToolBadge.active(switches: s, proxyOverridden: true, sslEnabled: false) == ActiveToolBadge.allCases)
    #expect(ActiveToolBadge.active(switches: ToolSwitches(), proxyOverridden: true, sslEnabled: false) == [.proxyOverridden, .sslProxyingOff])
    #expect(ActiveToolBadge.allCases.map(\.title) == ["Breakpoint", "Map Local", "Map Remote", "Block List", "Allow List",
                                                      "Network Conditions", "No Caching", "Proxy Overridden", "SSL Proxying Off"])
}

@Test func badgeOpensMatchingWindow() {
    let ids = Dictionary(uniqueKeysWithValues: ActiveToolBadge.allCases.map { ($0, $0.windowID) })
    #expect(ids == [.breakpoint: "tool-breakpoint-rules", .mapLocal: "tool-map-local", .mapRemote: "tool-map-remote",
                    .blockList: "tool-block", .allowList: "tool-allow", .networkConditions: "tool-network",
                    .proxyOverridden: "devices",
                    // 창이 없다: No Caching은 바 안 팝오버, SSL은 설정 ▸ SSL 탭(앱이 처리).
                    .noCaching: nil, .sslProxyingOff: nil])
}

@Test func throughputSumsLastSecond() {
    let now = Date(timeIntervalSince1970: 1000)
    func flow(started: TimeInterval, up: Int, completed: TimeInterval? = nil, down: Int = 0) -> Flow {
        let f = Flow.fixture(client: "1", decrypted: true)
        var request = f.request
        request.body = Data(count: up)
        return Flow(id: FlowID(), clientAddress: f.clientAddress, startedAt: Date(timeIntervalSince1970: started), request: request,
                    response: completed.map { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data(count: down)) },
                    completedAt: completed.map { Date(timeIntervalSince1970: $0) })
    }
    let flows = [
        flow(started: 990, up: 5_000, completed: 999.5, down: 20_000),   // 응답만 최근 1초
        flow(started: 999.2, up: 122_000),                               // 진행 중, 요청만
        flow(started: 999, up: 7, completed: 999, down: 9),              // 정확히 1초 전 = 창 밖
        flow(started: 1000, up: 1, completed: 1000, down: 2),            // 지금 = 창 안
        flow(started: 1000.5, up: 50, completed: 1000.5, down: 50),      // 미래(시계 차) = 창 밖
    ]
    let rate = Throughput.lastSecond(flows, now: now)
    #expect(rate.up == 122_001)
    #expect(rate.down == 20_002)
    #expect(Throughput.lastSecond([], now: now) == (up: 0, down: 0))
    #expect(Throughput.format(memory: 181_000_000, up: 122_000, down: 20_000) == "181 MB · ↑122 KB/s ↓20 KB/s")
    #expect(Throughput.format(memory: 1_234_567_890, up: 0, down: 999) == "1 GB · ↑0 B/s ↓999 B/s")
    #expect(Throughput.format(memory: 999_600, up: 1_500_000, down: 2_449) == "1 MB · ↑2 MB/s ↓2 KB/s")
}
