import EyeProxyCore
import Testing
@testable import EyeProxyKit

@Test func filterIsANDOfTokens() {
    let f = Flow.fixture(url: "https://api.tving.com/v2/search", method: "GET", status: 200)
    #expect(FlowFilter(text: "tving search").matches(f)); #expect(!FlowFilter(text: "tving POST").matches(f)); #expect(FlowFilter(text: "200").matches(f))
}

@Test func filterDeviceAndHost() {
    let f = Flow.fixture(url: "https://api.tving.com/v2", method: "GET", status: 200)
    #expect(FlowFilter(device: "192.168.0.21", host: "api.tving.com").matches(f))
    #expect(!FlowFilter(device: "other").matches(f)); #expect(!FlowFilter(host: "x.com").matches(f))
}
