import EyeProxyCore
import Foundation

/// Allow List 규칙. 공통 필드만 쓴다(스펙 §5.5).
public struct AllowRule: ToolRule {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var match: MatchRule

    public init(id: String = String(UUID().uuidString.prefix(8)), name: String = "Untitled", isEnabled: Bool = true,
                match: MatchRule = MatchRule()) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.match = match
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ProxymanKey.self)
        id = try c.decode(String.self, forKey: "id")
        name = try c.decode(String.self, forKey: "name")
        isEnabled = try c.decode(Bool.self, forKey: "isEnabled")
        match = try MatchRule(proxymanFields: c)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ProxymanKey.self)
        try c.encode(id, forKey: "id")
        try c.encode(name, forKey: "name")
        try c.encode(isEnabled, forKey: "isEnabled")
        try match.encode(proxymanFields: &c)
    }
}

extension RuleFile where R == AllowRule {
    public static var allowList: Self { .init(name: "allow-list.json") }
}
