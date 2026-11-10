import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private func flow(_ client: String, _ url: String) -> Flow { var f = Flow.fixture(url: url, method: "GET", status: 200); f = Flow(id: f.id, clientAddress: client, startedAt: f.startedAt, request: f.request, response: f.response); return f }

@Test func treeSplitsMacByAppAndRemoteByHost() {
    let a = flow("127.0.0.1", "https://www.example.com/"), b = flow("127.0.0.1", "https://api.example.com/x"), c = flow("::1", "https://api.example.com/y"), d = flow("192.168.0.9", "https://api.example.com/z")
    let safari = ProcessIdentity(pid: 1, path: "/Applications/Safari.app/Contents/MacOS/Safari")
    let sim = ProcessIdentity(pid: 2, path: "/x/CoreSimulator/Devices/U1/data/TVING.app/TVING")
    let t = SidebarTree.build(flows: [a, b, c, d], attribution: [a.id: safari, b.id: sim], devices: [Device(address: "192.168.0.9", name: "거실 TV", kind: .appleTV, lastSeen: .now)], pinned: ["gw.example.com", "api.example.com"], runtimes: ["U1": "tvOS 18.1"])
    #expect(t.pinned.map(\.host) == ["gw.example.com", "api.example.com"] && t.pinned.map(\.count) == [0, 3])
    #expect(t.devices.count == 2)
    let mac = t.devices.first { $0.address == "127.0.0.1" }!
    #expect(mac.displayName == "이 Mac" && mac.kind == .thisMac && mac.count == 3 && mac.hosts.isEmpty)
    #expect(mac.apps.map(\.displayName) == ["Safari", "TVING (tvOS 시뮬레이터)", "기타"] || mac.apps.map(\.displayName) == ["TVING (tvOS 시뮬레이터)", "Safari", "기타"])
    #expect(mac.apps.last!.groupKey == FlowFilter.unknownProcessKey && mac.apps.last!.hosts == [HostNode(host: "api.example.com", count: 1)])
    let tv = t.devices.first { $0.address == "192.168.0.9" }!
    #expect(tv.displayName == "거실 TV" && tv.kind == .appleTV && tv.apps.isEmpty && tv.hosts == [HostNode(host: "api.example.com", count: 1)])
    #expect(t.hosts.map(\.host) == ["api.example.com", "www.example.com"])
}
@Test func treeMergesLoopbackAddresses() {
    let t = SidebarTree.build(flows: [flow("::1", "https://a/"), flow("127.0.0.1", "https://a/")], attribution: [:], devices: [], pinned: [], runtimes: [:])
    #expect(t.devices.count == 1 && t.devices[0].address == "127.0.0.1" && t.devices[0].count == 2)
}
@Test func treeNamesImportedFlowsWithoutClient() {
    let t = SidebarTree.build(flows: [flow("", "https://a/")], attribution: [:], devices: [], pinned: [], runtimes: [:])
    #expect(t.devices.count == 1 && t.devices[0].displayName == "가져온 요청" && t.devices[0].kind == .unknown)
}
