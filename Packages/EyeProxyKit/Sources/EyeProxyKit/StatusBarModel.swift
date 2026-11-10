import EyeProxyCore
import Foundation

/// 하단 바의 켜진 도구 배지(스펙 §6). 켜진 것만 이 순서로 보인다.
public enum ActiveToolBadge: String, CaseIterable, Sendable {
    case breakpoint = "Breakpoint"
    case mapLocal = "Map Local"
    case mapRemote = "Map Remote"
    case blockList = "Block List"
    case allowList = "Allow List"
    case networkConditions = "Network Conditions"
    case noCaching = "No Caching"
    case proxyOverridden = "Proxy Overridden"
    case sslProxyingOff = "SSL Proxying Off"

    /// Proxyman과 같은 영어 이름.
    public var title: String { rawValue }

    /// 누르면 여는 창 id. nil이면 창이 없다 — No Caching은 바 안 팝오버, SSL Proxying Off는 설정 ▸ SSL 탭(앱이 처리).
    /// Proxy Overridden은 Certificate 창(`devices`)의 이 Mac 섹션.
    public var windowID: String? {
        switch self {
        case .breakpoint: "tool-breakpoint-rules"
        case .mapLocal: "tool-map-local"
        case .mapRemote: "tool-map-remote"
        case .blockList: "tool-block"
        case .allowList: "tool-allow"
        case .networkConditions: "tool-network"
        case .proxyOverridden: "devices"
        case .noCaching, .sslProxyingOff: nil
        }
    }

    public static func active(switches: ToolSwitches, proxyOverridden: Bool, sslEnabled: Bool) -> [ActiveToolBadge] {
        allCases.filter {
            switch $0 {
            case .breakpoint: switches.breakpoint
            case .mapLocal: switches.mapLocal
            case .mapRemote: switches.mapRemote
            case .blockList: switches.blockList
            case .allowList: switches.allowList
            case .networkConditions: switches.networkConditions
            case .noCaching: switches.noCaching
            case .proxyOverridden: proxyOverridden
            case .sslProxyingOff: !sslEnabled
            }
        }
    }
}

/// 하단 바 메모리·속도 표시(스펙 §6). 속도는 최근 1초의 요청·응답 본문 크기 합으로 근사한다(터널은 본문을 모르므로 0).
public enum Throughput {
    /// (now - 1초, now] 안에 시작한 요청 본문(↑)과 끝난 응답 본문(↓) 바이트.
    /// ponytail: 매 초 세션 전체를 훑는다(O(n)) — 수십만 건에서 느려지면 이벤트마다 쌓는 링 버퍼로.
    public static func lastSecond(_ flows: [Flow], now: Date) -> (up: Int, down: Int) {
        let from = now.addingTimeInterval(-1)
        func inWindow(_ date: Date) -> Bool { date > from && date <= now }
        var up = 0, down = 0
        for flow in flows {
            if inWindow(flow.startedAt) { up += flow.request.body.count }
            if let done = flow.completedAt, inWindow(done), let response = flow.response { down += response.body.count }
        }
        return (up, down)
    }

    /// `181 MB · ↑122 KB/s ↓20 KB/s` — 1000 단위, 정수로 반올림.
    public static func format(memory: Int, up: Int, down: Int) -> String {
        "\(short(memory)) · ↑\(short(up))/s ↓\(short(down))/s"
    }

    private static func short(_ count: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(count), unit = 0
        while value >= 999.5, unit < units.count - 1 { value /= 1000; unit += 1 }
        return "\(Int(value.rounded())) \(units[unit])"
    }
}
