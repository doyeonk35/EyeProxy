/// Highlight 색(Proxyman Flow ▸ Highlight와 같은 이름·순서).
public enum HighlightColor: String, CaseIterable, Codable, Sendable {
    case red, yellow, green, blue, purple, gray
}

/// 흐름 한 줄의 Highlight: 색(하나만)과 취소선(색과 독립).
public struct FlowHighlight: Codable, Equatable, Sendable {
    public var color: HighlightColor?
    public var strikethrough: Bool

    public init(color: HighlightColor? = nil, strikethrough: Bool = false) {
        self.color = color
        self.strikethrough = strikethrough
    }

    /// 색도 취소선도 없으면 true — 이런 값은 저장하지 않는다.
    public var isEmpty: Bool { color == nil && !strikethrough }
}
