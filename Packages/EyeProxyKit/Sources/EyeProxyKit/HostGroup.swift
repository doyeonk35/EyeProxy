import EyeProxyCore
import Foundation

/// 사이드바 Groups 항목: 도메인 패턴과 앱(ProcessIdentity.groupKey)의 묶음.
public struct HostGroup: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var hostPatterns: [String]
    public var apps: [String]

    public init(id: UUID = UUID(), name: String, hostPatterns: [String], apps: [String]) {
        self.id = id
        self.name = name
        self.hostPatterns = hostPatterns
        self.apps = apps
    }

    public var isEmpty: Bool { hostPatterns.isEmpty && apps.isEmpty }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let items = hostPatterns + apps
        guard let first = items.first else { return "" }
        return items.count > 1 ? "\(first) 외 \(items.count - 1)" : first
    }

    /// New Domain or App ⇧⌘K 시트의 처음 값: 앞 탭 사이드바 선택이 도메인·경로면 그 호스트, 앱이면 그 앱, 그룹이면 새 id 복사본.
    public static func draft(from item: SidebarItem?) -> HostGroup {
        switch item {
        case .host(let h)?, .path(let h, _)?: return HostGroup(name: "", hostPatterns: HostList.normalize(h).map { [$0] } ?? [], apps: [])
        case .scope(let s)?:
            if let h = s.host { return draft(from: .host(h)) }
            // "기타"(귀속 없음)는 그룹 매칭에 걸리지 않으므로 넣지 않는다.
            let apps = s.process.map { $0 == FlowFilter.unknownProcessKey ? [] : [$0] } ?? []
            return HostGroup(name: "", hostPatterns: [], apps: apps)
        case .group(let g)?: return HostGroup(name: g.name, hostPatterns: g.hostPatterns, apps: g.apps)
        case .allFlows?, nil: return HostGroup(name: "", hostPatterns: [], apps: [])
        }
    }
}

public struct HostGroupMatcher: Sendable {
    private let patterns: HostPatternSet
    private let apps: Set<String>

    public init(_ group: HostGroup) {
        patterns = HostPatternSet(group.hostPatterns)
        apps = Set(group.apps)
    }

    public func matches(host: String, process: String?) -> Bool {
        patterns.matches(host) || (process.map(apps.contains) ?? false)
    }
}
