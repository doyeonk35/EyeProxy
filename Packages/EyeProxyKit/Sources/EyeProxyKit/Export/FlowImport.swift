import EyeProxyCore
import Foundation

/// HAR에서 읽은 흐름 하나와 목록에만 있는 값. `number`가 nil이면 앱이 순서대로 매긴다.
public struct ImportedFlow: Sendable {
    public var flow: Flow
    public var number: Int?
    public var comment: String?
    public var highlight: FlowHighlight?
    public var client: String?
}

public enum FlowImportError: Error, Sendable {
    /// JSON이 아니거나 `log.entries`가 없다(짧은 이유).
    case invalidHAR(String)
}

/// HAR 가져오기(순수 함수). 앱·CLI·MCP가 같이 쓴다.
public enum FlowImport {
    /// HAR 1.2 JSON → 흐름. `_prog`(Prog 확장)가 있으면 번호·코멘트·Highlight·도구 표시 등을 복원하고, 없으면(다른 도구의 HAR) 기본값.
    /// 항목별로 관대하게 읽는다: request·method·url이 없는 항목만 건너뛰고, 형식이 틀린 나머지 필드는 기본값.
    /// 번호가 겹치거나 0 이하인 게 하나라도 있으면 번호는 전부 nil.
    public static func har(_ data: Data) throws -> [ImportedFlow] {
        // JSONSerialization은 본문 문자열 첫 BOM을 떼므로 JSONDecoder로 읽는다.
        let file: ImportFile
        do { file = try JSONDecoder().decode(ImportFile.self, from: data) } catch let error as DecodingError {
            throw FlowImportError.invalidHAR(reason(error))
        }
        let entries = file.log.entries.compactMap(\.value)
        if entries.isEmpty && !file.log.entries.isEmpty { throw FlowImportError.invalidHAR("읽을 수 있는 항목이 없습니다") }

        let fractional = ISO8601DateFormatter(), whole = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var last = Date()  // 시각을 못 읽으면 앞 항목의 시작 시각(첫 항목은 가져온 시각)
        var flows = entries.map { e in
            if let s = e.startedDateTime, let d = fractional.date(from: s) ?? whole.date(from: s) { last = d }
            return imported(e, startedAt: last)
        }
        let numbers = flows.compactMap(\.number)
        if Set(numbers).count != numbers.count || numbers.contains(where: { $0 <= 0 }) {
            for i in flows.indices { flows[i].number = nil }
        }
        return flows
    }

    private static func reason(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let c) where c.codingPath.isEmpty: "JSON이 아닙니다"
        case .keyNotFound(let key, let c): "\((c.codingPath + [key]).map(\.stringValue).joined(separator: ".")) 없음"
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
            "\(c.codingPath.map(\.stringValue).joined(separator: ".")) 형식 오류"
        @unknown default: "형식 오류"
        }
    }

    private static func imported(_ e: ImportEntry, startedAt started: Date) -> ImportedFlow {
        let p = e.prog
        let (scheme, host, port, path) = split(e.request.url)
        let request = FlowRequest(method: e.request.method, scheme: scheme, host: host, port: port, path: path,
                                  headers: e.request.headers, body: body(raw: p?.rawRequestBody, e.request.postData))
        // status 0(내보내기의 "응답 없음")이나 response 없음 → 응답 없는 흐름
        let response = e.response.flatMap { r -> FlowResponse? in
            guard let status = r.status, status > 0 else { return nil }
            return FlowResponse(status: status, reason: r.statusText ?? "", headers: r.headers, body: body(raw: p?.rawResponseBody, r.content))
        }
        var flow = Flow(id: FlowID(), clientAddress: "", startedAt: started, request: request, response: response,
                        completedAt: p?.incomplete == true ? nil : started.addingTimeInterval(max(e.time ?? 0, 0) / 1000),
                        error: p?.error, isDecrypted: p?.isDecrypted ?? (scheme == "https"), isTunnel: p?.isTunnel ?? false)
        flow.annotations = (p?.tools ?? []).map { .tool($0) }
            + [p?.originalURL.map { .originalURL($0) }, p?.sentURL.map { .sentURL($0) }].compactMap { $0 }
        return ImportedFlow(flow: flow, number: p?.number, comment: p?.comment, highlight: p?.highlight, client: p?.client)
    }

    /// 기록된 원본(`_prog.raw*Body`)이 있으면 그것, 없으면 text(base64면 풀어서, 모르는 encoding이면 UTF-8).
    private static func body(raw: String?, _ b: ImportBody?) -> Data {
        if let raw, let d = Data(base64Encoded: raw) { return d }
        guard let text = b?.text else { return Data() }
        if b?.encoding == "base64", let d = Data(base64Encoded: text) { return d }
        return Data(text.utf8)
    }

    /// `scheme://host[:port]path`. URLComponents는 날 공백 등이 섞인 기록 URL에서 nil이 될 수 있어 직접 나눈다.
    /// 포트가 없으면 http·ws 80, 그 외 443. IPv6 `[::1]:8080`도.
    private static func split(_ url: String) -> (scheme: String, host: String, port: Int, path: String) {
        let parts = url.components(separatedBy: "://")
        let scheme = parts.count > 1 ? parts[0] : "http"
        let rest = parts.count > 1 ? parts.dropFirst().joined(separator: "://") : url
        let cut = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.endIndex
        var host = String(rest[..<cut]), port = ["http", "ws"].contains(scheme) ? 80 : 443
        if let colon = host.lastIndex(of: ":"), !host.hasSuffix("]"), let p = Int(host[host.index(after: colon)...]) {
            port = p
            host = String(host[..<colon])
        }
        return (scheme, host, port, String(rest[cut...]))
    }
}

// MARK: - 가져오기용 모델 (항목별로 관대하게: 형식이 틀린 선택 필드는 nil, 배열은 원소별로 건너뜀)

private struct HARKey: CodingKey, ExpressibleByStringLiteral {
    let stringValue: String
    init(stringValue: String) { self.stringValue = stringValue }
    init(stringLiteral value: String) { stringValue = value }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

/// 원소 하나를 못 읽어도 배열 전체가 실패하지 않게.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

private extension KeyedDecodingContainer<HARKey> {
    /// 없거나 형식이 틀리면 nil.
    func lenient<T: Decodable>(_ key: HARKey) -> T? { (try? decodeIfPresent(T.self, forKey: key)) ?? nil }
    func list<T: Decodable>(_ key: HARKey) -> [T] { (lenient(key) as [Lossy<T>]?)?.compactMap(\.value) ?? [] }
}

private struct ImportFile: Decodable { var log: ImportLog }
private struct ImportLog: Decodable { var entries: [Lossy<ImportEntry>] }
private struct ImportBody: Decodable { var text: String?; var encoding: String? }

/// 이름 없는 헤더는 버리고(배열에서 건너뜀), 값이 null·문자열 아님이면 "".
private struct ImportHeader: Decodable {
    let header: HTTPHeader
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: HARKey.self)
        header = HTTPHeader(name: try c.decode(String.self, forKey: "name"), value: c.lenient("value") ?? "")
    }
}

private struct ImportRequest: Decodable {
    var method: String, url: String, headers: [HTTPHeader], postData: ImportBody?
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: HARKey.self)
        method = try c.decode(String.self, forKey: "method")
        url = try c.decode(String.self, forKey: "url")
        headers = (c.list("headers") as [ImportHeader]).map(\.header)
        postData = c.lenient("postData")
    }
}

private struct ImportResponse: Decodable {
    var status: Int?, statusText: String?, headers: [HTTPHeader], content: ImportBody?
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: HARKey.self)
        status = c.lenient("status")
        statusText = c.lenient("statusText")
        headers = (c.list("headers") as [ImportHeader]).map(\.header)
        content = c.lenient("content")
    }
}

/// `_prog`를 필드별로: 틀린 필드 하나 때문에 나머지를 잃지 않는다(이전·이후 Prog 모양도).
private struct ImportProg: Decodable {
    var number: Int?, comment: String?, highlight: FlowHighlight?, tools: [String]?, client: String?
    var isTunnel: Bool?, isDecrypted: Bool?, originalURL: String?, sentURL: String?, error: String?, incomplete: Bool?
    var rawRequestBody: String?, rawResponseBody: String?
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: HARKey.self)
        number = c.lenient("number"); comment = c.lenient("comment"); highlight = c.lenient("highlight")
        tools = c.lenient("tools"); client = c.lenient("client")
        isTunnel = c.lenient("isTunnel"); isDecrypted = c.lenient("isDecrypted")
        originalURL = c.lenient("originalURL"); sentURL = c.lenient("sentURL")
        error = c.lenient("error"); incomplete = c.lenient("incomplete")
        rawRequestBody = c.lenient("rawRequestBody"); rawResponseBody = c.lenient("rawResponseBody")
    }
}

private struct ImportEntry: Decodable {
    var startedDateTime: String?
    /// ms. 소수·음수도 온다.
    var time: Double?
    var request: ImportRequest
    var response: ImportResponse?
    var prog: ImportProg?
    /// request(method·url)를 못 읽을 때만 실패 → 그 항목만 건너뛴다.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: HARKey.self)
        request = try c.decode(ImportRequest.self, forKey: "request")
        startedDateTime = c.lenient("startedDateTime")
        time = c.lenient("time")
        response = c.lenient("response")
        prog = c.lenient("_prog")
    }
}
