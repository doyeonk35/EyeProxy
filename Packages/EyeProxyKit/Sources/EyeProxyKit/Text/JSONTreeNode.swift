import Foundation

public struct JSONTreeNode: Identifiable, Sendable {
    public let id: Int
    public let key: String
    public let preview: String
    public let children: [JSONTreeNode]?

    /// 원문 키 순서 유지. 루트가 객체/배열이면 그 자식들, 스칼라면 [그 노드].
    public static func parse(pretty: String) -> [JSONTreeNode] {
        var p = Parser(text: pretty as NSString, toks: JSONScanner.scan(pretty))
        guard let root = p.value(key: "") else { return [] }
        return root.children ?? [root]
    }

    private struct Parser {
        let text: NSString
        let toks: [JSONScanner.Tok]
        var pos = 0
        var nextID = 0

        mutating func value(key: String) -> JSONTreeNode? {
            guard pos < toks.count else { return nil }
            let t = toks[pos]
            pos += 1
            let id = nextID
            nextID += 1
            switch t.kind {
            case .open:
                let isObject = text.character(at: t.range.location) == 0x7b
                var kids: [JSONTreeNode] = []
                while pos < toks.count, toks[pos].kind != .close {
                    if toks[pos].kind == .comma { pos += 1; continue }
                    var k = String(kids.count)
                    if isObject {
                        guard toks[pos].kind == .key, pos + 1 < toks.count, toks[pos + 1].kind == .colon else { return nil }
                        k = text.substring(with: NSRange(location: toks[pos].range.location + 1, length: toks[pos].range.length - 2))
                        pos += 2
                    }
                    guard let child = value(key: k) else { return nil }
                    kids.append(child)
                }
                guard pos < toks.count else { return nil }
                pos += 1
                return JSONTreeNode(id: id, key: key, preview: isObject ? "{\(kids.count) keys}" : "[\(kids.count) items]", children: kids)
            case .string, .number, .keyword:
                return JSONTreeNode(id: id, key: key, preview: text.substring(with: t.range), children: nil)
            default: return nil
            }
        }
    }
}
