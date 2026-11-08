import Foundation

/// Proxyman `NetworkThrottlingService` 배열의 원소. 한 번에 하나만 켜진다(`RuleStore.activateNetworkCondition`).
public struct NetworkConditionRule: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var url: String
    public var isEnabled: Bool
    public var isSystemWide: Bool
    public var networkProfile: NetworkProfile

    public init(id: String = UUID().uuidString, name: String, url: String, isEnabled: Bool = false,
                isSystemWide: Bool = false, networkProfile: NetworkProfile) {
        self.id = id
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
        self.isSystemWide = isSystemWide
        self.networkProfile = networkProfile
    }
}
