import Foundation

/// 도구별 켜기/끄기. 규칙 자체는 `RuleStore`, 스위치는 `AppSettings`에 저장한다.
public struct ToolSwitches: Codable, Equatable, Sendable {
    public var breakpoint = false
    public var mapLocal = false
    public var mapRemote = false
    public var blockList = false
    public var allowList = false
    public var networkConditions = false
    public var noCaching = false
    public var repeatNoCache = false

    public init() {}
}
