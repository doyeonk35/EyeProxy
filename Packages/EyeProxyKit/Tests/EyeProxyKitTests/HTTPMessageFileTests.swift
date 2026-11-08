import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hmf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func parsesProxymanDefaultMessage() throws {
    let body = "{\n  \"status\": \"ok\"\n}"
    let raw = Data("HTTP/1.1 200 OK\nContent-Type: application/json; charset=utf-8\n\n\(body)".utf8)
    let r = try HTTPMessageFile.parse(raw, fileURLBase: nil)
    #expect(r.status == 200)
    #expect(r.reason == "OK")
    #expect(r.headers == [
        HTTPHeader(name: "Content-Type", value: "application/json; charset=utf-8"),
        HTTPHeader(name: "Content-Length", value: "\(body.utf8.count)"),
    ])
    #expect(r.body == Data(body.utf8))
}

@Test func parsesCRLF() throws {
    let raw = Data("HTTP/1.1 404 Not Found\r\nX-A: 1\r\ncontent-length: 99\r\nTransfer-Encoding: chunked\r\n\r\nhi\r\n\r\nthere".utf8)
    let r = try HTTPMessageFile.parse(raw, fileURLBase: nil)
    #expect(r.status == 404)
    #expect(r.reason == "Not Found")
    #expect(r.headers == [HTTPHeader(name: "X-A", value: "1"), HTTPHeader(name: "content-length", value: "11")])
    #expect(r.body == Data("hi\r\n\r\nthere".utf8))
}

@Test func keepsRepeatedHeadersAndEdgeStatusLines() throws {
    let r = try HTTPMessageFile.parse(Data("HTTP/1.1 204\nVary: a\nSet-Cookie: x=1\nVary: b\nSet-Cookie: y=2".utf8), fileURLBase: nil)
    #expect(r.status == 204)
    #expect(r.reason == "")
    #expect(r.body.isEmpty)
    #expect(r.headers.map(\.name) == ["Vary", "Set-Cookie", "Vary", "Set-Cookie", "Content-Length"])
    #expect(r.headers.map(\.value) == ["a", "x=1", "b", "y=2", "0"])
}

@Test func fileURLReplacesBody() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data("abc".utf8).write(to: dir.appendingPathComponent("rel.json"))
    let raw = Data("HTTP/1.1 200 OK\nX-A: 1\n<file_url=\"rel.json\">\n\nignored".utf8)
    let r = try HTTPMessageFile.parse(raw, fileURLBase: dir)
    #expect(r.body == Data("abc".utf8))
    #expect(r.headers == [HTTPHeader(name: "X-A", value: "1"), HTTPHeader(name: "Content-Length", value: "3")])
}

@Test func missingFileURLThrows() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let raw = Data("HTTP/1.1 200 OK\n<FILE_URL=\"nope.bin\">\n\n".utf8)
    #expect(throws: HTTPMessageFileError.self) { try HTTPMessageFile.parse(raw, fileURLBase: dir) }
}

@Test func badStatusLineThrows() {
    #expect(throws: HTTPMessageFileError.badStatusLine) {
        try HTTPMessageFile.parse(Data("hello\n\nx".utf8), fileURLBase: nil)
    }
}

@Test func serializeRoundTrips() throws {
    let original = FlowResponse(
        status: 201, reason: "Created",
        headers: [HTTPHeader(name: "Content-Type", value: "text/plain"), HTTPHeader(name: "Content-Length", value: "5")],
        body: Data([0xFF, 0x00, 0x41, 0x0A, 0x42])
    )
    let data = HTTPMessageFile.serialize(original)
    #expect(data.starts(with: Data("HTTP/1.1 201 Created\nContent-Type: text/plain\n".utf8)))
    #expect(try HTTPMessageFile.parse(data, fileURLBase: nil) == original)
}

@Test func localFileGuessesContentType() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    for (name, type) in [("a.json", "application/json"), ("a.png", "image/png"), ("noext", "application/octet-stream")] {
        let url = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        let r = try HTTPMessageFile.response(forLocalFile: url)
        #expect(r.status == 200)
        #expect(r.header("Content-Type") == type)
        #expect(r.body == Data("x".utf8))
    }
}

@Test func requestRoundTripsThroughRaw() throws {
    let base = FlowRequest(method: "GET", scheme: "https", host: "api.example.com", port: 443, path: "/v1/items?x=1",
                           headers: [HTTPHeader(name: "Host", value: "api.example.com"), HTTPHeader(name: "A", value: "1")],
                           body: Data("{\"a\":1}".utf8))
    let raw = HTTPMessageFile.serialize(base)
    #expect(String(decoding: raw, as: UTF8.self).hasPrefix("GET /v1/items?x=1 HTTP/1.1\nHost: api.example.com\nA: 1\n\n"))
    #expect(try HTTPMessageFile.parseRequest(raw, base: base) == base)

    let edited = try HTTPMessageFile.parseRequest(Data("post http://other.example.com:8080/p HTTP/1.1\r\nB: 2\r\n\r\nhi".utf8), base: base)
    #expect(edited == FlowRequest(method: "POST", scheme: "http", host: "other.example.com", port: 8080, path: "/p",
                                  headers: [HTTPHeader(name: "B", value: "2")], body: Data("hi".utf8)))
    for bad in ["", "GET", "GET /x", "GET x HTTP/1.1", "GET /x FTP/1", "G T /x HTTP/1.1", "GET ftp://h/x HTTP/1.1"] {
        #expect(throws: HTTPMessageFileError.badRequestLine) { try HTTPMessageFile.parseRequest(Data(bad.utf8), base: base) }
    }
}
