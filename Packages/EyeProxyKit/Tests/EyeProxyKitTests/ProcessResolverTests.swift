import Testing
@testable import EyeProxyKit

@Test func parseLsofMapsClientPortToPidAndSkipsSelf() {
    let out = "p100\ncEyeProxy\nf5\nn*:9090\nf6\nn127.0.0.1:9090->127.0.0.1:52001\np200\ncSafari\nf7\nn127.0.0.1:52001->127.0.0.1:9090\np300\ncWebKit\nf8\nn[::1]:52002->[::1]:9090\nf9\nn127.0.0.1:52003->127.0.0.1:443\n"
    let m = ProcessLookup.parseLsof(out, proxyPort: 9090, excludingPID: 100)
    #expect(m == [52001: 200, 52002: 300])
}

@Test func resolverReturnsNilWhenPortAbsent() async {
    let r = ProcessResolver()
    let t = ContinuousClock.now
    #expect(await r.resolve(port: 1, proxyPort: 1) == nil)
    #expect(ContinuousClock.now - t < .seconds(8))
}
