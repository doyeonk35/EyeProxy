import EyeProxyCore
import Foundation

/// 사이드바 트리에서 선택한 행이 가리키는 범위.
public struct FlowScope: Hashable, Sendable {
    public var device: String?
    public var process: String?
    public var host: String?

    public init(device: String? = nil, process: String? = nil, host: String? = nil) {
        self.device = device
        self.process = process
        self.host = host
    }
}

public struct FlowFilter: Equatable, Sendable, Codable {
    public static let unknownProcessKey = "unknown"
    public static let maxRules = 10

    /// 필터 막대 규칙(최대 10개). 켜지고 검색어가 있는 규칙만 거른다.
    public var rules: [FilterRule] = [] {
        didSet { if rules.count > Self.maxRules { rules = Array(rules.prefix(Self.maxRules)) } }
    }
    /// false = 모든 규칙(AND, Proxyman 기본), true = 하나라도(OR).
    public var combineWithOr = false
    public var device: String? = nil
    public var host: String? = nil
    /// ProcessIdentity.groupKey. 귀속 없는 흐름의 키는 `unknownProcessKey`.
    public var process: String? = nil
    /// false면 `.hidden` 주석이 있는 흐름(Block List의 숨김)을 뺀다.
    public var includeHidden = false
    /// 필터 바 프로토콜 묶음. 비면 전체, 안에서는 OR.
    public var protocols: Set<FlowProtocol> = []
    /// 필터 바 콘텐츠 종류 묶음. 비면 전체, 안에서는 OR.
    public var contentKinds: Set<ContentKind> = []
    /// 필터 바 상태 코드 묶음(1...5 = 1xx...5xx). 비어 있지 않으면 응답 없는 흐름은 빠진다.
    public var statusClasses: Set<Int> = []

    /// 필터 바의 세 묶음이 모두 비었는가(= All).
    public var isBarEmpty: Bool { protocols.isEmpty && contentKinds.isEmpty && statusClasses.isEmpty }

    /// 필터 바만 All로 되돌린다. 규칙·사이드바 조건은 그대로.
    public mutating func clearBar() {
        protocols = []; contentKinds = []; statusClasses = []
    }

    public init(device: String? = nil, host: String? = nil) {
        self.device = device
        self.host = host
    }

    // 저장은 필터 막대 규칙만 한다(사이드바·칩 선택은 저장하지 않는다).
    private enum CodingKeys: String, CodingKey { case rules, combineWithOr, text }

    /// 옛 검색어(`text`)만 있으면 켜진 URL·Contains 규칙 하나로 옮긴다.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        combineWithOr = try c.decodeIfPresent(Bool.self, forKey: .combineWithOr) ?? false
        if let rules = try c.decodeIfPresent([FilterRule].self, forKey: .rules) {
            self.rules = Array(rules.prefix(Self.maxRules))
        } else if let text = try c.decodeIfPresent(String.self, forKey: .text), !text.isEmpty {
            rules = [FilterRule(key: .url, match: .contains, text: text)]
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rules, forKey: .rules)
        try c.encode(combineWithOr, forKey: .combineWithOr)
    }

    public static func isLoopback(_ address: String) -> Bool { address == "127.0.0.1" || address == "::1" }

    public static func sameDevice(_ a: String, _ b: String) -> Bool {
        (isLoopback(a) && isLoopback(b)) || a == b
    }

    /// 켜진(isActive) 규칙이 하나라도 있는가 — 하단 바 Filter 버튼 강조.
    public var hasActiveRules: Bool { rules.contains(where: \.isActive) }

    /// 켜진 본문 규칙. 비어 있지 않으면 앱은 본문 판정을 메인 밖에서 한다.
    public var activeBodyRules: [FilterRule] { rules.filter { $0.isActive && $0.needsBody } }

    public func matches(_ flow: Flow, process: String? = nil) -> Bool { matches(FilterSubject(flow: flow), process: process) }

    /// process: 그 흐름의 groupKey(귀속 없으면 nil).
    public func matches(_ subject: FilterSubject, process: String? = nil) -> Bool { prepared().matches(subject, process: process) }

    /// 여러 흐름을 거를 때 한 번 만든다: 켜진 규칙과 그 정규식을 흐름마다가 아니라 한 번만 준비한다.
    public func prepared() -> PreparedFilter { PreparedFilter(self) }
}

/// 한 번의 거르기 동안 쓰는 `FlowFilter`. 켜진 규칙·정규식은 만들 때 한 번만 계산한다.
public struct PreparedFilter {
    public let filter: FlowFilter
    /// body: 본문 규칙이면 `bodyRules` 안의 자리.
    private let active: [(rule: FilterRule, regex: NSRegularExpression?, body: Int?)]
    /// 켜진 본문 규칙(순서대로). `bodyHits`·`matches(bodyHits:)`의 배열이 이 순서를 따른다.
    public let bodyRules: [FilterRule]

    init(_ filter: FlowFilter) {
        self.filter = filter
        var active: [(rule: FilterRule, regex: NSRegularExpression?, body: Int?)] = []
        var bodyRules: [FilterRule] = []
        for r in filter.rules where r.isEnabled && !r.text.isEmpty {
            let regex = r.regex
            // 정규식 매칭인데 컴파일되지 않으면(isInvalid) 뺀다 — 흐름마다 다시 컴파일하지 않는다.
            if regex == nil, [.matchRegex, .notMatchRegex].contains(r.match) { continue }
            active.append((r, regex, r.needsBody ? bodyRules.count : nil))
            if r.needsBody { bodyRules.append(r) }
        }
        self.active = active
        self.bodyRules = bodyRules
    }

    /// 본문 규칙만 판정한다(메인 밖에서 부른다). 결과는 `bodyRules` 순서.
    public func bodyHits(_ subject: FilterSubject) -> [Bool] {
        active.filter { $0.body != nil }.map { $0.rule.matches(subject, regex: $0.regex) }
    }

    /// bodyHits: 미리 판정한 본문 규칙 결과(`bodyRules` 순서). nil이면 본문 규칙도 여기서 판정한다.
    public func matches(_ subject: FilterSubject, process: String? = nil, bodyHits: [Bool]? = nil) -> Bool {
        let flow = subject.flow
        let f = filter
        if !f.includeHidden, flow.annotations.contains(.hidden) { return false }
        if let device = f.device, !FlowFilter.sameDevice(flow.clientAddress, device) { return false }
        if let wanted = f.process, (process ?? FlowFilter.unknownProcessKey) != wanted { return false }
        if let host = f.host, flow.request.host != host { return false }
        if !f.protocols.isEmpty, !f.protocols.contains(FlowProtocol.of(flow)) { return false }
        if !f.contentKinds.isEmpty, !f.contentKinds.contains(ContentKind.of(flow)) { return false }
        if !f.statusClasses.isEmpty, !(flow.response.map { f.statusClasses.contains($0.status / 100) } ?? false) { return false }
        if active.isEmpty { return true }
        let hit = { (e: (rule: FilterRule, regex: NSRegularExpression?, body: Int?)) -> Bool in
            guard let i = e.body, let bodyHits else { return e.rule.matches(subject, regex: e.regex) }
            return i < bodyHits.count && bodyHits[i]
        }
        return f.combineWithOr ? active.contains(where: hit) : active.allSatisfy(hit)
    }
}
