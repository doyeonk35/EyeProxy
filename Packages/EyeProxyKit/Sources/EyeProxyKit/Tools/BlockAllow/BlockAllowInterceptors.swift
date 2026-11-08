import EyeProxyCore
import Foundation

extension MatchRule {
    /// CONNECT 단계에서 판정 가능한 규칙: 와일드카드, host 뒤에 경로·포트 없음(`/`·`/*`만), 메서드·GraphQL 제한 없음.
    var connectHostPattern: String? {
        guard let host = hostPattern, methods == .any, graphQLQueryName == nil else { return nil }
        var rest = Substring(url)
        if let r = rest.range(of: "://") { rest = rest[r.upperBound...] }
        let tail = rest.drop { $0 != "/" }
        guard rest.prefix(while: { $0 != "/" }).lowercased() == host, ["", "/", "/*"].contains(tail) else { return nil }
        return host
    }

    /// Block·Allow가 CONNECT 단계에서 호스트만으로 판정하는 규칙(자동 복호화 대상 아님).
    public var isDecidedAtConnect: Bool { connectHostPattern != nil }

    /// `*` 임의 길이, `?` 한 글자, 대소문자 무시.
    func hostGlobMatches(_ host: String) -> Bool {
        guard let pattern = connectHostPattern ?? hostPattern else { return false }
        return Self.glob(Array(pattern), Array(host.lowercased()))
    }

    /// Allow CONNECT용. 호스트 패턴이 없는 규칙(정규식, `*`뿐인 호스트)은 어떤 호스트와도 맞을 수 있다.
    /// 명시적 `http://` 규칙은 CONNECT(HTTPS)와 맞지 않는다.
    func couldMatchHost(_ host: String) -> Bool {
        if mode == .regex { return true }
        if url.range(of: "http://", options: [.anchored, .caseInsensitive]) != nil { return false }
        return hostPattern == nil || hostGlobMatches(host)
    }

    private static func glob(_ p: [Character], _ s: [Character]) -> Bool {
        var (i, j, star, mark) = (0, 0, -1, 0)
        while j < s.count {
            if i < p.count, p[i] == "*" { star = i; mark = j; i += 1 }
            else if i < p.count, p[i] == "?" || p[i] == s[j] { i += 1; j += 1 }
            else if star >= 0 { i = star + 1; mark += 1; j = mark }
            else { return false }
        }
        while i < p.count, p[i] == "*" { i += 1 }
        return i == p.count
    }
}

public typealias AppPathLookup = @Sendable (_ clientAddress: String, _ clientPort: Int?) async -> String?

/// 첫 일치 Block 규칙을 적용한다. CONNECT에선 host 전용·앱 규칙만 판정하고 나머지는 요청 단계로 미룬다.
public struct BlockInterceptor: RequestInterceptor, ConnectInterceptor {
    let rules: RuleTree<BlockRule>
    let appPath: AppPathLookup

    public init(rules: RuleTree<BlockRule>, appPath: @escaping AppPathLookup) {
        self.rules = rules
        self.appPath = appPath
    }

    // ponytail: 요청마다 lsof 조회. 느리면 포트별 캐시.
    private func app(_ enabled: [BlockRule], _ address: String, _ port: Int?) async -> String? {
        enabled.contains { $0.appPath != nil } ? await appPath(address, port) : nil
    }

    public func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision {
        let enabled = rules.enabledRules
        let app = await app(enabled, context.clientAddress, context.clientPort)
        guard let rule = enabled.first(where: { r in
            if let p = r.appPath {
                return p == app && (r.match.url.isEmpty || r.match.matches(request))
            }
            return r.match.matches(request)
        }) else { return .continue(request) }
        switch rule.action {
        case .blockAndHide:
            context.annotate(.hidden)
            return .drop
        case .blockAndDisplay:
            context.annotate(ToolMark.annotation(.blocked, detail: rule.name))
            return .drop
        case .hideOnly:
            context.annotate(.hidden)
            return .continue(request)
        }
    }

    public func intercept(host: String, port: Int, context: ConnectContext) async -> ConnectVerdict {
        let enabled = rules.enabledRules
        let app = await app(enabled, context.clientAddress, context.clientPort)
        guard let rule = enabled.first(where: { r in
            if let p = r.appPath {
                guard p == app else { return false }
                return r.match.url.isEmpty || (r.match.connectHostPattern != nil && r.match.hostGlobMatches(host))
            }
            return r.match.connectHostPattern != nil && r.match.hostGlobMatches(host)
        }) else { return ConnectVerdict() }
        switch rule.action {
        case .blockAndHide: return ConnectVerdict(action: .drop, record: false)
        // 기록되는 끊긴 CONNECT 항목에도 Blocked 표시(Core가 note를 주석으로 단다).
        case .blockAndDisplay: return ConnectVerdict(action: .drop, note: ToolMark.label(.blocked, detail: rule.name))
        case .hideOnly: return ConnectVerdict(record: false)
        }
    }
}

/// 어떤 규칙에도 안 맞는 트래픽을 기록하지 않는다. 켜진 규칙이 없으면 아무 영향 없음.
public struct AllowInterceptor: RequestInterceptor, ConnectInterceptor {
    let rules: RuleTree<AllowRule>

    public init(rules: RuleTree<AllowRule>) { self.rules = rules }

    public func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision {
        let enabled = rules.enabledRules
        if !enabled.isEmpty, !enabled.contains(where: { $0.match.matches(request) }) { context.annotate(.unrecorded) }
        return .continue(request)
    }

    public func intercept(host: String, port: Int, context: ConnectContext) async -> ConnectVerdict {
        let enabled = rules.enabledRules
        if enabled.isEmpty || enabled.contains(where: { $0.match.couldMatchHost(host) }) { return ConnectVerdict() }
        return ConnectVerdict(action: .tunnel, record: false)
    }
}
