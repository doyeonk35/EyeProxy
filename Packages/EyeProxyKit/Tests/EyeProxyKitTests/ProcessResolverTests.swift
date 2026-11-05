import Testing
@testable import EyeProxyKit

@Test func parseLsofMapsClientPortToPidAndSkipsSelf() {
    let out = "p100\ncEyeProxy\nf5\nn*:9090\nf6\nn127.0.0.1:9090->127.0.0.1:52001\np200\ncSafari\nf7\nn127.0.0.1:52001->127.0.0.1:9090\np300\ncWebKit\nf8\nn[::1]:52002->[::1]:9090\nf9\nn127.0.0.1:52003->127.0.0.1:443\n"
    let m = ProcessLookup.parseLsof(out, proxyPort: 9090, excludingPID: 100)
    #expect(m == [52001: 200, 52002: 300])
}

@Test func cacheEntriesExpireAfterTTLAndNeedPath() async {
    let r = ProcessResolver()
    let t0 = ContinuousClock.now
    let id = ProcessIdentity(pid: 5, path: "/Applications/Safari.app/Contents/MacOS/Safari")
    await r.store(id, for: 50000, at: t0)
    #expect(await r.cached(50000, now: t0 + .seconds(59)) == id)
    #expect(await r.cached(50000, now: t0 + .seconds(60)) == nil)
    await r.store(ProcessIdentity(pid: 6, path: nil), for: 50001, at: t0)
    #expect(await r.cached(50001, now: t0) == nil)
}

@Test func resolverReturnsNilWhenPortAbsent() async {
    let r = ProcessResolver()
    let t = ContinuousClock.now
    #expect(await r.resolve(port: 1, proxyPort: 1) == nil)
    #expect(ContinuousClock.now - t < .seconds(8))
}
