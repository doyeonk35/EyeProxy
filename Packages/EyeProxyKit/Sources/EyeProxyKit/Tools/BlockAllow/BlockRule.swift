import EyeProxyCore
import Foundation

/// Proxyman 키 `blockAction` 값은 가정(스펙 §9).
public enum BlockAction: String, Codable, Sendable {
    case blockAndHide, blockAndDisplay, hideOnly
}

/// Block List 규칙. `appPath`가 있으면 그 앱 번들 경로에서 온 요청도 막는다(Block App).
public struct BlockRule: ToolRule {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var match: MatchRule
    public var action: BlockAction
    public var appPath: String?

    public init(
        id: String = String(UUID().uuidString.prefix(8)), name: String = "Untitled", isEnabled: Bool = true,
        match: MatchRule = MatchRule(), action: BlockAction = .blockAndDisplay, appPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.match = match
        self.action = action
        self.appPath = appPath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ProxymanKey.self)
        id = try c.decode(String.self, forKey: "id")
        name = try c.decode(String.self, forKey: "name")
        isEnabled = try c.decode(Bool.self, forKey: "isEnabled")
        match = try MatchRule(proxymanFields: c)
        // 모르는 값이면 throw → 노드를 건너뛴다.
        action = try c.decode(BlockAction.self, forKey: "blockAction")
        appPath = try c.decodeIfPresent(String.self, forKey: "appPath")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ProxymanKey.self)
        try c.encode(id, forKey: "id")
        try c.encode(name, forKey: "name")
        try c.encode(isEnabled, forKey: "isEnabled")
        try match.encode(proxymanFields: &c)
        try c.encode(action, forKey: "blockAction")
        try c.encode(appPath, forKey: "appPath")
    }
}

extension RuleFile where R == BlockRule {
    public static var blockList: Self { .init(name: "block-list.json") }
}
