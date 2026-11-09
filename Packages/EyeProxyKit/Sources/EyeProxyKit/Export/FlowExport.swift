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

/// request.postData(size 없음)와 response.content(size 있음) 공용.
struct HARBody: Codable {
    var size: Int?
    var mimeType: String
    var text: String
    /// 바이너리(UTF-8로 안 읽히는 본문)면 "base64"
    var encoding: String?

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
        request = HARRequest(
            method: f.request.method, url: f.request.url, headers: headers(f.request.headers),
            queryString: URLComponents(string: f.request.url)?.queryItems?.map { HARNameValue(name: $0.name, value: $0.value ?? "") } ?? [],
            postData: f.request.body.isEmpty ? nil : HARBody(size: nil, mimeType: f.request.header("Content-Type"), data: f.request.body),
            bodySize: f.request.body.count)
        let r = f.response
        response = HARResponse(
            status: r?.status ?? 0, statusText: r?.reason ?? "", headers: headers(r?.headers ?? []),
            content: HARBody(size: r?.body.count ?? 0, mimeType: r?.header("Content-Type"), data: r?.body ?? Data()),
            redirectURL: r?.header("Location") ?? "", bodySize: r?.body.count ?? -1)
        _prog = HARProg(
            number: item.number, comment: item.comment, highlight: item.highlight,
            tools: row.editedMarks.isEmpty ? nil : row.editedMarks.map(\.rawValue), client: item.client,
            isTunnel: f.isTunnel, isDecrypted: f.isDecrypted,
            originalURL: f.annotations.lazy.compactMap { if case .originalURL(let u) = $0 { u } else { nil } }.first,
            sentURL: f.annotations.lazy.compactMap { if case .sentURL(let u) = $0 { u } else { nil } }.first,
            error: f.error, incomplete: f.completedAt == nil ? true : nil)
    }
}
