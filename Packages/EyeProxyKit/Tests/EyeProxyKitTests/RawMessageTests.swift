import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private func h(_ n: String, _ v: String) -> HTTPHeader { .init(name: n, value: v) }

@Test func rawRequestFormatsStartLineHeadersAndBody() {
    let r = FlowRequest(method: "POST", scheme: "https", host: "example.com", port: 443, path: "/api?q=1",
                        headers: [h("Host", "example.com"), h("Content-Type", "application/json")], body: Data(#"{"a":1}"#.utf8))
    #expect(RawMessage.request(r) == "POST /api?q=1 HTTP/1.1\nHost: example.com\nContent-Type: application/json\n\n{\"a\":1}")
}

@Test func rawResponseShowsBinaryPlaceholder() {
    let r = FlowResponse(status: 200, reason: "OK", headers: [h("Content-Type", "image/png")], body: Data([0x89, 0x50, 0xff, 0xfe]))
    #expect(RawMessage.response(r) == "HTTP/1.1 200 OK\nContent-Type: image/png\n\n<binary 4 bytes>")
}

@Test func rawDecodesGzipBody() throws {
    let gz = try gzip(Data("안녕 hello".utf8))
    let r = FlowResponse(status: 404, reason: "Not Found", headers: [h("Content-Encoding", "gzip")], body: gz)
    // 본문은 풀어서, 헤더는 원래 값 그대로.
    #expect(RawMessage.response(r) == "HTTP/1.1 404 Not Found\nContent-Encoding: gzip\n\n안녕 hello")
}
