import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private func flow(_ client: String, _ url: String) -> Flow { var f = Flow.fixture(url: url, method: "GET", status: 200); f = Flow(id: f.id, clientAddress: client, startedAt: f.startedAt, request: f.request, response: f.response); return f }

private let safari = ProcessIdentity(pid: 1, path: "/Applications/Safari.app/Contents/MacOS/Safari")
private let sim = ProcessIdentity(pid: 2, path: "/x/CoreSimulator/Devices/U1/data/TVING.app/TVING")
private let tv = Device(address: "192.168.0.9", name: "거실 TV", kind: .appleTV, lastSeen: .now)

/// 이 Mac 셋(Safari·시뮬레이터·귀속 없음), 이름 아는 원격 TV 둘, 이름 모르는 원격 하나.
private func sample() -> (flows: [Flow], attribution: [FlowID: ProcessIdentity], tree: SidebarTree) {
    let a = flow("127.0.0.1", "https://www.example.com/"), b = flow("127.0.0.1", "https://api.example.com/x"), c = flow("::1", "https://api.example.com/y")
    let d = flow("192.168.0.9", "https://api.example.com/z"), e = flow("192.168.0.9", "https://vod.example-cdn.net/seg/1.ts"), f = flow("192.168.0.30", "https://a.example.com/")
    let flows = [a, b, c, d, e, f], attribution = [a.id: safari, b.id: sim]
    let tree = SidebarTree.build(flows: flows, attribution: attribution, devices: [tv], pinned: ["gw.example.com", "api.example.com"], runtimes: ["U1": "tvOS 18.1"])
    return (flows, attribution, tree)
}

@Test func treeSplitsRemoteDevicesAppsAndDomains() {
    let t = sample().tree
    #expect(t.remoteDevices.map(\.displayName).sorted() == ["192.168.0.30", "거실 TV"])
    let tvNode = t.remoteDevices.first { $0.address == "192.168.0.9" }!
    #expect(tvNode.kind == .appleTV && tvNode.count == 2 && tvNode.hosts == [HostNode(host: "api.example.com", count: 1), HostNode(host: "vod.example-cdn.net", count: 1)])
    #expect(Set(t.apps.prefix(2).map(\.displayName)) == ["Safari", "TVING (tvOS 시뮬레이터)"])
    #expect(t.apps.last!.groupKey == FlowFilter.unknownProcessKey && t.apps.last!.hosts == [HostNode(host: "api.example.com", count: 1)])
    #expect(t.apps.map(\.count).reduce(0, +) == 3)
    #expect(t.domains.map(\.host) == ["a.example.com", "api.example.com", "vod.example-cdn.net", "www.example.com"])
    #expect(t.hostsWithPaths == ["api.example.com", "vod.example-cdn.net"])
    // 원격 기기가 없으면 Remote devices가 비어 섹션이 숨는다.
    let local = SidebarTree.build(flows: [flow("::1", "https://a/"), flow("127.0.0.1", "https://a/")], attribution: [:], devices: [], pinned: [], runtimes: [:])
    #expect(local.remoteDevices.isEmpty && local.apps.count == 1 && local.apps[0].count == 2)
}

@Test func treeKeepsPinnedAndCountsMatch() {
    let (flows, attribution, t) = sample()
    #expect(t.pinned.map(\.host) == ["gw.example.com", "api.example.com"] && t.pinned.map(\.count) == [0, 3])
    /// 그 줄을 골랐을 때 목록에 보이는 흐름 수(앱과 같은 `SidebarItem.apply`).
    func listed(_ item: SidebarItem) -> Int {
        var f = FlowFilter()
        item.apply(to: &f)
        return flows.filter { f.matches($0, process: attribution[$0.id]?.groupKey) }.count
    }
    var rows: [(SidebarItem, Int)] = t.pinned.map { (.host($0.host), $0.count) } + t.domains.map { (.host($0.host), $0.count) }
    for d in t.remoteDevices {
        rows.append((.scope(FlowScope(device: d.address)), d.count))
        rows += d.hosts.map { (.scope(FlowScope(device: d.address, host: $0.host)), $0.count) }
    }
    rows.append((.scope(FlowScope(device: SidebarTree.thisMac)), t.appsCount))
    for app in t.apps {
        rows.append((.scope(FlowScope(device: SidebarTree.thisMac, process: app.groupKey)), app.count))
        rows += app.hosts.map { (.scope(FlowScope(device: SidebarTree.thisMac, process: app.groupKey, host: $0.host)), $0.count) }
    }
    for node in SidebarTree.pathTree(for: "api.example.com", flows: flows) {
        rows.append((.path(host: "api.example.com", prefix: node.fullPath), node.count))
    }
    #expect(rows.count == 21)
    for (item, count) in rows { #expect(listed(item) == count, "\(item)") }
    #expect(listed(.allFlows) == flows.count)
}

@Test func pathTreeGroupsSegmentsWithCounts() {
    let flows = ["/v3/media/1", "/v3/media/2?x=1", "/v3/user", "/v30", "/", "/a/b/c/d/e/f"].map { flow("127.0.0.1", "https://api.example.com" + $0) }
        + [flow("127.0.0.1", "https://other.example.com/v3/media")]
    let tree = SidebarTree.pathTree(for: "api.example.com", flows: flows)
    #expect(tree.map(\.segment) == ["a", "v3", "v30"] && tree.map(\.count) == [1, 3, 1])
    let v3 = tree[1]
    #expect(v3.fullPath == "/v3" && v3.children.map(\.segment) == ["media", "user"] && v3.children.map(\.count) == [2, 1])
    #expect(v3.children[0].fullPath == "/v3/media" && v3.children[0].children.map(\.segment) == ["1", "2"])
    // 깊이 상한(4): 그 아래는 마지막 노드에 합친다.
    var deepest = tree[0]
    while let next = deepest.children.first { deepest = next }
    #expect(deepest.fullPath == "/a/b/c/d" && deepest.count == 1 && SidebarTree.pathDepthLimit == 4)
}

@Test func pathPrefixFilterMatchesOnlyUnderPrefix() {
    var f = FlowFilter(host: "api.example.com")
    f.pathPrefix = "/v3"
    let hits = ["/v3", "/v3/x", "/v3/", "/v3?q=1", "/v3/media/1"].map { f.matches(flow("127.0.0.1", "https://api.example.com" + $0)) }
    let misses = ["/v30", "/v4/v3", "/", "/V3"].map { f.matches(flow("127.0.0.1", "https://api.example.com" + $0)) }
    #expect(hits.allSatisfy { $0 } && !misses.contains(true))
    #expect(!f.matches(flow("127.0.0.1", "https://other.example.com/v3")))
}

@Test func sidebarFilterMatchesNamesCaseInsensitive() {
    let t = sample().tree
    #expect(t.filtered("").domains == t.domains && t.filtered("  ").apps.count == t.apps.count)
    let cdn = t.filtered("EXAMPLE-cdn")
    #expect(cdn.domains.map(\.host) == ["vod.example-cdn.net"] && cdn.pinned.isEmpty && cdn.apps.isEmpty)
    // 자식이 맞으면 부모는 그 자식만 가지고 남는다(개수는 부모 전체 — 고르면 목록과 같게).
    #expect(cdn.remoteDevices.map(\.displayName) == ["거실 TV"] && cdn.remoteDevices[0].hosts.map(\.host) == ["vod.example-cdn.net"] && cdn.remoteDevices[0].count == 2)
    // 부모 이름이 맞으면 자식 전부.
    let byName = t.filtered("SAFARI")
    #expect(byName.apps.map(\.displayName) == ["Safari"] && byName.apps[0].hosts.map(\.host) == ["www.example.com"])
    #expect(t.filtered("거실").remoteDevices.first?.hosts.count == 2)
    #expect(t.filtered("API").pinned.map(\.host) == ["api.example.com"])
}

@Test func treeNamesImportedFlowsWithoutClient() {
    let t = SidebarTree.build(flows: [flow("", "https://a/")], attribution: [:], devices: [], pinned: [], runtimes: [:])
    #expect(t.remoteDevices.count == 1 && t.remoteDevices[0].displayName == "가져온 요청" && t.remoteDevices[0].kind == .unknown)
}
