import Foundation

/// 호스트 패턴 모음. `*` = 임의 문자열(빈 문자열 포함), `?` = 정확히 한 글자. 대소문자 무시.
public struct HostPatternSet: Sendable {
    private let exact: Set<String>
    private let regex: NSRegularExpression?

    public init(_ patterns: [String]) {
        var exact = Set<String>(), wild: [String] = []
        for p in patterns {
            if p.contains("*") || p.contains("?") {
                let body = p.map { c -> String in
                    switch c {
                    case "*": ".*"
                    case "?": "."
                    default: NSRegularExpression.escapedPattern(for: String(c))
                    }
                }.joined()
                wild.append("(?:\(body))")
            } else {
                exact.insert(p.lowercased())
            }
        }
        self.exact = exact
        regex = wild.isEmpty ? nil : try? NSRegularExpression(pattern: "^(?:\(wild.joined(separator: "|")))$", options: .caseInsensitive)
    }

    public var isEmpty: Bool { exact.isEmpty && regex == nil }

    public func matches(_ host: String) -> Bool {
        if exact.contains(host.lowercased()) { return true }
        return regex?.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil
    }
}
