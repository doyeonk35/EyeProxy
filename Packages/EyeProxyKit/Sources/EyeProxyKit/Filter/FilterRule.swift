import EyeProxyCore
import Foundation

/// 필터 규칙의 키(Proxyman 필터 막대 메뉴와 같은 이름·순서, 스펙 §4).
public enum FilterKey: String, CaseIterable, Codable, Sendable {
    case url = "URL", host = "Host", queryString = "Query String"
    case requestHeader = "Request Header", responseHeader = "Response Header"
    case requestBody = "Request Body", responseBody = "Response Body"
    case method = "Method", statusCode = "Status Code", client = "Client", ipAddress = "IP Address"
    case comment = "Comment", color = "Color", duration = "Duration (ms)"
    case requestBodySize = "Request Body Size (KB)", responseBodySize = "Response Body Size (KB)"

    /// `<`·`>=`를 쓸 수 있는 숫자 키.
    public var isNumeric: Bool { [.statusCode, .duration, .requestBodySize, .responseBodySize].contains(self) }
}

/// 필터 규칙의 매칭 방식(스펙 §4). 텍스트 매칭은 모두 대소문자를 무시한다.
public enum FilterMatch: String, CaseIterable, Codable, Sendable {
    case contains = "Contains", notContains = "Not Contains", startWith = "Start With", endWith = "End With"
    case equal = "Equal", notEqual = "Not Equal", lessThan = "<", greaterOrEqual = ">="
    case matchWildcard = "Match Wildcard", notMatchWildcard = "Not Match Wildcard"
    case matchRegex = "Match Regex", notMatchRegex = "Not Match Regex"

    /// 숫자 키에서만 뜻이 있다. 숫자 키가 아니면 맞는 흐름이 없다.
    public var isNumericOnly: Bool { self == .lessThan || self == .greaterOrEqual }
    var isNegated: Bool { [.notContains, .notEqual, .notMatchWildcard, .notMatchRegex].contains(self) }
}

/// 필터 막대 한 줄. `matches`는 켜짐 여부를 보지 않는다 — 켜짐·빈 검색어는 `FlowFilter`가 거른다.
public struct FilterRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var isEnabled: Bool
    public var key: FilterKey
    public var match: FilterMatch
    public var text: String

    public init(id: UUID = UUID(), isEnabled: Bool = true, key: FilterKey = .url, match: FilterMatch = .contains, text: String = "") {
        self.id = id
        self.isEnabled = isEnabled
        self.key = key
        self.match = match
        self.text = text
    }

    /// 본문을 풀어야 하는 규칙. 앱은 이런 규칙이 켜져 있으면 메인 밖에서 거른다.
    public var needsBody: Bool { key == .requestBody || key == .responseBody }

    /// 정규식이 잘못됐다(표시용). 이 규칙은 무시된다.
    public var isInvalid: Bool { (match == .matchRegex || match == .notMatchRegex) && regex == nil }

    /// 실제로 거르는 규칙: 켜져 있고, 검색어가 있고, 정규식이 올바르다.
    public var isActive: Bool { isEnabled && !text.isEmpty && !isInvalid }

    public func matches(_ row: FilterSubject) -> Bool {
        if match.isNumericOnly {
            guard key.isNumeric, let n = row.numericValue(for: key), let t = Double(text.trimmingCharacters(in: .whitespaces)) else { return false }
            return match == .lessThan ? n < t : n >= t
        }
        let s = row.value(for: key)
        // NSString 검색: 1 MB 본문에서 String.range(of:)보다 수십 배 빠르다.
        func found(_ options: NSString.CompareOptions) -> Bool { (s as NSString).range(of: text, options: options.union(.caseInsensitive)).location != NSNotFound }
        let hit: Bool
        switch match {
        case .contains, .notContains: hit = found([])
        case .startWith: hit = found(.anchored)
        case .endWith: hit = found([.anchored, .backwards])
        case .equal, .notEqual: hit = s.caseInsensitiveCompare(text) == .orderedSame
        case .matchWildcard, .notMatchWildcard, .matchRegex, .notMatchRegex:
            guard let regex else { return true }
            hit = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        case .lessThan, .greaterOrEqual: return false  // 위에서 처리했다.
        }
        return match.isNegated ? !hit : hit
    }

    /// Wildcard(`*`·`?`, 전체 일치)와 Regex(부분 일치)를 대소문자 무시 정규식으로. 그 밖의 매칭이나 잘못된 패턴은 nil.
    private var regex: NSRegularExpression? {
        let pattern: String
        switch match {
        case .matchRegex, .notMatchRegex: pattern = text
        case .matchWildcard, .notMatchWildcard:
            pattern = "(?s)^" + NSRegularExpression.escapedPattern(for: text)
                .replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".") + "$"
        default: return nil
        }
        if let cached = Self.regexCache.object(forKey: pattern as NSString) { return cached }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        Self.regexCache.setObject(compiled, forKey: pattern as NSString)
        return compiled
    }

    /// 흐름마다 다시 컴파일하지 않도록. NSCache·NSRegularExpression은 스레드 안전하다.
    nonisolated(unsafe) private static let regexCache = NSCache<NSString, NSRegularExpression>()
}

/// 규칙이 보는 흐름 한 건의 값들. 본문은 본문 키를 평가할 때만 (압축이면 풀어서) UTF-8로 읽는다.
public struct FilterSubject: Sendable {
    public let flow: Flow
    public let number: Int
    public let comment: String?
    public let highlight: FlowHighlight?
    /// 목록 Client 열과 같은 이름(프로세스·기기).
    public let client: String

    public init(flow: Flow, number: Int = 0, comment: String? = nil, highlight: FlowHighlight? = nil, client: String = "") {
        self.flow = flow
        self.number = number
        self.comment = comment
        self.highlight = highlight
        self.client = client
    }

    /// 텍스트 매칭이 보는 값. 없으면 "".
    public func value(for key: FilterKey) -> String {
        let request = flow.request
        switch key {
        case .url: return request.url
        case .host: return request.host
        case .queryString: return request.path.firstIndex(of: "?").map { String(request.path[request.path.index(after: $0)...]) } ?? ""
        case .requestHeader: return Self.lines(request.headers)
        case .responseHeader: return Self.lines(flow.response?.headers ?? [])
        case .requestBody: return Self.text(request.body, encoding: request.header("Content-Encoding"))
        case .responseBody: return flow.response.map { Self.text($0.body, encoding: $0.header("Content-Encoding")) } ?? ""
        case .method: return request.method
        case .client: return client
        case .ipAddress: return flow.clientAddress
        case .comment: return comment ?? ""
        case .color: return highlight?.color?.rawValue ?? ""
        case .statusCode, .duration, .requestBodySize, .responseBodySize:
            return numericValue(for: key).map { $0.rounded() == $0 ? String(Int($0)) : String($0) } ?? ""
        }
    }

    /// 숫자 키의 값(Status Code, Duration ms, 본문 KB). 응답·완료 전이거나 숫자 키가 아니면 nil.
    public func numericValue(for key: FilterKey) -> Double? {
        switch key {
        case .statusCode: return flow.response.map { Double($0.status) }
        case .duration: return flow.completedAt.map { ($0.timeIntervalSince(flow.startedAt) * 1000).rounded() }
        case .requestBodySize: return Double(flow.request.body.count) / 1024
        case .responseBodySize: return flow.response.map { Double($0.body.count) / 1024 }
        default: return nil
        }
    }

    private static func lines(_ headers: [HTTPHeader]) -> String {
        headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
    }

    private static func text(_ body: Data, encoding: String?) -> String {
        String(decoding: BodyDecoder.decompressed(body: body, contentEncoding: encoding) ?? body, as: UTF8.self)
    }
}
