import EyeProxyCore
import Foundation

/// Proxyman `localFile` 값.
public struct LocalFileRef: Codable, Equatable, Sendable {
    public var name: String
    public var path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// Map Local 규칙. Proxyman `MapLocalFiles-RuleTree` 노드의 `_0`과 같은 키로 코딩한다.
public struct MapLocalRule: ToolRule {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var match: MatchRule
    public var useLocalFile: Bool
    public var localFile: LocalFileRef?
    public var useDirectory: Bool
    public var directoryPath: String?
    /// `advanceSettings.delayTimePreset`. 단위는 초로 가정.
    public var delaySeconds: Int?

    public static let delayPresets: [Int?] = [nil, 1, 2, 3, 5, 10, 30]

    public init(
        id: String = String(UUID().uuidString.prefix(8)), name: String = "Untitled", isEnabled: Bool = true,
        match: MatchRule = MatchRule(), useLocalFile: Bool = true, localFile: LocalFileRef? = nil,
        useDirectory: Bool = false, directoryPath: String? = nil, delaySeconds: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.match = match
        self.useLocalFile = useLocalFile
        self.localFile = localFile
        self.useDirectory = useDirectory
        self.directoryPath = directoryPath
        self.delaySeconds = delaySeconds
    }

    private struct PathRef: Codable { var path: String }
    private struct Advance: Codable { var delayTimePreset: Int? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ProxymanKey.self)
        id = try c.decode(String.self, forKey: "id")
        name = try c.decode(String.self, forKey: "name")
        isEnabled = try c.decode(Bool.self, forKey: "isEnabled")
        match = try MatchRule(proxymanFields: c)
        useLocalFile = try c.decodeIfPresent(Bool.self, forKey: "isLocalFileEnable") ?? false
        localFile = try c.decodeIfPresent(LocalFileRef.self, forKey: "localFile")
        useDirectory = try c.decodeIfPresent(Bool.self, forKey: "isDirectoryFileEnable") ?? false
        // 모양 미확인: `{"path":…}` 또는 문자열.
        if let s = try? c.decodeIfPresent(String.self, forKey: "directoryFile") {
            directoryPath = s
        } else {
            directoryPath = try c.decodeIfPresent(PathRef.self, forKey: "directoryFile")?.path
        }
        delaySeconds = try c.decodeIfPresent(Advance.self, forKey: "advanceSettings")?.delayTimePreset
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ProxymanKey.self)
        try c.encode(id, forKey: "id")
        try c.encode(name, forKey: "name")
        try c.encode(isEnabled, forKey: "isEnabled")
        try match.encode(proxymanFields: &c)
        try c.encode(useLocalFile, forKey: "isLocalFileEnable")
        try c.encode(localFile, forKey: "localFile")
        try c.encode(useDirectory, forKey: "isDirectoryFileEnable")
        try c.encode(directoryPath.map(PathRef.init), forKey: "directoryFile")
        try c.encode(Advance(delayTimePreset: delaySeconds), forKey: "advanceSettings")
    }

    /// 디렉터리 모드에서 폴더 아래 찾을 상대 경로(쿼리 제외, 퍼센트 디코딩).
    /// Wildcard: 패턴 경로의 첫 `*`/`?` 앞 리터럴 접두를 뗀다(host만이면 전체 경로). Regex: 첫 캡처 그룹.
    /// 비었거나 `..` 성분이 있으면 nil.
    public func relativePath(for request: FlowRequest) -> String? {
        var raw: Substring
        switch match.mode {
        case .regex:
            let target = MatchRule.urlString(request, includeQuery: match.queryMode == .exact)
            // ponytail: 요청마다 컴파일. 디렉터리 정규식 규칙이 많아지면 캐시.
            guard let re = try? NSRegularExpression(pattern: "^(?:\(match.url))$"),
                  let m = re.firstMatch(in: target, range: NSRange(target.startIndex..., in: target)),
                  m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: target) else { return nil }
            raw = target[r]
        case .wildcard:
            var pattern = Substring(match.url)
            if let s = pattern.range(of: "://"), !pattern[..<s.lowerBound].contains("/") { pattern = pattern[s.upperBound...] }
            // ponytail: 경로 중간 와일드카드(`/v*/static/*`)는 첫 와일드카드까지만 뗀다. 필요하면 정규식으로 접두 매칭.
            let literal = pattern.firstIndex(of: "/").map { pattern[$0...].prefix { $0 != "*" && $0 != "?" } } ?? ""
            let path = Substring(request.path)
            if literal.isEmpty {
                raw = path
            } else {
                guard let p = path.range(of: literal, options: [.anchored, .caseInsensitive]) else { return nil }
                raw = path[p.upperBound...]
            }
        }
        if let q = raw.firstIndex(of: "?") { raw = raw[..<q] }
        let decoded = String(raw).removingPercentEncoding ?? String(raw)
        let rel = String(decoded.drop { $0 == "/" })
        guard !rel.isEmpty, !rel.split(separator: "/").contains("..") else { return nil }
        return rel
    }
}

extension RuleFile where R == MapLocalRule {
    public static var mapLocal: Self { .init(name: "map-local.json") }
}
