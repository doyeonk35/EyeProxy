import EyeProxyCore
import Foundation

public struct HostNode: Identifiable, Hashable, Sendable {
    public let host: String
    public let count: Int
    public var id: String { host }

    public init(host: String, count: Int) {
        self.host = host
        self.count = count
    }
}

public struct AppNode: Identifiable, Sendable {
    public let groupKey: String
    public let displayName: String
    public let path: String?
    public let count: Int
    public let hosts: [HostNode]
    public var id: String { groupKey }
}

public struct DeviceNode: Identifiable, Sendable {
    public let address: String
    public let displayName: String
    public let kind: DeviceKind
    public let count: Int
    public let apps: [AppNode]
    public let hosts: [HostNode]
    public var id: String { address }
}

/// 고정 호스트 → 기기(이 Mac은 앱별, 원격은 호스트별) → 전체 호스트 순의 사이드바 모델.
public struct SidebarTree: Sendable {
    public let pinned: [HostNode]
    public let devices: [DeviceNode]
    public let hosts: [HostNode]

    private static let loopbackKey = "127.0.0.1"

    public static func build(flows: [Flow], attribution: [FlowID: ProcessIdentity], devices: [Device], pinned: [String], runtimes: [String: String]) -> SidebarTree {
        func hostNodes(_ flows: [Flow]) -> [HostNode] {
            Dictionary(grouping: flows, by: \.request.host)
                .map { HostNode(host: $0.key, count: $0.value.count) }
                .sorted { $0.host < $1.host }
        }

        let all = hostNodes(flows)
        let pinnedNodes = pinned.map { host in HostNode(host: host, count: all.first { $0.host == host }?.count ?? 0) }

        let byDevice = Dictionary(grouping: flows) { FlowFilter.isLoopback($0.clientAddress) ? loopbackKey : $0.clientAddress }
        let deviceNodes = byDevice.map { address, flows -> (Date, DeviceNode) in
            let known = devices.first { FlowFilter.sameDevice($0.address, address) }
            let isMac = FlowFilter.isLoopback(address)
            let kind = known?.kind ?? (isMac ? .thisMac : .unknown)
            let name = known?.displayName ?? (isMac ? "이 Mac" : address)
            var apps: [AppNode] = []
            if kind == .thisMac {
                let byApp = Dictionary(grouping: flows) { attribution[$0.id]?.groupKey ?? FlowFilter.unknownProcessKey }
                apps = byApp.map { key, flows in
                    let identity = attribution[flows[0].id]
                    return AppNode(groupKey: key, displayName: identity?.displayName(runtimes: runtimes) ?? "기타", path: identity?.path, count: flows.count, hosts: hostNodes(flows))
                }
                // ponytail: 동수면 groupKey로 결정적 순서. "기타"는 항상 마지막.
                apps.sort {
                    if ($0.groupKey == FlowFilter.unknownProcessKey) != ($1.groupKey == FlowFilter.unknownProcessKey) { return $1.groupKey == FlowFilter.unknownProcessKey }
                    return $0.count != $1.count ? $0.count > $1.count : $0.groupKey < $1.groupKey
                }
            }
            let node = DeviceNode(address: address, displayName: name, kind: kind, count: flows.count, apps: apps, hosts: kind == .thisMac ? [] : hostNodes(flows))
            return (flows.map(\.startedAt).max() ?? .distantPast, node)
        }
        .sorted { $0.0 > $1.0 }
        .map(\.1)

        return SidebarTree(pinned: pinnedNodes, devices: deviceNodes, hosts: all)
    }
}
