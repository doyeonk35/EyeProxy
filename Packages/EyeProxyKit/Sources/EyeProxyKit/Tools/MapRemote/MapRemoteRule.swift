import EyeProxyCore
import Foundation

/// Map Remote 목적지. 비었거나 nil인 칸은 원래 요청 값을 유지한다.
public struct MapTarget: Equatable, Sendable {
    public var scheme: String?
    public var host: String?
    public var port: Int?
    public var path: String?
    public var query: String?

    public init(scheme: String? = nil, host: String? = nil, port: Int? = nil, path: String? = nil, query: String? = nil) {
        self.scheme = scheme.nilIfEmpty
        self.host = host.nilIfEmpty
        self.port = port
        self.path = path.nilIfEmpty
        self.query = query.nilIfEmpty
    }

    /// Host 칸에 붙여넣은 URL을 5칸으로 나눈다. scheme이 없으면(`host:port/path`) scheme은 nil.
    public static func parse(pastedURL: String) -> MapTarget {
        let text = pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasScheme = text.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) != nil
        guard let c = URLComponents(string: hasScheme ? text : "https://" + text) else { return MapTarget(host: text) }
        let scheme = hasScheme ? c.scheme?.lowercased() : nil
        return MapTarget(scheme: scheme, host: c.host, port: c.port,
                         path: c.percentEncodedPath == "/" ? nil : c.percentEncodedPath, query: c.percentEncodedQuery)
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? { self?.isEmpty == false ? self : nil }
}

/// Map Remote 규칙. Proxyman 키(`toURL`, `isPreserveHostHeader`, `isPreserveOriginalURL`)는 가정(스펙 §9.2).
public struct MapRemoteRule: ToolRule {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var match: MatchRule
    public var mapTo: MapTarget
    public var preserveHostHeader: Bool
    public var preserveOriginalURL: Bool

    public init(
        id: String = String(UUID().uuidString.prefix(8)), name: String = "Untitled", isEnabled: Bool = true,
        match: MatchRule = MatchRule(includeSubpaths: true, ignoreQuery: true), mapTo: MapTarget = MapTarget(),
        preserveHostHeader: Bool = false, preserveOriginalURL: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.match = match
        self.mapTo = mapTo
        self.preserveHostHeader = preserveHostHeader
        self.preserveOriginalURL = preserveOriginalURL
    }

    private struct ToURL: Codable {
        var `protocol`: String?
        var host: String?
        var port: Int?
        var path: String?
        var query: String?

        init(_ t: MapTarget) { (`protocol`, host, port, path, query) = (t.scheme, t.host, t.port, t.path, t.query) }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: ProxymanKey.self)
            `protocol` = try c.decodeIfPresent(String.self, forKey: "protocol")
            host = try c.decodeIfPresent(String.self, forKey: "host")
            // 포트는 숫자 또는 문자열로 올 수 있다고 가정.
            port = try? c.decodeIfPresent(Int.self, forKey: "port")
            if port == nil { port = (try? c.decodeIfPresent(String.self, forKey: "port")).flatMap { Int($0) } }
            path = try c.decodeIfPresent(String.self, forKey: "path")
            query = try c.decodeIfPresent(String.self, forKey: "query")
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ProxymanKey.self)
        id = try c.decode(String.self, forKey: "id")
        name = try c.decode(String.self, forKey: "name")
        isEnabled = try c.decode(Bool.self, forKey: "isEnabled")
        match = try MatchRule(proxymanFields: c)
        let to = try c.decode(ToURL.self, forKey: "toURL")
        mapTo = MapTarget(scheme: to.protocol, host: to.host, port: to.port, path: to.path, query: to.query)
        preserveHostHeader = try c.decodeIfPresent(Bool.self, forKey: "isPreserveHostHeader") ?? false
        preserveOriginalURL = try c.decodeIfPresent(Bool.self, forKey: "isPreserveOriginalURL") ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ProxymanKey.self)
        try c.encode(id, forKey: "id")
        try c.encode(name, forKey: "name")
        try c.encode(isEnabled, forKey: "isEnabled")
        try match.encode(proxymanFields: &c)
        try c.encode(ToURL(mapTo), forKey: "toURL")
        try c.encode(preserveHostHeader, forKey: "isPreserveHostHeader")
        try c.encode(preserveOriginalURL, forKey: "isPreserveOriginalURL")
    }

    /// 패턴 경로에서 첫 `*`/`?` 앞까지, 끝 `/` 제외. 정규식·경로 없음이면 nil.
    var matchedPrefix: String? {
        guard match.mode == .wildcard else { return nil }
        var pattern = Substring(match.url)
        if let s = pattern.range(of: "://"), !pattern[..<s.lowerBound].contains("/") { pattern = pattern[s.upperBound...] }
        guard let slash = pattern.firstIndex(of: "/") else { return nil }
        var prefix = String(pattern[slash...].prefix { $0 != "*" && $0 != "?" })
        while prefix.hasSuffix("/") { prefix.removeLast() }
        return prefix.isEmpty ? nil : prefix
    }
}

extension RuleFile where R == MapRemoteRule {
    public static var mapRemote: Self { .init(name: "map-remote.json") }
}
