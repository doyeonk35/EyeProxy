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

/// 원격 기기(이 Mac 아님). 자식은 그 기기의 도메인뿐(기기 앱별 묶기는 범위 밖).
public struct DeviceNode: Identifiable, Sendable {
    public let address: String
    public let displayName: String
    public let kind: DeviceKind
    public let count: Int
    public let hosts: [HostNode]
    public var id: String { address }
}

/// 도메인 아래 경로 트리의 한 마디. `fullPath`로 시작하는(세그먼트 경계) 요청 수가 `count`.
public struct PathNode: Identifiable, Sendable {
    public let segment: String
    public let fullPath: String
    public let count: Int
    public let children: [PathNode]
    public var id: String { fullPath }
}

/// 사이드바에서 고른 줄. 목록 거르기에 더할 조건은 `apply(to:)`.
public enum SidebarItem: Hashable, Sendable {
    case allFlows
    case host(String)
    case scope(FlowScope)
    case path(host: String, prefix: String)

    public func apply(to f: inout FlowFilter) {
        switch self {
        case .allFlows: break
        case .host(let host): f.host = host
        case .scope(let s): (f.device, f.process, f.host) = (s.device, s.process, s.host)
        case .path(let host, let prefix): (f.host, f.pathPrefix) = (host, prefix)
        }
    }
}

/// Proxyman 하이어라키: Favorites ▸ Pinned, Remote devices ▸ 도메인, All ▸ Apps(이 Mac) ▸ 도메인 / Domains.
public struct SidebarTree: Sendable {
    public let pinned: [HostNode]
    public let remoteDevices: [DeviceNode]
    public let apps: [AppNode]
    /// Apps 줄 개수 = 이 Mac(루프백) 흐름 수.
    public let appsCount: Int
    public let domains: [HostNode]
    /// 경로가 있는(펼칠 경로 트리가 있는) 도메인. 터널·"/"뿐인 도메인은 펼침 표시를 하지 않는다.
    public let hostsWithPaths: Set<String>

    /// 이 Mac 흐름을 고르는 기기 주소(`FlowFilter.sameDevice`가 ::1도 같이 본다).
    public static let thisMac = "127.0.0.1"
    /// 경로 트리 깊이 상한. 그보다 깊은 경로는 마지막 마디에 합친다.
    public static let pathDepthLimit = 4

    public static func build(flows: [Flow], attribution: [FlowID: ProcessIdentity], devices: [Device], pinned: [String], runtimes: [String: String]) -> SidebarTree {
        let all = hostNodes(flows)
        let counts = Dictionary(uniqueKeysWithValues: all.map { ($0.host, $0.count) })
        let pinnedNodes = pinned.map { HostNode(host: $0, count: counts[$0] ?? 0) }

        let local = flows.filter { FlowFilter.isLoopback($0.clientAddress) }
        let remote = flows.filter { !FlowFilter.isLoopback($0.clientAddress) }

        let byApp = Dictionary(grouping: local) { attribution[$0.id]?.groupKey ?? FlowFilter.unknownProcessKey }
        var apps = byApp.map { key, flows in
            let identity = attribution[flows[0].id]
            return AppNode(groupKey: key, displayName: identity?.displayName(runtimes: runtimes) ?? "기타", path: identity?.path, count: flows.count, hosts: hostNodes(flows))
        }
        // ponytail: 동수면 groupKey로 결정적 순서. "기타"는 항상 마지막.
        apps.sort {
            if ($0.groupKey == FlowFilter.unknownProcessKey) != ($1.groupKey == FlowFilter.unknownProcessKey) { return $1.groupKey == FlowFilter.unknownProcessKey }
            return $0.count != $1.count ? $0.count > $1.count : $0.groupKey < $1.groupKey
        }

        let remoteDevices = Dictionary(grouping: remote, by: \.clientAddress).map { address, flows -> (Date, DeviceNode) in
            let known = devices.first { $0.address == address }
            let node = DeviceNode(address: address, displayName: known?.displayName ?? (address.isEmpty ? "가져온 요청" : address),
                                  kind: known?.kind ?? .unknown, count: flows.count, hosts: hostNodes(flows))
            return (flows.map(\.startedAt).max() ?? .distantPast, node)
        }
        .sorted { $0.0 > $1.0 }
        .map(\.1)

        // = pathSegments가 비지 않음(배열을 만들지 않고).
        let withPaths = Set(flows.lazy.filter { $0.request.path.prefix { $0 != "?" && $0 != "#" }.contains { $0 != "/" } }.map(\.request.host))
        return SidebarTree(pinned: pinnedNodes, remoteDevices: remoteDevices, apps: apps, appsCount: local.count, domains: all, hostsWithPaths: withPaths)
    }

    private static func hostNodes(_ flows: [Flow]) -> [HostNode] {
        Dictionary(grouping: flows, by: \.request.host)
            .map { HostNode(host: $0.key, count: $0.value.count) }
            .sorted { $0.host < $1.host }
    }

    /// 그 호스트 요청의 경로 트리(쿼리 제외, 깊이 `pathDepthLimit`까지). 펼친 도메인만 계산한다.
    public static func pathTree(for host: String, flows: [Flow]) -> [PathNode] {
        final class Box { var count = 0; var children: [Substring: Box] = [:] }
        let root = Box()
        for flow in flows where flow.request.host == host {
            var box = root
            for segment in FlowFilter.pathSegments(flow.request.path).prefix(pathDepthLimit) {
                let next = box.children[segment] ?? Box()
                box.children[segment] = next
                next.count += 1
                box = next
            }
        }
        func nodes(_ box: Box, _ parent: String) -> [PathNode] {
            box.children.map { segment, child in
                let full = parent + "/" + segment
                return PathNode(segment: String(segment), fullPath: full, count: child.count, children: nodes(child, full))
            }
            .sorted { $0.segment < $1.segment }
        }
        return nodes(root, "")
    }

    /// 사이드바 필터 칸: 이름에 query가 든(대소문자 무시) 줄만. 부모 이름이 맞으면 자식 전부,
    /// 아니면 맞는 자식만 남긴다. 개수는 그대로(고르면 목록이 부모 전체를 보이므로).
    public func filtered(_ query: String) -> SidebarTree {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return self }
        func hit(_ name: String) -> Bool { name.localizedCaseInsensitiveContains(q) }
        func hosts(_ nodes: [HostNode]) -> [HostNode] { nodes.filter { hit($0.host) } }
        let apps = apps.compactMap { a -> AppNode? in
            let h = hit(a.displayName) ? a.hosts : hosts(a.hosts)
            return h.isEmpty ? nil : AppNode(groupKey: a.groupKey, displayName: a.displayName, path: a.path, count: a.count, hosts: h)
        }
        let devices = remoteDevices.compactMap { d -> DeviceNode? in
            let h = hit(d.displayName) || hit(d.address) ? d.hosts : hosts(d.hosts)
            return h.isEmpty ? nil : DeviceNode(address: d.address, displayName: d.displayName, kind: d.kind, count: d.count, hosts: h)
        }
        return SidebarTree(pinned: hosts(pinned), remoteDevices: devices, apps: apps, appsCount: appsCount, domains: hosts(domains), hostsWithPaths: hostsWithPaths)
    }
}
