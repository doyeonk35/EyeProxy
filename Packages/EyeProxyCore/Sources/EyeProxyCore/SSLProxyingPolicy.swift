import Foundation

public struct SSLProxyingPolicy: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    /// "api.tving.com", "*.tving.com", "*" — `*`는 임의 문자열, 비교는 대소문자 무시.
    public var patterns: [String]

    public init(isEnabled: Bool = true, patterns: [String] = []) {
        self.isEnabled = isEnabled
        self.patterns = patterns
    }

    public func shouldDecrypt(host: String) -> Bool {
        guard isEnabled else { return false }
        return patterns.contains { Self.matches(pattern: $0, host: host) }
    }

    private static func matches(pattern: String, host: String) -> Bool {
        let body = pattern.split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: ".*")
        guard let regex = try? NSRegularExpression(pattern: "^\(body)$", options: .caseInsensitive) else { return false }
        return regex.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil
    }
}
