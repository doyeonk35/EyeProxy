import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

@Test func curlCommand() { #expect(CurlExport.command(for: FlowRequest(method: "POST", scheme: "https", host: "a", port: 443, path: "/b?c=1", headers: [.init(name: "Content-Type", value: "application/json")], body: Data(#"{"x":1}"#.utf8))) == #"curl -X 'POST' 'https://a/b?c=1' -H 'Content-Type: application/json' --data-binary '{"x":1}'"#) }

@Test func curlGetQuotingAndOmissions() {
    let r = FlowRequest(method: "GET", scheme: "http", host: "a", port: 8080, path: "/", headers: [.init(name: "Host", value: "a"), .init(name: "Content-Length", value: "3"), .init(name: "X", value: "it's")], body: Data([0xff]))
    #expect(CurlExport.command(for: r) == #"curl 'http://a:8080/' -H 'X: it'\''s' # binary body omitted"#)
}

/// Tools ▸ Add --proxy flag into cURL command: 켜면 `--proxy`를 본문 앞에 붙인다(`#` 주석 뒤로 가 먹히지 않게). nil이면 지금과 같다.
@Test func curlAddsProxyFlagWhenEnabled() {
    let r = FlowRequest(method: "GET", scheme: "https", host: "example.com", port: 443, path: "/a", headers: [], body: Data())
    #expect(CurlExport.command(for: r, proxy: "http://192.168.0.2:9090") == "curl 'https://example.com/a' --proxy 'http://192.168.0.2:9090'")
    #expect(CurlExport.command(for: r, proxy: nil) == "curl 'https://example.com/a'")
    var b = r; b.body = Data([0xff])
    #expect(CurlExport.command(for: b, proxy: "http://10.0.0.1:19090") == "curl 'https://example.com/a' --proxy 'http://10.0.0.1:19090' # binary body omitted")
}
