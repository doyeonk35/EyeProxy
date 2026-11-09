import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private let t0 = Date(timeIntervalSince1970: 1_794_186_123.25)  // 2026-11-09T01:02:03.250Z

private func completedFlow() -> Flow {
    var f = Flow(id: FlowID(), clientAddress: "192.168.0.21", startedAt: t0,
                 request: FlowRequest(method: "POST", scheme: "https", host: "api.example.com", port: 443, path: "/v1/items?q=a%20b&n=2",
                                      headers: [HTTPHeader(name: "Content-Type", value: "application/json")], body: Data(#"{"a":1}"#.utf8)),
                 isDecrypted: true)
    f.response = FlowResponse(status: 201, reason: "Created", headers: [HTTPHeader(name: "Content-Type", value: "application/json"),
                                                                       HTTPHeader(name: "Location", value: "https://api.example.com/v1/items/9")],
                              body: Data(#"{"id":9}"#.utf8))
    f.completedAt = t0.addingTimeInterval(0.042)
    f.annotations = [.tool("Map Remote: R"), .originalURL("https://old.example.com/v1/items"), .tool("Map Local: L"), .tool("Map Remote: R")]
    return f
}

private func entries(_ data: Data) throws -> [[String: Any]] {
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let log = try #require(root["log"] as? [String: Any])
    return try #require(log["entries"] as? [[String: Any]])
}

@Test func harHasLog12ShapeAndProgExtension() throws {
    let item = ExportItem(flow: completedFlow(), number: 7, comment: "메모", highlight: FlowHighlight(color: .red, strikethrough: true), client: "iPhone")
    let data = FlowExport.har([item], version: "1.2.3")
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let log = try #require(root["log"] as? [String: Any])
    #expect(log["version"] as? String == "1.2")
    #expect(log["creator"] as? [String: String] == ["name": "Prog", "version": "1.2.3"])

    let e = try #require(try entries(data).first)
    #expect(e["startedDateTime"] as? String == "2026-11-09T01:02:03.250Z")
    #expect(e["time"] as? Int == 42)
    #expect((e["cache"] as? [String: Any])?.isEmpty == true)
    #expect(e["timings"] as? [String: Int] == ["send": 0, "wait": 42, "receive": 0])

    let req = try #require(e["request"] as? [String: Any])
    #expect(req["method"] as? String == "POST" && req["url"] as? String == "https://api.example.com/v1/items?q=a%20b&n=2")
    #expect(req["httpVersion"] as? String == "HTTP/1.1" && (req["cookies"] as? [Any])?.isEmpty == true)
    #expect(req["headers"] as? [[String: String]] == [["name": "Content-Type", "value": "application/json"]])
    #expect(req["queryString"] as? [[String: String]] == [["name": "q", "value": "a b"], ["name": "n", "value": "2"]])
    #expect(req["postData"] as? [String: String] == ["mimeType": "application/json", "text": #"{"a":1}"#])
    #expect(req["headersSize"] as? Int == -1 && req["bodySize"] as? Int == 7)

    let res = try #require(e["response"] as? [String: Any])
    #expect(res["status"] as? Int == 201 && res["statusText"] as? String == "Created" && res["httpVersion"] as? String == "HTTP/1.1")
    #expect(res["redirectURL"] as? String == "https://api.example.com/v1/items/9" && res["bodySize"] as? Int == 8)
    let content = try #require(res["content"] as? [String: Any])
    #expect(content["size"] as? Int == 8 && content["mimeType"] as? String == "application/json" && content["text"] as? String == #"{"id":9}"#)
    #expect(content["encoding"] == nil)

    let prog = try #require(e["_prog"] as? [String: Any])
    #expect(prog["number"] as? Int == 7 && prog["comment"] as? String == "메모" && prog["client"] as? String == "iPhone")
    #expect(prog["highlight"] as? [String: AnyHashable] == ["color": "red", "strikethrough": true])
    #expect(prog["tools"] as? [String] == ["Map Remote", "Map Local"])
    #expect(prog["isTunnel"] as? Bool == false && prog["isDecrypted"] as? Bool == true)
    #expect(prog["originalURL"] as? String == "https://old.example.com/v1/items")
    // 없는 선택 필드는 null 대신 생략
    for key in ["sentURL", "error", "incomplete"] { #expect(prog[key] == nil) }

    // 키 순서 고정(sortedKeys) + 슬래시 이스케이프 없음 → 같은 입력은 같은 바이트
    #expect(FlowExport.har([item], version: "1.2.3") == data)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"url\" : \"https://api.example.com/") && !json.contains("\\/"))

    // 바꾼 URL을 보존하는 Map Remote는 sentURL로
    var preserved = completedFlow(); preserved.annotations = [.tool("Map Remote: R"), .sentURL("https://new.example.com/v1/items")]
    let p2 = try #require(try entries(FlowExport.har([ExportItem(flow: preserved, number: 1)], version: "1"))[0]["_prog"] as? [String: Any])
    #expect(p2["sentURL"] as? String == "https://new.example.com/v1/items" && p2["originalURL"] == nil)
    for key in ["comment", "highlight", "client"] { #expect(p2[key] == nil) }
}

@Test func harEncodesBinaryAsBase64AndTextAsIs() throws {
    let gz = try gzip(Data("hello hello hello".utf8))
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
    let korean = #"{"msg":"안녕하세요"}"#
    var f = completedFlow()
    f.request.body = gz
    f.response?.body = png
    var g = completedFlow()
    g.request.body = Data(korean.utf8)
    g.response?.body = Data(korean.utf8)
    let es = try entries(FlowExport.har([ExportItem(flow: f, number: 1), ExportItem(flow: g, number: 2)], version: "1"))

    func body(_ e: [String: Any], _ side: String, _ key: String) throws -> [String: Any] {
        try #require((e[side] as? [String: Any])?[key] as? [String: Any])
    }
    for (b, bytes) in [(try body(es[0], "request", "postData"), gz), (try body(es[0], "response", "content"), png)] {
        #expect(b["encoding"] as? String == "base64")
        #expect(Data(base64Encoded: try #require(b["text"] as? String)) == bytes)
    }
    for b in [try body(es[1], "request", "postData"), try body(es[1], "response", "content")] {
        #expect(b["encoding"] == nil)
        #expect(b["text"] as? String == korean)
        #expect(Data((b["text"] as? String ?? "").utf8) == Data(korean.utf8))
    }
    #expect(try body(es[1], "response", "content")["size"] as? Int == Data(korean.utf8).count)
    // 한글은 \u 이스케이프 없이 그대로 쓴다
    #expect(String(decoding: FlowExport.har([ExportItem(flow: g, number: 2)], version: "1"), as: UTF8.self).contains("안녕하세요"))

    // BOM으로 시작하는 텍스트도 바이트 그대로. JSONSerialization은 문자열 첫 U+FEFF를 떼므로 JSONDecoder로 읽는다.
    var h = completedFlow()
    h.response?.body = Data([0xEF, 0xBB, 0xBF]) + Data(korean.utf8)
    let content = try JSONDecoder().decode(HARFile.self, from: FlowExport.har([ExportItem(flow: h, number: 3)], version: "1"))
        .log.entries[0].response.content
    #expect(content.encoding == nil && Data(content.text.utf8) == h.response?.body)
}

@Test func harMarksFailedAndIncompleteFlows() throws {
    var failed = completedFlow()
    failed.response = nil; failed.error = "연결이 끊어졌습니다"; failed.completedAt = t0.addingTimeInterval(1.5)
    var pending = completedFlow()
    pending.response = nil; pending.completedAt = nil
    pending.request.body = Data()
    let es = try entries(FlowExport.har([ExportItem(flow: failed, number: 3), ExportItem(flow: pending, number: 5)], version: "1"))

    let fr = try #require(es[0]["response"] as? [String: Any])
    #expect(fr["status"] as? Int == 0 && fr["statusText"] as? String == "" && (fr["headers"] as? [Any])?.isEmpty == true)
    #expect((fr["content"] as? [String: AnyHashable]) == ["size": 0, "mimeType": "", "text": ""])
    #expect(es[0]["time"] as? Int == 1500)
    let fp = try #require(es[0]["_prog"] as? [String: Any])
    #expect(fp["error"] as? String == "연결이 끊어졌습니다" && fp["incomplete"] == nil)

    #expect((es[1]["response"] as? [String: Any])?["status"] as? Int == 0)
    #expect(es[1]["time"] as? Int == 0)
    #expect(es[1]["timings"] as? [String: Int] == ["send": 0, "wait": 0, "receive": 0])
    #expect((es[1]["request"] as? [String: Any])?["postData"] == nil)
    let pp = try #require(es[1]["_prog"] as? [String: Any])
    #expect(pp["incomplete"] as? Bool == true && pp["error"] == nil && pp["number"] as? Int == 5)
}

@Test func csvHasHeaderAndStableNumbers() {
    var tunnel = Flow(id: FlowID(), clientAddress: "127.0.0.1", startedAt: t0,
                      request: FlowRequest(method: "CONNECT", scheme: "https", host: "example.com", port: 443, path: "", headers: [], body: Data()),
                      isTunnel: true)
    tunnel.error = "x"
    let items = [
        ExportItem(flow: completedFlow(), number: 2, comment: "ok", highlight: FlowHighlight(color: .green), client: "iPhone"),
        ExportItem(flow: tunnel, number: 5, highlight: FlowHighlight(strikethrough: true)),
        ExportItem(flow: completedFlow(), number: 9, highlight: FlowHighlight(color: .blue, strikethrough: true)),
    ]
    let lines = FlowExport.csv(items).components(separatedBy: "\r\n")
    #expect(lines == [
        "ID,Method,URL,Status,Code,Client,Start,Duration (ms),Request Size,Response Size,SSL,Edited,Highlight,Comment",
        #"2,POST,https://api.example.com/v1/items?q=a%20b&n=2,Completed,201,iPhone,2026-11-09T01:02:03.250Z,42,7,8,Yes,"Map Remote, Map Local",green,ok"#,
        "5,CONNECT,https://example.com,Failed,,,2026-11-09T01:02:03.250Z,,0,,No,,strikethrough,",
        #"9,POST,https://api.example.com/v1/items?q=a%20b&n=2,Completed,201,,2026-11-09T01:02:03.250Z,42,7,8,Yes,"Map Remote, Map Local",blue+strikethrough,"#,
        "",
    ])
    #expect(FlowExport.csv([]) == lines[0] + "\r\n")
}

@Test func csvEscapesCommasQuotesAndNewlines() {
    var f = completedFlow()
    f.request.path = "/a,b?q=\"x\""
    let csv = FlowExport.csv([ExportItem(flow: f, number: 1, comment: "line1\r\nline2, \"quoted\"\nend", client: "Kim's, iPad")])
    let row = csv.components(separatedBy: "\r\n").dropFirst().joined(separator: "\r\n")
    #expect(row.hasPrefix(#"1,POST,"https://api.example.com/a,b?q=""x""",Completed,201,"Kim's, iPad","#))
    #expect(row.hasSuffix(",\"line1\r\nline2, \"\"quoted\"\"\nend\"\r\n"))
    // RFC 4180 파싱으로 되돌리면 열 14개, 값 그대로
    let fields = parseCSVRecord(row)
    #expect(fields.count == 14)
    #expect(fields[2] == "https://api.example.com/a,b?q=\"x\"" && fields[5] == "Kim's, iPad")
    #expect(fields[13] == "line1\r\nline2, \"quoted\"\nend")
}

/// 테스트용 RFC 4180 레코드 하나 파서(끝의 CRLF까지).
private func parseCSVRecord(_ s: String) -> [String] {
    var fields: [String] = [], cur = "", quoted = false
    var it = Array(s.unicodeScalars).makeIterator()
    var pending: Unicode.Scalar? = nil
    while let c = pending ?? it.next() {
        pending = nil
        if quoted {
            if c == "\"" {
                if let n = it.next() { if n == "\"" { cur.unicodeScalars.append("\"") } else { quoted = false; pending = n } } else { quoted = false }
            } else { cur.unicodeScalars.append(c) }
        } else if c == "\"" { quoted = true
        } else if c == "," { fields.append(cur); cur = ""
        } else if c == "\r" { _ = it.next(); break
        } else { cur.unicodeScalars.append(c) }
    }
    fields.append(cur)
    return fields
}
