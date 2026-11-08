import EyeProxyCore
import Foundation
import Synchronization

public enum MatchMode: String, Codable, Sendable {
    case wildcard = "useWildcard"
    case regex = "useRegex"
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
    public var ignoreQuery: Bool
    public var graphQLQueryName: String?

    public init(
        url: String = "", mode: MatchMode = .wildcard, methods: MethodMatch = .any,
        includeSubpaths: Bool = false, ignoreQuery: Bool = true, graphQLQueryName: String? = nil
    ) {
        self.url = url
        self.mode = mode
        self.methods = methods
        self.includeSubpaths = includeSubpaths
        self.ignoreQuery = ignoreQuery
        self.graphQLQueryName = graphQLQueryName
    }

    public func matches(_ request: FlowRequest) -> Bool {
        if case .exact(let list) = methods,
           !list.contains(where: { $0.caseInsensitiveCompare(request.method) == .orderedSame }) { return false }
        guard let regex = compiled() else { return false }
        let target = Self.urlString(request, includeQuery: !ignoreQuery)
        return regex.firstMatch(in: target, range: NSRange(target.startIndex..., in: target)) != nil
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
        var out = split != nil ? "" : "[a-z][a-z0-9+.-]*://"
        for ch in url {
            switch ch {
            case "*": out += ".*"
            case "?": out += "."
            default: out += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        let afterScheme = split?.rest ?? Substring(url)
        if !afterScheme.contains("/") || includeSubpaths { out += "(/.*)?" }
        return out
    }

    private static let regexCache = Mutex<[String: NSRegularExpression]>([:])

    private static func cache(pattern: String, options: NSRegularExpression.Options, key: String) -> NSRegularExpression? {
        if let hit = regexCache.withLock({ $0[key] }) { return hit }
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        regexCache.withLock { $0[key] = re }
        return re
    }
}
