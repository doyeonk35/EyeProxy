import EyeProxyCore
import Foundation

/// 필터 바의 프로토콜 묶음. 순서가 칩 순서다.
public enum FlowProtocol: String, CaseIterable, Sendable {
    case http = "HTTP", https = "HTTPS"

    /// scheme이 https면 HTTPS(복호화 안 한 CONNECT 터널 포함), 아니면 HTTP.
    public static func of(_ flow: Flow) -> FlowProtocol {
        flow.request.scheme.lowercased() == "https" ? .https : .http
    }
}

/// 필터 바의 콘텐츠 종류 묶음. 순서가 칩 순서다.
public enum ContentKind: String, CaseIterable, Sendable {
    case json = "JSON", form = "Form", xml = "XML", js = "JS", css = "CSS", graphql = "GraphQL", document = "Document", media = "Media", other = "Other"

    /// 응답 Content-Type(응답이 없으면 요청 Content-Type)으로 분류한다. 처음 맞는 규칙이 이긴다.
    public static func of(_ flow: Flow) -> ContentKind {
        let requestType = mediaType(flow.request.header("Content-Type"))
        let path = flow.request.path.split(separator: "?").first.map { $0.lowercased() } ?? ""
        if path.contains("graphql") || requestType == "application/graphql" { return .graphql }
        if requestType == "application/x-www-form-urlencoded" || requestType == "multipart/form-data" { return .form }
        guard let type = flow.response.map({ mediaType($0.header("Content-Type")) }) ?? requestType else { return .other }
        if type.contains("json") { return .json }
        if type.contains("xml") { return .xml }
        if type.contains("javascript") || type.contains("ecmascript") { return .js }
        if type == "text/css" { return .css }
        if ["text/html", "text/plain", "application/pdf", "text/markdown", "text/csv"].contains(type) { return .document }
        if ["image/", "video/", "audio/", "font/", "application/font-", "application/x-font-"].contains(where: type.hasPrefix)
            || ["application/vnd.apple.mpegurl", "application/x-mpegurl"].contains(type) { return .media }
        return .other
    }

    /// `;` 앞 미디어 타입을 소문자·공백 제거로. 없으면 nil.
    private static func mediaType(_ value: String?) -> String? {
        value?.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }
}
