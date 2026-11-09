import EyeProxyCore
import Foundation

/// 내보낼 흐름 하나와 목록에만 있는 값(안정 번호·코멘트·Highlight·클라이언트 이름).
public struct ExportItem: Sendable {
    public var flow: Flow
    public var number: Int
    public var comment: String?
    public var highlight: FlowHighlight?
    public var client: String?

    public init(flow: Flow, number: Int, comment: String? = nil, highlight: FlowHighlight? = nil, client: String? = nil) {
        self.flow = flow
        self.number = number
        self.comment = comment
        self.highlight = highlight
        self.client = client
    }
}

/// HAR 1.2·CSV 내보내기(순수 함수). 앱·CLI·MCP가 같이 쓴다.
public enum FlowExport {
    /// HAR 1.2 JSON. 키 정렬·슬래시 비이스케이프로 같은 입력은 같은 바이트(diff 친화).
    public static func har(_ items: [ExportItem], creator: String = "Prog", version: String) -> Data {
        let file = HARFile(log: HARLog(version: "1.2", creator: HARCreator(name: creator, version: version), entries: items.map(HAREntry.init)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        // 문자열·정수·Bool만 담은 구조체라 인코딩이 실패할 수 없다.
        return try! encoder.encode(file)
    }

    /// RFC 4180 CSV(헤더 한 줄, 줄 끝 CRLF). 본문은 넣지 않고, 모르는 시간·크기 칸은 비운다.
    public static func csv(_ items: [ExportItem]) -> String {
        let header = ["ID", "Method", "URL", "Status", "Code", "Client", "Start", "Duration (ms)",
                      "Request Size", "Response Size", "SSL", "Edited", "Highlight", "Comment"]
        let rows = items.map { item in
            let row = FlowRow(flow: item.flow, number: item.number)
            let response = item.flow.response
            return [String(item.number), row.method, row.url, String(describing: row.state).capitalized,
                    response.map { String($0.status) } ?? "", item.client ?? "", timestamp(row.startedAt),
                    row.durationMS < 0 ? "" : String(row.durationMS), String(row.requestSize),
                    response.map { String($0.body.count) } ?? "", row.isSSL ? "Yes" : "No", row.edited,
                    // 색 raw 값, 취소선이면 "+strikethrough"(색 없으면 "strikethrough")
                    [item.highlight?.color?.rawValue, item.highlight?.strikethrough == true ? "strikethrough" : nil]
                        .compactMap { $0 }.joined(separator: "+"),
                    item.comment ?? ""]
        }
        return ([header] + rows).map { $0.map(csvField).joined(separator: ",") + "\r\n" }.joined()
    }

    /// ISO 8601, 밀리초, UTC(`2026-11-09T01:02:03.456Z`).
    static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    private static func csvField(_ s: String) -> String {
        // Character 단위면 "\r\n"이 한 글자라 "\n"에 안 걸리므로 스칼라로 본다.
        guard s.unicodeScalars.contains(where: { ",\"\r\n".unicodeScalars.contains($0) }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - HAR 1.2 모델 (nil인 선택 필드는 키째 생략된다)

struct HARFile: Codable { var log: HARLog }
struct HARLog: Codable { var version: String; var creator: HARCreator; var entries: [HAREntry] }
struct HARCreator: Codable { var name: String; var version: String }
struct HARNameValue: Codable { var name: String; var value: String }

/// request.postData(size 없음)와 response.content(size 있음) 공용. text는 Content-Encoding을 푼 본문.
struct HARBody: Codable {
    var size: Int?
    /// 푼 크기 − 기록된 크기. 풀어서 바이트가 바뀐 응답에만.
    var compression: Int?
    var mimeType: String
    var text: String
    /// 바이너리(UTF-8로 안 읽히는 본문)면 "base64"
    var encoding: String?

    /// Content-Encoding대로 풀어(실패하면 기록 그대로) 담고, 바이트가 바뀌었으면 기록된 원본의 base64를 돌려준다.
    static func make(_ recorded: Data, contentEncoding: String?, mimeType: String?, sized: Bool) -> (body: HARBody, raw: String?) {
        let decoded = BodyDecoder.decompressed(body: recorded, contentEncoding: contentEncoding) ?? recorded
        let changed = decoded != recorded
        var body = HARBody(size: sized ? decoded.count : nil, mimeType: mimeType, data: decoded)
        if sized && changed { body.compression = decoded.count - recorded.count }
        return (body, changed ? recorded.base64EncodedString() : nil)
    }

    init(size: Int?, mimeType: String?, data: Data) {
        self.size = size
        self.mimeType = mimeType ?? ""
        // String(data:encoding:)는 BOM을 떼어 바이트 왕복이 깨지므로 엄격한 검증 디코딩을 쓴다.
        if let s = String(validating: data, as: UTF8.self) {
            text = s
        } else {
            text = data.base64EncodedString()
            encoding = "base64"
        }
    }
}

struct HARRequest: Codable {
    var method: String
    var url: String
    var httpVersion = "HTTP/1.1"
    var cookies: [HARNameValue] = []
    var headers: [HARNameValue]
    var queryString: [HARNameValue]
    var postData: HARBody?
    var headersSize = -1
    var bodySize: Int
}

struct HARResponse: Codable {
    var status: Int
    var statusText: String
    var httpVersion = "HTTP/1.1"
    var cookies: [HARNameValue] = []
    var headers: [HARNameValue]
    var content: HARBody
    var redirectURL: String
    var headersSize = -1
    var bodySize: Int
}

struct HARTimings: Codable { var send = 0; var wait: Int; var receive = 0 }

/// HAR 규칙의 `_` 접두 확장. 값이 없는 선택 필드는 생략.
/// `rawRequestBody`·`rawResponseBody`: 압축을 풀어 text에 담았을 때만 기록된 원본 바이트(base64).
/// `FlowImport.har`는 이 값이 있으면 text 대신 이것을 본문으로 써야 바이트 왕복이 맞는다(헤더의 Content-Encoding은 그대로 둔다).
struct HARProg: Codable {
    var number: Int
    var comment: String?
    var highlight: FlowHighlight?
    var tools: [String]?
    var client: String?
    var isTunnel: Bool
    var isDecrypted: Bool
    var originalURL: String?
    var sentURL: String?
    var error: String?
    var incomplete: Bool?
    var rawRequestBody: String?
    var rawResponseBody: String?
}

struct HAREntry: Codable {
    var startedDateTime: String
    /// ms. 미완료면 0(+ `_prog.incomplete`)
    var time: Int
    var request: HARRequest
    var response: HARResponse
    var cache: [String: String] = [:]
    var timings: HARTimings
    var _prog: HARProg

    init(_ item: ExportItem) {
        let f = item.flow, row = FlowRow(flow: f, number: item.number)
        startedDateTime = FlowExport.timestamp(f.startedAt)
        time = max(row.durationMS, 0)
        timings = HARTimings(wait: time)
        let headers = { (h: [HTTPHeader]) in h.map { HARNameValue(name: $0.name, value: $0.value) } }
        let post = HARBody.make(f.request.body, contentEncoding: f.request.header("Content-Encoding"),
                                mimeType: f.request.header("Content-Type"), sized: false)
        request = HARRequest(
            method: f.request.method, url: f.request.url, headers: headers(f.request.headers),
            queryString: Self.queryString(f.request.url),
            postData: f.request.body.isEmpty ? nil : post.body, bodySize: f.request.body.count)
        let r = f.response
        let content = HARBody.make(r?.body ?? Data(), contentEncoding: r?.header("Content-Encoding"), mimeType: r?.header("Content-Type"), sized: true)
        response = HARResponse(
            status: r?.status ?? 0, statusText: r?.reason ?? "", headers: headers(r?.headers ?? []),
            content: content.body, redirectURL: r?.header("Location") ?? "", bodySize: r?.body.count ?? -1)
        _prog = HARProg(
            number: item.number, comment: item.comment, highlight: item.highlight,
            tools: row.editedMarks.isEmpty ? nil : row.editedMarks.map(\.rawValue), client: item.client,
            isTunnel: f.isTunnel, isDecrypted: f.isDecrypted,
            originalURL: f.annotations.lazy.compactMap { if case .originalURL(let u) = $0 { u } else { nil } }.first,
            sentURL: f.annotations.lazy.compactMap { if case .sentURL(let u) = $0 { u } else { nil } }.first,
            error: f.error, incomplete: f.completedAt == nil ? true : nil,
            rawRequestBody: post.raw, rawResponseBody: content.raw)
    }

    /// `?` 뒤(`#` 앞)를 `&`·첫 `=`로 나눠 퍼센트 디코딩(실패하면 원문). 반복 키는 순서대로, `+`는 공백으로 바꾸지 않는다.
    /// URLComponents는 쓰지 않는다: macOS 15에서 날 공백·`|`·`{}`가 섞인 URL도 nil 없이 받아들이지만 그때는 `%ED%95%9C` 같은 유효한 이스케이프를 풀지 않는다.
    static func queryString(_ url: String) -> [HARNameValue] {
        guard let q = url.split(separator: "?", maxSplits: 1).dropFirst().first?.split(separator: "#", omittingEmptySubsequences: false).first
        else { return [] }
        func decode(_ s: Substring) -> String { s.removingPercentEncoding ?? String(s) }
        return q.split(separator: "&").map {
            let kv = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return HARNameValue(name: decode(kv[0]), value: kv.count > 1 ? decode(kv[1]) : "")
        }
    }
}
