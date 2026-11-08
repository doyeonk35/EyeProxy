import EyeProxyCore
import Foundation

/// Breakpoint 규칙. Proxyman 키(`isRequest`, `isResponse`)는 가정(스펙 §9). 없으면 false.
public struct BreakpointRule: ToolRule {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var match: MatchRule
    public var onRequest: Bool
    public var onResponse: Bool

    public init(
        id: String = String(UUID().uuidString.prefix(8)), name: String = "Untitled", isEnabled: Bool = true,
        match: MatchRule = MatchRule(), onRequest: Bool = true, onResponse: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.match = match
        self.onRequest = onRequest
        self.onResponse = onResponse
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ProxymanKey.self)
        id = try c.decode(String.self, forKey: "id")
        name = try c.decode(String.self, forKey: "name")
        isEnabled = try c.decode(Bool.self, forKey: "isEnabled")
        match = try MatchRule(proxymanFields: c)
        onRequest = try c.decodeIfPresent(Bool.self, forKey: "isRequest") ?? false
        onResponse = try c.decodeIfPresent(Bool.self, forKey: "isResponse") ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ProxymanKey.self)
        try c.encode(id, forKey: "id")
        try c.encode(name, forKey: "name")
        try c.encode(isEnabled, forKey: "isEnabled")
        try match.encode(proxymanFields: &c)
        try c.encode(onRequest, forKey: "isRequest")
        try c.encode(onResponse, forKey: "isResponse")
    }
}

extension RuleFile where R == BreakpointRule {
    public static var breakpoint: Self { .init(name: "breakpoint.json") }
}
