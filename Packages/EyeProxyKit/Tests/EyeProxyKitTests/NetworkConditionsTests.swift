import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private let ctx = FlowContext(id: .init(), clientAddress: "127.0.0.1", clientPort: 5000) { _ in }

private func req(_ host: String, body: Int = 0) -> FlowRequest {
    FlowRequest(method: "GET", scheme: "https", host: host, port: 443, path: "/", headers: [], body: Data(count: body))
}

private func profile(delay: Int = 0, down: Int = 0, lost: Bool = false) -> NetworkProfile {
    NetworkProfile(name: "T", profileType: 1, downloadBandwidth: down, uploadBandwidth: down,
                   downloadBandwidthTitle: "", uploadBandwidthTitle: "", delay: delay, minimumWaitTime: 0,
                   packageDrop: 0, isAllLostConnection: lost, downloadMin: down, uploadMin: down)
}

private func rule(_ p: NetworkProfile, url: String = "img.example.com") -> NetworkConditionRule {
    NetworkConditionRule(id: "r", name: "R", url: url, isEnabled: true, isSystemWide: false, networkProfile: p)
}

private func elapsed(_ body: () async -> Void) async -> Duration {
    await ContinuousClock().measure { await body() }
}

@Test func decodesProxymanThrottlingFixture() throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        .appendingPathComponent("Proxyman/NetworkThrottlingService.json")
    let rules = try JSONDecoder().decode([NetworkConditionRule].self, from: Data(contentsOf: url))
    let p = try #require(rules.first).networkProfile
    #expect(rules[0].url == "img.example.com" && p.name == "Very Bad Network" && p.downloadBandwidth == 125000)
    #expect(p.delay == 1400 && p.packageDrop == 10 && p.profileType == 1 && p.minimumWaitTime == 500000)
    let obj = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(rules)) as? [[String: Any]])
    let np = try #require(obj[0]["networkProfile"] as? [String: Any])
    for k in ["name", "profileType", "downloadBandwidth", "uploadBandwidth", "downloadBandwidthTitle",
              "uploadBandwidthTitle", "delay", "minimumWaitTime", "packageDrop", "isAllLostConnection"] {
        #expect(np[k] != nil, "\(k)")
    }
    #expect(try JSONDecoder().decode([NetworkConditionRule].self, from: JSONEncoder().encode(rules)) == rules)
}

@Test func presetsMatchSpecNames() {
    #expect(NetworkProfile.presets.map(\.name) == ["100% Loss", "Very Bad Network", "Slow Network", "Medium Network",
                                                   "2G (EDGE)", "3G", "4G (LTE)", "5G", "Wi-Fi", "Wi-Fi 802.11ac"])
    #expect(NetworkProfile.presets[0].isAllLostConnection)
    #expect(NetworkProfile.presets[1].delay == 1400 && NetworkProfile.presets[1].downloadBandwidth == 125_000)
}

@Test func delayAppliesOnlyToTargetHost() async {
    let i = NetworkConditionsInterceptor(rule: rule(profile(delay: 300)), random: { 0 })
    let slow = await elapsed { _ = await i.intercept(req("img.example.com"), context: ctx) }
    let fast = await elapsed { _ = await i.intercept(req("other.example.com"), context: ctx) }
    #expect(slow >= .milliseconds(290))
    #expect(fast < .milliseconds(100))
}

@Test func bandwidthDelayScalesWithSize() async {
    let i = NetworkConditionsInterceptor(rule: rule(profile(down: 100_000)), random: { 0 })
    let res = FlowResponse(status: 200, reason: "OK", headers: [], body: Data(count: 50_000))
    let t = await elapsed { _ = await i.intercept(res, for: req("img.example.com"), context: ctx) }
    #expect(t >= .milliseconds(490))
}

@Test func totalLossHangsUntilCancelled() async {
    let i = NetworkConditionsInterceptor(rule: rule(profile(lost: true)))
    let task = Task { await i.intercept(req("img.example.com"), context: ctx) }
    try? await Task.sleep(for: .milliseconds(500))
    task.cancel()
    guard case .drop = await task.value else { Issue.record("expected drop"); return }
}

@Test func connectShapingForTarget() async {
    let i = NetworkConditionsInterceptor(rule: rule(profile(delay: 40, down: 1000)), random: { 0 })
    let c = ConnectContext(clientAddress: "127.0.0.1", clientPort: 1)
    let v = await i.intercept(host: "IMG.example.com", port: 443, context: c)
    #expect(v.shaping == TunnelShaping(latencyMS: 40, downBytesPerSecond: 1000, upBytesPerSecond: 1000, blackhole: false))
    #expect(await i.intercept(host: "x.example.com", port: 443, context: c).shaping == nil)
}

@Test @MainActor func activatingOneDeactivatesOthers() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let s = RuleStore(directory: dir)
    s.networkConditions = [rule(profile()), NetworkConditionRule(id: "b", name: "B", url: "x", isEnabled: true, isSystemWide: false, networkProfile: profile())]
    s.activateNetworkCondition(id: "r")
    #expect(s.networkConditions.map(\.isEnabled) == [true, false])
    #expect(RuleStore(directory: dir).networkConditions.map(\.isEnabled) == [true, false])
}

@Test @MainActor func customProfilesPersist() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let s = RuleStore(directory: dir)
    s.customNetworkProfiles = [profile(delay: 7, down: 500)]
    #expect(RuleStore(directory: dir).customNetworkProfiles == [profile(delay: 7, down: 500)])
}
