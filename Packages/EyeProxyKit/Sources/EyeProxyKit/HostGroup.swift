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
