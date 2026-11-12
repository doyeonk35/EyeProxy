import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private let t0 = Date(timeIntervalSince1970: 1_794_186_123.25)  // 2026-11-09T01:02:03.250Z

private func flow(_ method: String = "GET", scheme: String = "https", host: String = "api.example.com", port: Int = 443, path: String = "/v1/items",
                  headers: [HTTPHeader] = [], body: Data = Data(), response: FlowResponse? = nil, isTunnel: Bool = false) -> Flow {
    var f = Flow(id: FlowID(), clientAddress: "192.168.0.21", startedAt: t0,
                 request: FlowRequest(method: method, scheme: scheme, host: host, port: port, path: path, headers: headers, body: body),
                 response: response, isDecrypted: scheme == "https" && !isTunnel, isTunnel: isTunnel)
    f.completedAt = t0.addingTimeInterval(0.042)
    return f
}

private func roundTrip(_ items: [ExportItem]) throws -> [ImportedFlow] {
    try FlowImport.har(FlowExport.har(items, version: "1"))
}

private func urls(_ f: Flow) -> (original: String?, sent: String?) {
    (f.annotations.lazy.compactMap { if case .originalURL(let u) = $0 { u } else { nil } }.first,
     f.annotations.lazy.compactMap { if case .sentURL(let u) = $0 { u } else { nil } }.first)
}

@Test func harRoundTripPreservesBinaryAndUTF8Bodies() throws {
    let korean = #"{"msg":"안녕하세요"}"#
    let gz = try gzip(Data("hello hello hello".utf8))
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0xFF, 0x00])
    let ct = { HTTPHeader(name: "Content-Type", value: $0) }
    let flows = [
        // 바이너리: Content-Encoding 없는 gzip 요청 본문, PNG 응답
        flow("POST", headers: [ct("application/octet-stream")], body: gz,
             response: FlowResponse(status: 200, reason: "OK", headers: [ct("image/png")], body: png)),
        // 한글 텍스트(BOM 포함)
        flow("PUT", headers: [ct("application/json")], body: Data(korean.utf8),
             response: FlowResponse(status: 200, reason: "OK", headers: [ct("text/plain; charset=utf-8")], body: Data([0xEF, 0xBB, 0xBF]) + Data(korean.utf8))),
        // gzip으로 인코딩된 한글 JSON: 원본 바이트는 _prog.raw*Body로 돌아온다
        flow("POST", headers: [ct("application/json"), HTTPHeader(name: "Content-Encoding", value: "gzip")], body: try gzip(Data(korean.utf8)),
             response: FlowResponse(status: 200, reason: "OK", headers: [ct("application/json"), HTTPHeader(name: "Content-Encoding", value: "gzip"),
                                                                        HTTPHeader(name: "Set-Cookie", value: "a=1"), HTTPHeader(name: "Set-Cookie", value: "b=2")],
                                    body: try gzip(Data(korean.utf8)))),
    ]
    let imported = try roundTrip(flows.enumerated().map { ExportItem(flow: $1, number: $0 + 1) })
    #expect(imported.count == flows.count)
    for (orig, got) in zip(flows, imported) {
        #expect(got.flow.request.body == orig.request.body)
        #expect(got.flow.response?.body == orig.response?.body)
        #expect(got.flow.request.headers == orig.request.headers)
        #expect(got.flow.response?.headers == orig.response?.headers)
    }
}

@Test func harRoundTripPreservesNumbersCommentsHighlightsTools() throws {
    var edited = flow("POST", path: "/v1/items?q=a%20b&n=2", headers: [HTTPHeader(name: "X-A", value: "1"), HTTPHeader(name: "X-A", value: "2")],
                      body: Data(#"{"a":1}"#.utf8), response: FlowResponse(status: 201, reason: "Created", headers: [], body: Data()))
    edited.annotations = [.tool("Map Remote: R"), .originalURL("https://old.example.com/v1/items"), .tool("Map Local: L")]
    var sent = flow(scheme: "http", host: "example.com", port: 8080, path: "/", response: FlowResponse(status: 304, reason: "Not Modified", headers: [], body: Data()))
    sent.annotations = [.tool("Breakpoint"), .sentURL("https://new.example.com/")]
    var tunnel = flow("CONNECT", host: "example.com", port: 8443, path: "", isTunnel: true)
    tunnel.error = "연결이 끊어졌습니다"
    var pending = flow(host: "example.com")
    pending.completedAt = nil
    let items = [
        ExportItem(flow: edited, number: 7, comment: "메모", highlight: FlowHighlight(color: .red, strikethrough: true), client: "iPhone"),
        ExportItem(flow: sent, number: 2, highlight: FlowHighlight(strikethrough: true)),
        ExportItem(flow: tunnel, number: 12, comment: "터널"),
        ExportItem(flow: pending, number: 3, highlight: FlowHighlight(color: .green), client: "curl"),
    ]
    let imported = try roundTrip(items)
    #expect(imported.count == items.count)
    for (item, got) in zip(items, imported) {
        let o = item.flow, g = got.flow
        #expect(got.number == item.number && got.comment == item.comment && got.highlight == item.highlight && got.client == item.client)
        #expect(g.request.method == o.request.method && g.request.url == o.request.url)
        #expect(g.request.scheme == o.request.scheme && g.request.host == o.request.host && g.request.port == o.request.port && g.request.path == o.request.path)
        #expect(g.request.headers == o.request.headers)
        #expect(g.response?.status == o.response?.status && g.response?.reason == o.response?.reason)
        #expect(FlowRow(flow: g, number: 0).editedMarks == FlowRow(flow: o, number: 0).editedMarks)
        #expect(g.isTunnel == o.isTunnel && g.isDecrypted == o.isDecrypted)
        #expect(urls(g) == urls(o))
        #expect(g.error == o.error)
        #expect((g.completedAt == nil) == (o.completedAt == nil))
        #expect(g.startedAt == o.startedAt)
    }
    #expect(imported[0].flow.completedAt == edited.completedAt)
    #expect(imported[2].flow.response == nil && imported[3].flow.response == nil)
}

@Test func harRoundTripRestoresClientAsAddress() throws {
    let items = [
        ExportItem(flow: flow(), number: 1, client: "iPhone 15"),
        ExportItem(flow: flow(), number: 2, client: ""),
        ExportItem(flow: flow(), number: 3, client: nil),
    ]
    let imported = try roundTrip(items)
    #expect(imported.map(\.flow.clientAddress) == ["iPhone 15", "", ""])
    #expect(imported.map(\.client) == ["iPhone 15", "", nil])
}

@Test func foreignHARWithoutProgExtensionImportsWithDefaults() throws {
    // Chrome DevTools 모양 최소 픽스처: time은 소수, 시각은 오프셋·소수 초 유무가 섞임, 선택 필드 일부 없음
    let har = #"""
    {"log": {"version": "1.2", "creator": {"name": "WebInspector", "version": "537.36"}, "pages": [],
      "entries": [
        {"startedDateTime": "2026-11-09T10:02:03.250+09:00", "time": 12.75,
         "request": {"method": "GET", "url": "https://example.com/a?x=1", "httpVersion": "h2",
                     "headers": [{"name": ":authority", "value": "example.com"}, {"name": "accept", "value": "*/*"}],
                     "queryString": [{"name": "x", "value": "1"}], "cookies": [], "headersSize": -1, "bodySize": 0},
         "response": {"status": 200, "statusText": "", "httpVersion": "h2",
                      "headers": [{"name": "content-encoding", "value": "gzip"}, {"name": "content-type", "value": "application/json"}],
                      "content": {"size": 15, "mimeType": "application/json", "text": "{\"k\":\"한글\"}"},
                      "redirectURL": "", "headersSize": -1, "bodySize": -1, "_transferSize": 120},
         "cache": {}, "timings": {"blocked": 0.5, "dns": -1, "send": 0.1, "wait": 10, "receive": 2.15}, "_initiator": {"type": "script"}},
        {"startedDateTime": "2026-11-09T01:02:04Z", "time": -1,
         "request": {"method": "POST", "url": "http://example.com:8080/upload", "headers": [],
                     "postData": {"mimeType": "application/octet-stream", "text": "AAEC/w==", "encoding": "base64"}},
         "response": {"status": 0, "statusText": "", "headers": [], "content": {"size": 0, "mimeType": "x-unknown"}}},
        {"startedDateTime": "2026-11-09T01:02:05.5Z", "time": 3,
         "request": {"method": "GET", "url": "https://example.com/img", "headers": []},
         "response": {"status": 200, "statusText": "OK", "headers": [],
                      "content": {"mimeType": "image/png", "text": "iVBORw==", "encoding": "base64"}}},
        {"startedDateTime": "2026-11-09T01:02:06.000Z", "time": 1,
         "request": {"method": "GET", "url": "https://example.com/weird", "headers": []},
         "response": {"status": 204, "statusText": "No Content", "headers": [],
                      "content": {"mimeType": "text/plain", "text": "plain", "encoding": "quoted-printable"}}},
        {"startedDateTime": "2026-11-09T10:02:07+0900", "time": 0,
         "request": {"method": "GET", "url": "wss://example.com/socket", "headers": []},
         "response": {"status": 101, "statusText": "Switching Protocols", "headers": []}},
        {"startedDateTime": "어제쯤", "time": 0,
         "request": {"method": "GET", "url": "ws://example.com/x", "headers": []}}
      ]}}
    """#
    let fs = try FlowImport.har(Data(har.utf8))
    #expect(fs.count == 6)
    for f in fs {
        #expect(f.number == nil && f.comment == nil && f.highlight == nil && f.client == nil)
        #expect(f.flow.isTunnel == false && f.flow.error == nil && f.flow.annotations.isEmpty)
    }

    let a = fs[0].flow
    #expect(a.startedAt == t0)
    #expect(a.completedAt == t0.addingTimeInterval(0.01275))
    #expect(a.request.method == "GET" && a.request.scheme == "https" && a.request.host == "example.com" && a.request.port == 443 && a.request.path == "/a?x=1")
    #expect(a.request.headers == [HTTPHeader(name: ":authority", value: "example.com"), HTTPHeader(name: "accept", value: "*/*")])
    #expect(a.request.body.isEmpty && a.isDecrypted)
    // 이미 풀린 본문이어도 헤더는 기록 그대로(Content-Encoding 유지)
    #expect(a.response?.status == 200 && a.response?.reason == "" && a.response?.headers.first?.value == "gzip")
    #expect(a.response?.body == Data("{\"k\":\"한글\"}".utf8))

    let b = fs[1].flow
    #expect(b.startedAt == Date(timeIntervalSince1970: 1_794_186_124))
    #expect(b.completedAt == b.startedAt)  // 음수 time → 0
    #expect(b.request.scheme == "http" && b.request.port == 8080 && b.request.url == "http://example.com:8080/upload" && !b.isDecrypted)
    #expect(b.request.body == Data([0x00, 0x01, 0x02, 0xFF]))
    #expect(b.response == nil)  // status 0 → 응답 없음

    let c = fs[2].flow
    #expect(c.startedAt == Date(timeIntervalSince1970: 1_794_186_125.5))
    #expect(c.response?.body == Data([0x89, 0x50, 0x4E, 0x47]))

    // 모르는 encoding → text를 UTF-8로
    #expect(fs[3].flow.response?.body == Data("plain".utf8))

    // 콜론 없는 오프셋, ws·wss 기본 포트
    let w = fs[4].flow
    #expect(w.startedAt == Date(timeIntervalSince1970: 1_794_186_127))
    #expect(w.request.port == 443 && w.request.url == "wss://example.com/socket" && w.response?.status == 101 && w.response?.body.isEmpty == true)
    // 읽을 수 없는 시각 → 앞 항목의 시작 시각
    let x = fs[5].flow
    #expect(x.startedAt == w.startedAt && x.response == nil)
    #expect(x.request.port == 80 && x.request.url == "ws://example.com/x")
}

@Test func malformedEntriesAreSkippedOrDefaulted() throws {
    let har = #"""
    {"log": {"entries": [
      {"startedDateTime": "2026-11-09T01:02:03.250Z", "time": "slow",
       "request": {"method": "GET", "url": "https://example.com/ok",
                   "headers": [{"name": "X-Null", "value": null}, {"name": "X-Num", "value": 3}, {"value": "no name"}, {"name": "X-A", "value": "1"}]},
       "response": {"status": "200", "headers": []},
       "_prog": {"number": 3, "comment": "메모", "client": "iPhone"}},
      {"startedDateTime": "2026-11-09T01:02:04Z", "request": {"method": "GET"}},
      {"startedDateTime": "2026-11-09T01:02:05Z", "time": 5,
       "request": {"method": "GET", "url": "https://example.com/broken", "headers": "nope"},
       "response": {"status": 204, "statusText": "No Content", "headers": [], "content": {"text": 7}},
       "_prog": "not an object"},
      "garbage"
    ]}}
    """#
    let fs = try FlowImport.har(Data(har.utf8))
    #expect(fs.count == 2)
    let ok = fs[0]
    // _prog 필드는 하나씩: 빠진 isTunnel·isDecrypted 등이 있어도 나머지는 살린다
    #expect(ok.number == 3 && ok.comment == "메모" && ok.client == "iPhone" && ok.flow.isDecrypted && !ok.flow.isTunnel)
    #expect(ok.flow.request.headers == [HTTPHeader(name: "X-Null", value: ""), HTTPHeader(name: "X-Num", value: ""), HTTPHeader(name: "X-A", value: "1")])
    #expect(ok.flow.response == nil)  // status 형식 오류 → 응답 없음
    #expect(ok.flow.completedAt == ok.flow.startedAt)  // time 형식 오류 → 0
    let broken = fs[1]
    #expect(broken.number == nil && broken.comment == nil && broken.flow.annotations.isEmpty && broken.flow.isDecrypted)
    #expect(broken.flow.request.url == "https://example.com/broken" && broken.flow.request.headers.isEmpty)
    #expect(broken.flow.response?.status == 204 && broken.flow.response?.body.isEmpty == true)

    // 항목은 있는데 하나도 못 읽으면 빈 세션 대신 오류
    #expect(throws: FlowImportError.self) { try FlowImport.har(Data(#"{"log": {"entries": [{"request": {}}, 1]}}"#.utf8)) }
    // 첫 항목 시각을 못 읽으면 가져온 시각
    let before = Date()
    let first = try FlowImport.har(Data(#"{"log": {"entries": [{"request": {"method": "GET", "url": "https://example.com/"}}]}}"#.utf8))
    #expect(first[0].flow.startedAt >= before && first[0].flow.startedAt <= Date())
}

@Test func duplicateNumbersAreDropped() throws {
    let unique = try roundTrip([ExportItem(flow: flow(), number: 4), ExportItem(flow: flow(), number: 9)])
    #expect(unique.map(\.number) == [4, 9])
    let dup = try roundTrip([ExportItem(flow: flow(), number: 4), ExportItem(flow: flow(), number: 9), ExportItem(flow: flow(), number: 4)])
    #expect(dup.map(\.number) == [nil, nil, nil])
    // 0 이하 번호도 유효하지 않으므로 전부 다시 매긴다
    let zero = try roundTrip([ExportItem(flow: flow(), number: 0), ExportItem(flow: flow(), number: 9)])
    #expect(zero.map(\.number) == [nil, nil])
    // 코멘트 등 나머지는 그대로
    let kept = try roundTrip([ExportItem(flow: flow(), number: 1, comment: "a"), ExportItem(flow: flow(), number: 1, comment: "b")])
    #expect(kept.map(\.comment) == ["a", "b"])
}

@Test func invalidHARThrows() throws {
    for bad in ["", "not json", "[]", #"{"log": {}}"#, #"{"log": {"entries": 3}}"#, #"{"entries": []}"#] {
        #expect(throws: FlowImportError.self) { try FlowImport.har(Data(bad.utf8)) }
    }
    do {
        _ = try FlowImport.har(Data(#"{"log": {}}"#.utf8))
        Issue.record("throw 기대")
    } catch let FlowImportError.invalidHAR(reason) {
        #expect(!reason.isEmpty)
    }
    #expect(try FlowImport.har(Data(#"{"log": {"entries": []}}"#.utf8)).isEmpty)
}
