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
