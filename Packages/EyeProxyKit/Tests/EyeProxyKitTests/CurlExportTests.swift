import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

@Test func curlCommand() { #expect(CurlExport.command(for: FlowRequest(method: "POST", scheme: "https", host: "a", port: 443, path: "/b?c=1", headers: [.init(name: "Content-Type", value: "application/json")], body: Data(#"{"x":1}"#.utf8))) == #"curl -X 'POST' 'https://a/b?c=1' -H 'Content-Type: application/json' --data-binary '{"x":1}'"#) }

@Test func curlGetQuotingAndOmissions() {
    let r = FlowRequest(method: "GET", scheme: "http", host: "a", port: 8080, path: "/", headers: [.init(name: "Host", value: "a"), .init(name: "Content-Length", value: "3"), .init(name: "X", value: "it's")], body: Data([0xff]))
    #expect(CurlExport.command(for: r) == #"curl 'http://a:8080/' -H 'X: it'\''s' # binary body omitted"#)
}
