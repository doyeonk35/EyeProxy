import EyeProxyCore
import Foundation

public enum CookieParser {
    /// "a=1; b=x=y" → [a:1, b:x=y]. "=" 없는 조각은 value "", 빈 조각은 무시.
    public static func requestCookies(_ cookieHeader: String) -> [HTTPHeader] {
        cookieHeader.split(separator: ";").compactMap { piece in
            let t = piece.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : pair(t, suffix: "")
        }
    }

    /// 각 Set-Cookie의 첫 name=value, 나머지 속성은 value 뒤에 "; Path=/; HttpOnly"로 그대로 붙인다.
    public static func responseCookies(_ setCookieHeaders: [String]) -> [HTTPHeader] {
        setCookieHeaders.compactMap { h in
            let t = h.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            let parts = t.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            let rest = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            return pair(parts[0].trimmingCharacters(in: .whitespaces), suffix: rest.isEmpty ? "" : "; " + rest)
        }
    }

    private static func pair(_ s: String, suffix: String) -> HTTPHeader {
        guard let eq = s.firstIndex(of: "=") else { return HTTPHeader(name: s, value: suffix) }
        return HTTPHeader(name: String(s[..<eq]), value: String(s[s.index(after: eq)...]) + suffix)
    }
}
