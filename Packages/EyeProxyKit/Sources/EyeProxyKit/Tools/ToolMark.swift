import EyeProxyCore

/// 요청·응답을 바꾼 도구 표시(목록 Edited 열). 주석 문자열 `"<raw>"` 또는 `"<raw>: <detail>"`로 왕복한다.
/// "Map Local 파일 없음: …", "자동 복호화(규칙: …)" 같은 메모는 편집이 아니므로 표시하지 않는다.
public enum ToolMark: String, CaseIterable, Sendable {
    case mapLocal = "Map Local", mapRemote = "Map Remote", breakpoint = "Breakpoint", blocked = "Blocked"

    public static func annotation(_ mark: ToolMark, detail: String?) -> FlowAnnotation {
        .tool(detail.map { "\(mark.rawValue): \($0)" } ?? mark.rawValue)
    }

    public static func mark(of annotation: FlowAnnotation) -> ToolMark? {
        guard case .tool(let label) = annotation else { return nil }
        return allCases.first { label == $0.rawValue || label.hasPrefix($0.rawValue + ": ") }
    }
}
