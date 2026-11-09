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
    /// 번호가 겹치거나 0 이하인 게 하나라도 있으면 번호는 전부 nil.
    public static func har(_ data: Data) throws -> [ImportedFlow] {
        // JSONSerialization은 본문 문자열 첫 BOM을 떼므로 JSONDecoder로 읽는다.
        let file: ImportFile
        do { file = try JSONDecoder().decode(ImportFile.self, from: data) } catch let error as DecodingError {
            throw FlowImportError.invalidHAR(reason(error))
        }
        var flows = file.log.entries.map(imported)
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

    private static func imported(_ e: ImportEntry) -> ImportedFlow {
        let p = e._prog
        let started = e.startedDateTime.flatMap(date) ?? Date(timeIntervalSince1970: 0)
        let headers = { (h: [HARNameValue]?) in (h ?? []).map { HTTPHeader(name: $0.name, value: $0.value) } }
        let (scheme, host, port, path) = split(e.request.url)
        let request = FlowRequest(method: e.request.method, scheme: scheme, host: host, port: port, path: path,
                                  headers: headers(e.request.headers), body: body(raw: p?.rawRequestBody, e.request.postData))
        // status 0(내보내기의 "응답 없음")이나 response 없음 → 응답 없는 흐름
        let response = e.response.flatMap { r -> FlowResponse? in
            guard let status = r.status, status > 0 else { return nil }
            return FlowResponse(status: status, reason: r.statusText ?? "", headers: headers(r.headers), body: body(raw: p?.rawResponseBody, r.content))
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

    /// ISO 8601. 소수 초 유무, `Z`·`±hh:mm` 모두.
    private static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// `scheme://host[:port]path`. URLComponents는 날 공백 등이 섞인 기록 URL에서 nil이 될 수 있어 직접 나눈다.
    /// 포트가 없으면 http 80, 그 외 443. IPv6 `[::1]:8080`도.
    private static func split(_ url: String) -> (scheme: String, host: String, port: Int, path: String) {
        let parts = url.components(separatedBy: "://")
        let scheme = parts.count > 1 ? parts[0] : "http"
        let rest = parts.count > 1 ? parts.dropFirst().joined(separator: "://") : url
        let cut = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.endIndex
        var host = String(rest[..<cut]), port = scheme == "http" ? 80 : 443
        if let colon = host.lastIndex(of: ":"), !host.hasSuffix("]"), let p = Int(host[host.index(after: colon)...]) {
            port = p
            host = String(host[..<colon])
        }
        return (scheme, host, port, String(rest[cut...]))
    }
}

// MARK: - 가져오기용 모델 (다른 도구의 HAR도 받도록 HAR 필수 필드 외엔 선택)

private struct ImportFile: Decodable { var log: ImportLog }
private struct ImportLog: Decodable { var entries: [ImportEntry] }
private struct ImportBody: Decodable { var text: String?; var encoding: String? }
private struct ImportRequest: Decodable { var method: String; var url: String; var headers: [HARNameValue]?; var postData: ImportBody? }
private struct ImportResponse: Decodable { var status: Int?; var statusText: String?; var headers: [HARNameValue]?; var content: ImportBody? }

private struct ImportEntry: Decodable {
    var startedDateTime: String?
    /// ms. 소수·음수도 온다.
    var time: Double?
    var request: ImportRequest
    var response: ImportResponse?
    var _prog: HARProg?
}
