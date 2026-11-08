import EyeProxyCore
import Testing
@testable import EyeProxyKit

@Test func filterIsANDOfTokens() {
    let f = Flow.fixture(url: "https://api.example.com/v2/search", method: "GET", status: 200)
    #expect(FlowFilter(text: "example search").matches(f)); #expect(!FlowFilter(text: "example POST").matches(f)); #expect(FlowFilter(text: "200").matches(f))
}

@Test func filterProcessAndLoopback() {
    let f = Flow.fixture(client: "::1", decrypted: true)
    #expect(FlowFilter(device: "127.0.0.1").matches(f)); #expect(FlowFilter.sameDevice("::1", "127.0.0.1") && !FlowFilter.sameDevice("::1", "10.0.0.1"))
    var p = FlowFilter(); p.process = "/a/Safari"
    #expect(p.matches(f, process: "/a/Safari") && !p.matches(f, process: nil) && !p.matches(f, process: "/b"))
    p.process = FlowFilter.unknownProcessKey; #expect(p.matches(f, process: nil))
}

@Test func filterDeviceAndHost() {
    let f = Flow.fixture(url: "https://api.example.com/v2", method: "GET", status: 200)
    #expect(FlowFilter(device: "192.168.0.21", host: "api.example.com").matches(f))
    #expect(!FlowFilter(device: "other").matches(f)); #expect(!FlowFilter(host: "x.com").matches(f))
}

private func typed(_ url: String, status: Int, _ type: String) -> Flow {
    var f = Flow.fixture(url: url, method: "GET", status: status)
    f.response?.headers = [HTTPHeader(name: "Content-Type", value: type)]
    return f
}

@Test func barGroupsAreOrWithinAndAcrossGroups() {
    var b = FlowFilter(); b.protocols = [.https]; b.contentKinds = [.json, .xml]; b.statusClasses = [2]
    #expect(b.matches(typed("https://a.com/", status: 200, "application/json")))
    #expect(!b.matches(typed("http://a.com/", status: 200, "application/json")))
    #expect(!b.matches(typed("https://a.com/", status: 200, "text/css")))
    #expect(!b.matches(typed("https://a.com/", status: 404, "application/json")))
}

@Test func statusFilterExcludesPendingRows() {
    var f = Flow.fixture(url: "https://a.com/", method: "GET", status: 200); f.response = nil
    var b = FlowFilter(); #expect(b.matches(f))
    b.statusClasses = [2]; #expect(!b.matches(f))
}

@Test func barFilterStacksWithTextAndHost() {
    var b = FlowFilter(text: "search", host: "api.example.com"); b.contentKinds = [.json]
    #expect(b.matches(typed("https://api.example.com/search", status: 200, "application/json")))
    #expect(!b.matches(typed("https://api.example.com/list", status: 200, "application/json")))
    #expect(!b.matches(typed("https://x.example.com/search", status: 200, "application/json")))
    #expect(!b.matches(typed("https://api.example.com/search", status: 200, "text/html")))
}

@Test func clearBarKeepsOtherFields() {
    var b = FlowFilter(text: "q", host: "h"); b.protocols = [.http]; b.contentKinds = [.css]; b.statusClasses = [5]
    #expect(!b.isBarEmpty); b.clearBar()
    #expect(b.isBarEmpty && b.text == "q" && b.host == "h")
}
