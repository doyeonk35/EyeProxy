import Foundation

public struct SSLProxyingPolicy: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    /// "api.example.com", "*.example.com", "*" — `*`는 임의 문자열, `?`는 한 글자, 비교는 대소문자 무시.
    public var patterns: [String]

    public init(isEnabled: Bool = true, patterns: [String] = []) {
        self.isEnabled = isEnabled
        self.patterns = patterns
    }

    public func shouldDecrypt(host: String) -> Bool {
        isEnabled && HostPatternSet(patterns).matches(host)
    }
}
