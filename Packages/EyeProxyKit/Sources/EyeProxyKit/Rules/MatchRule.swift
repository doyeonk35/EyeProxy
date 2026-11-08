import EyeProxyCore
import Foundation
import Synchronization

public enum MatchMode: String, Codable, Sendable {
    case wildcard = "useWildcard"
    case regex = "useRegex"
}

/// 쿼리 비교 방식. `.ignore` = 쿼리를 떼고 비교(새 규칙 기본), `.selected` = 경로는 `.ignore`처럼 + 체크된 조건만 비교,
/// `.exact` = Proxyman과 같이 쿼리 포함 전체 URL 비교(가져온 규칙 기본).
public enum QueryMode: String, Codable, Sendable {
    case ignore, selected, exact
}

/// `.selected`의 쿼리 조건. 키는 정확히(대소문자 구분), 값은 `*`·`?` 와일드카드. `id`는 편집기용이라 저장하지 않는다.
public struct QueryCondition: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var key: String
    public var value: String
    public var isEnabled: Bool

    public init(key: String, value: String, isEnabled: Bool) {
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey { case key, value, isEnabled }

    public static func == (a: Self, b: Self) -> Bool {
        a.key == b.key && a.value == b.value && a.isEnabled == b.isEnabled
    }
}

public enum MethodMatch: Equatable, Sendable {
    case any
    case exact([String])
}

/// 도구(Map Local/Remote, Breakpoint, Block/Allow)가 공유하는 URL 매칭 규칙.
public struct MatchRule: Equatable, Sendable {
    public var url: String
    public var mode: MatchMode
    public var methods: MethodMatch
    public var includeSubpaths: Bool
    public var queryMode: QueryMode
    public var queryConditions: [QueryCondition]
    public var graphQLQueryName: String?

    public init(
        url: String = "", mode: MatchMode = .wildcard, methods: MethodMatch = .any,
        includeSubpaths: Bool = false, queryMode: QueryMode = .ignore, queryConditions: [QueryCondition] = [],
        graphQLQueryName: String? = nil
    ) {
        self.url = url
        self.mode = mode
        self.methods = methods
        self.includeSubpaths = includeSubpaths
        self.queryMode = queryMode
        self.queryConditions = queryConditions
        self.graphQLQueryName = graphQLQueryName
    }

    public func matches(_ request: FlowRequest) -> Bool {
        if case .exact(let list) = methods,
           !list.contains(where: { $0.caseInsensitiveCompare(request.method) == .orderedSame }) { return false }
        guard let regex = compiled() else { return false }
        let target = Self.urlString(request, includeQuery: queryMode == .exact)
        guard regex.firstMatch(in: target, range: NSRange(target.startIndex..., in: target)) != nil else { return false }
        guard queryMode == .selected else { return true }
        let items = Self.queryItems(request.path)
        return activeConditions.allSatisfy { c in
            guard let re = Self.cache(
                pattern: "^(?:\(Self.wildcardRegex(c.value)))$", options: .dotMatchesLineSeparators, key: "q:\(c.value)"
            ) else { return false }
            return items.contains { $0.key == c.key && re.firstMatch(in: $0.value, range: NSRange($0.value.startIndex..., in: $0.value)) != nil }
        }
    }

    /// 우클릭 ▸ Tools로 만드는 새 규칙: 요청 URL(쿼리 제외) + 그 메서드 + 쿼리 무시.
    /// 요청의 쿼리 항목은 체크 해제로 넣어 두어 사용자가 필요한 것만 체크해 `.selected`로 바꾸게 한다.
    public init(prefilledFrom request: FlowRequest) {
        self.init(
            url: Self.urlString(request, includeQuery: false), methods: .exact([request.method]),
            queryConditions: Self.queryItems(request.path).map { QueryCondition(key: $0.key, value: $0.value, isEnabled: false) })
    }

    /// 체크됐고 키가 빈 칸이 아닌 조건(`.selected`에서 실제로 비교하는 것).
    public var activeConditions: [QueryCondition] {
        queryConditions.filter { $0.isEnabled && !$0.key.isEmpty }
    }

    /// 규칙 목록 Matching Rule 열 꼬리말.
    public var queryDescription: String? {
        switch queryMode {
        case .selected: activeConditions.isEmpty ? nil : "쿼리 \(activeConditions.count)개"
        case .exact: "쿼리 전체 일치"
        case .ignore: nil
        }
    }

    /// 편집기 URL 칸에 붙여 넣은 쿼리를 체크된 조건으로 떼어 낸다. 첫 `?` 뒤가 `k=v(&k=v)*` 꼴일 때만
    /// (`/v?/users`·`?*` 같은 와일드카드 `?`는 그대로). 키·값은 퍼센트 디코딩해 보여 준다.
    public static func splitQuery(fromPattern url: String) -> (url: String, conditions: [QueryCondition]) {
        guard let q = url.firstIndex(of: "?") else { return (url, []) }
        let query = String(url[url.index(after: q)...])
        guard query.range(of: #"^[^&=/?]+=[^&]*(&[^&=/?]+=[^&]*)*$"#, options: .regularExpression) != nil else { return (url, []) }
        return (String(url[..<q]), queryItems("?" + query).map { QueryCondition(key: $0.key, value: $0.value, isEnabled: true) })
    }

    /// 경로의 `?` 뒤 쿼리 항목(퍼센트 디코딩, `+`는 그대로 — URLComponents.queryItems와 같은 규칙). 값이 없으면 "".
    private static func queryItems(_ path: String) -> [(key: String, value: String)] {
        guard let q = path.firstIndex(of: "?") else { return [] }
        return path[path.index(after: q)...].split(separator: "&").map { pair in
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let decode = { (s: Substring) in s.removingPercentEncoding ?? String(s) }
            return (decode(kv[0]), kv.count > 1 ? decode(kv[1]) : "")
        }
    }

    /// Test your Rule용: 메서드는 보지 않고 URL 한 줄만 비교한다. scheme이 없으면 https로 본다.
    public func matches(sampleURL: String) -> Bool {
        let line = sampleURL.trimmingCharacters(in: .whitespaces)
        guard let c = URLComponents(string: line.contains("://") ? line : "https://" + line),
              let scheme = c.scheme?.lowercased(), let host = c.host, !host.isEmpty else { return false }
        var path = c.percentEncodedPath.isEmpty ? "/" : c.percentEncodedPath
        if let q = c.percentEncodedQuery { path += "?" + q }
        var rule = self
        rule.methods = .any
        return rule.matches(FlowRequest(
            method: "GET", scheme: scheme, host: host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
            port: c.port ?? (scheme == "http" ? 80 : 443), path: path, headers: [], body: Data()))
    }

    /// 정규식 컴파일 실패 문구. 와일드카드 모드나 정상 정규식이면 nil.
    public var validationError: String? {
        guard mode == .regex else { return nil }
        return compiled() == nil ? "정규식이 올바르지 않습니다" : nil
    }

    /// 자동 복호화용 호스트 패턴. 정규식·http 패턴·와일드카드뿐인 호스트는 nil.
    public var hostPattern: String? {
        guard mode == .wildcard else { return nil }
        var rest = Substring(url)
        if let (scheme, after) = Self.splitScheme(url) {
            if scheme.lowercased() == "http" { return nil }
            rest = after
        }
        var host = rest.prefix { $0 != "/" }
        if host.hasPrefix("["), let close = host.firstIndex(of: "]") {
            host = host[...close]
        } else if let colon = host.firstIndex(of: ":") {
            host = host[..<colon]
        }
        let lower = host.lowercased()
        return lower.allSatisfy({ $0 == "*" || $0 == "?" }) ? nil : lower
    }

    /// `?` 뒤에 `=`나 `*`가 오면 쿼리용 패턴으로 본다(편집기 안내용).
    public var hasQueryLikePattern: Bool {
        url.range(of: #"\?[^/]*[=*]"#, options: .regularExpression) != nil
    }

    public static func urlString(_ request: FlowRequest, includeQuery: Bool) -> String {
        let isDefault = (request.scheme == "http" && request.port == 80) || (request.scheme == "https" && request.port == 443)
        let host = request.host.contains(":") ? "[\(request.host)]" : request.host
        var path = request.path
        if !includeQuery, let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        return "\(request.scheme)://\(host)\(isDefault ? "" : ":\(request.port)")\(path)"
    }

    // MARK: - 컴파일

    private func compiled() -> NSRegularExpression? {
        let body: String
        var options: NSRegularExpression.Options = []
        switch mode {
        case .regex:
            body = url
        case .wildcard:
            body = wildcardBody()
            options = .caseInsensitive
        }
        return Self.cache(pattern: "^(?:\(body))$", options: options, key: "\(mode.rawValue):\(body)")
    }

    /// `://`는 앞 글자가 scheme 모양(`/`·`.` 없음)일 때만 구분자로 본다. 쿼리 안의 URL은 제외.
    private static func splitScheme(_ url: String) -> (scheme: Substring, rest: Substring)? {
        guard let r = url.range(of: "://") else { return nil }
        let scheme = url[..<r.lowerBound]
        guard scheme.range(of: #"^[A-Za-z*?][A-Za-z0-9+.*?-]*$"#, options: .regularExpression) != nil else { return nil }
        return (scheme, url[r.upperBound...])
    }

    private func wildcardBody() -> String {
        let split = Self.splitScheme(url)
        var out = (split != nil ? "" : "[a-z][a-z0-9+.-]*://") + Self.wildcardRegex(url)
        let afterScheme = split?.rest ?? Substring(url)
        if !afterScheme.contains("/") || includeSubpaths { out += "(/.*)?" }
        return out
    }

    /// `*` = 0자 이상, `?` = 1자, 나머지는 리터럴.
    private static func wildcardRegex(_ s: String) -> String {
        s.map { ch in
            switch ch {
            case "*": ".*"
            case "?": "."
            default: NSRegularExpression.escapedPattern(for: String(ch))
            }
        }.joined()
    }

    private static let regexCache = Mutex<[String: NSRegularExpression]>([:])

    private static func cache(pattern: String, options: NSRegularExpression.Options, key: String) -> NSRegularExpression? {
        if let hit = regexCache.withLock({ $0[key] }) { return hit }
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        regexCache.withLock { $0[key] = re }
        return re
    }
}
