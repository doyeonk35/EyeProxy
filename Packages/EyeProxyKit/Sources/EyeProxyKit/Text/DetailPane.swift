import EyeProxyCore
import Foundation

/// 상세 요청·응답 패널 탭(스펙 §7). 이름은 Proxyman과 같은 영어.
public enum DetailTab: String, CaseIterable, Sendable {
    case header = "Header", query = "Query", body = "Body", form = "Form", cookies = "Cookies", auth = "Auth"
    case setCookie = "Set-Cookie", raw = "Raw", summary = "Summary", treeview = "Treeview", m3u8 = "M3U8", json = "JSON"

    public var title: String { rawValue }
    /// 이름·값 표 탭(≡ 거르기를 쓰는 탭).
    public var isTable: Bool { [.header, .query, .form, .cookies, .auth, .setCookie, .summary].contains(self) }
}

/// 탭 묶음: `[구분선 앞, 구분선 뒤]`. 괄호 탭(Form·Cookies·Auth·Set-Cookie)은 내용이 있을 때만, M3U8은 재생목록일 때만.
public enum DetailTabs {
    public static func request(_ r: FlowRequest, isPlaylist: Bool) -> [[DetailTab]] {
        var first: [DetailTab] = [.header, .query, .body]
        if !r.body.isEmpty, FormFields.isForm(r.header("Content-Type")) { first.append(.form) }
        if !(r.header("Cookie") ?? "").trimmingCharacters(in: .whitespaces).isEmpty { first.append(.cookies) }
        if r.header("Authorization") != nil { first.append(.auth) }
        first.append(.raw)
        return [first, [.summary, .treeview] + (isPlaylist ? [.m3u8] : []) + [.json]]
    }

    public static func response(_ r: FlowResponse, isPlaylist: Bool) -> [[DetailTab]] {
        let setCookie = r.headers.contains { $0.name.caseInsensitiveCompare("Set-Cookie") == .orderedSame }
        return [[.header, .body] + (setCookie ? [.setCookie] : []) + [.raw], [.treeview] + (isPlaylist ? [.m3u8] : []) + [.json]]
    }

    /// 마지막으로 고른 탭이 이 흐름에 없으면 Header.
    public static func shown(_ chosen: DetailTab, in tabs: [[DetailTab]]) -> DetailTab {
        tabs.contains { $0.contains(chosen) } ? chosen : .header
    }
}

/// 상세 머리 URL 색 구간: 스킴 회색·호스트 파랑·(기본 아닌) 포트 회색·경로와 쿼리 초록. CONNECT는 `host:port`만.
public struct URLParts: Equatable, Sendable {
    public let scheme: String, host: String, port: String, rest: String

    public init(scheme: String, host: String, port: String, rest: String) {
        (self.scheme, self.host, self.port, self.rest) = (scheme, host, port, rest)
    }

    public init(_ r: FlowRequest) {
        if r.method.uppercased() == "CONNECT" {
            self.init(scheme: "", host: r.host, port: ":\(r.port)", rest: "")
            return
        }
        let isDefault = (["http", "ws"].contains(r.scheme) && r.port == 80) || (["https", "wss"].contains(r.scheme) && r.port == 443)
        self.init(scheme: "\(r.scheme)://", host: r.host, port: isDefault ? "" : ":\(r.port)", rest: r.path)
    }
}

/// 패널 표 거르기 옵션(`⋯` 메뉴): Case Insensitive(기본)/Sensitive, Text(기본)/Regular Expression. 이름 또는 값에서 찾는다.
public struct TableFilter: Equatable, Sendable {
    public var caseSensitive: Bool
    public var regex: Bool

    public init(caseSensitive: Bool = false, regex: Bool = false) {
        self.caseSensitive = caseSensitive
        self.regex = regex
    }

    /// 보일 행 인덱스. 빈 검색어면 전부, 정규식이 틀리면 nil.
    public func indices(of rows: [HTTPHeader], query: String) -> [Int]? {
        if query.isEmpty { return Array(rows.indices) }
        let hit: (String) -> Bool
        if regex {
            guard let re = try? NSRegularExpression(pattern: query, options: caseSensitive ? [] : .caseInsensitive) else { return nil }
            hit = { re.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        } else if caseSensitive {
            hit = { $0.contains(query) }
        } else {
            hit = { $0.localizedCaseInsensitiveContains(query) }
        }
        return rows.indices.filter { hit(rows[$0].name) || hit(rows[$0].value) }
    }
}

/// Form 탭: form-urlencoded·multipart 요청 본문의 필드. 파일 파트는 `파일명 (크기)`.
public enum FormFields {
    public static func isForm(_ contentType: String?) -> Bool {
        let t = mediaType(contentType)
        return t == "application/x-www-form-urlencoded" || t == "multipart/form-data"
    }

    public static func parse(body: Data, contentType: String?) -> [HTTPHeader] {
        switch mediaType(contentType) {
        case "application/x-www-form-urlencoded":
            return String(decoding: body, as: UTF8.self).split(separator: "&").map { pair in
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map {
                    let s = $0.replacingOccurrences(of: "+", with: " ")
                    return s.removingPercentEncoding ?? s
                }
                return HTTPHeader(name: kv[0], value: kv.count > 1 ? kv[1] : "")
            }
        case "multipart/form-data":
            guard let boundary = parameters(contentType ?? "")["boundary"], !boundary.isEmpty else { return [] }
            return multipart(body, boundary: boundary)
        default:
            return []
        }
    }

    private static func mediaType(_ contentType: String?) -> String {
        (contentType ?? "").split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
    }

    /// `a=1; b="x"` → [a: 1, b: x] (키는 소문자).
    private static func parameters(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for p in s.split(separator: ";") {
            let kv = p.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            out[kv[0].lowercased()] = kv[1].count >= 2 && kv[1].hasPrefix("\"") && kv[1].hasSuffix("\"") ? String(kv[1].dropFirst().dropLast()) : kv[1]
        }
        return out
    }

    private static func multipart(_ body: Data, boundary: String) -> [HTTPHeader] {
        let delimiter = Data("--\(boundary)".utf8), crlf = Data("\r\n".utf8), blank = Data("\r\n\r\n".utf8)
        var cuts: [Range<Data.Index>] = []
        var from = body.startIndex
        while let r = body.range(of: delimiter, in: from..<body.endIndex) { cuts.append(r); from = r.upperBound }
        return zip(cuts, cuts.dropFirst()).compactMap { a, b in
            let part = body[a.upperBound..<b.lowerBound]
            guard let sep = part.range(of: blank) else { return nil }
            let head = String(decoding: part[..<sep.lowerBound], as: UTF8.self)
            var value = part[sep.upperBound...]
            if value.suffix(2) == crlf { value = value.dropLast(2) }
            let disposition = head.components(separatedBy: "\r\n")
                .first { $0.lowercased().hasPrefix("content-disposition:") }.map(parameters) ?? [:]
            let name = disposition["name"] ?? ""
            if let file = disposition["filename"] { return HTTPHeader(name: name, value: "\(file) (\(ByteSize.format(value.count)))") }
            return HTTPHeader(name: name, value: String(decoding: value, as: UTF8.self))
        }
    }
}

/// Auth 탭: Authorization 헤더. Basic은 사용자·비밀번호로 풀고, 그 밖은 방식·토큰.
public enum AuthFields {
    public static func parse(_ authorization: String) -> [HTTPHeader] {
        let parts = authorization.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return [HTTPHeader(name: "Token", value: authorization)] }
        let (type, credential) = (String(parts[0]), parts[1].trimmingCharacters(in: .whitespaces))
        if type.lowercased() == "basic", let d = Data(base64Encoded: credential), let s = String(data: d, encoding: .utf8),
           let colon = s.firstIndex(of: ":") {
            return [HTTPHeader(name: "Type", value: type), HTTPHeader(name: "Username", value: String(s[..<colon])),
                    HTTPHeader(name: "Password", value: String(s[s.index(after: colon)...]))]
        }
        return [HTTPHeader(name: "Type", value: type), HTTPHeader(name: "Token", value: credential)]
    }
}
