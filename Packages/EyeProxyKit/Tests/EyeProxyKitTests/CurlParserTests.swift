import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

@Test func parsesExportedCurl() {
    let r = FlowRequest(method: "POST", scheme: "https", host: "api.example.com", port: 8443, path: "/a?b=1",
                        headers: [.init(name: "Content-Type", value: "application/json"), .init(name: "X-Quote", value: "it's")],
                        body: Data(#"{"k":"it's"}"#.utf8))
    #expect(CurlParser.parse(CurlExport.command(for: r)) == r)
}

@Test(arguments: [
    ("curl https://api.example.com/a", "GET"),
    ("curl -d 'a=1' https://api.example.com/a", "POST"),
    ("curl -G -d 'q=1' https://api.example.com/s", "GET"),   // url ?q=1
    ("curl -X PUT -H 'X-A: b' --data-raw \"{\\\"k\\\":1}\" https://api.example.com/a", "PUT"),
    ("curl 'https://api.example.com/a' \\\n  -H 'Accept: */*' --compressed", "GET"),
]) func curlVariants(command: String, method: String) throws {
    let r = try #require(CurlParser.parse(command))
    #expect(r.method == method && r.scheme == "https" && r.host == "api.example.com" && r.port == 443)
    switch command {
    case let c where c.contains("-G"): #expect(r.path == "/s?q=1" && r.body.isEmpty)
    case let c where c.contains("PUT"): #expect(r.header("X-A") == "b" && r.body == Data(#"{"k":1}"#.utf8))
    case let c where c.contains("Accept"): #expect(r.headers == [HTTPHeader(name: "Accept", value: "*/*")] && r.path == "/a")
    case let c where c.contains("-d"): #expect(r.body == Data("a=1".utf8) && r.header("Content-Type") == "application/x-www-form-urlencoded")
    default: #expect(r.path == "/a" && r.headers.isEmpty)
    }
}

@Test func garbageReturnsNil() {
    #expect(CurlParser.parse("ls -la") == nil)
    #expect(CurlParser.parse("curl -s") == nil)
}
