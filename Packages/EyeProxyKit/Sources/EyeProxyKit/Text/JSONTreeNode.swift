import Foundation

public struct JSONTreeNode: Identifiable, Sendable {
    public let id: Int
    public let key: String
    public let preview: String
    public let children: [JSONTreeNode]?

    /// 원문 키 순서 유지. 루트가 객체/배열이면 그 자식들, 스칼라면 [그 노드].
    /// 중첩 깊이(BodyDecoder 상한 512)에 스택이 영향받지 않도록 명시적 프레임 스택으로 만든다.
    public static func parse(pretty: String) -> [JSONTreeNode] {
        struct Frame { let id: Int; let key: String; let isObject: Bool; var children: [JSONTreeNode] = [] }
        let text = pretty as NSString
        var stack: [Frame] = []
        var root: JSONTreeNode?
        var nextID = 0
        var pendingKey = ""

        func nodeKey() -> String {
            guard let top = stack.last else { return "" }
            return top.isObject ? pendingKey : String(top.children.count)
        }
        func finish(_ n: JSONTreeNode) {
            if stack.isEmpty { root = n } else { stack[stack.count - 1].children.append(n) }
        }

        for t in JSONScanner.scan(pretty) {
            switch t.kind {
            case .key:
                pendingKey = text.substring(with: NSRange(location: t.range.location + 1, length: max(0, t.range.length - 2)))
            case .colon, .comma: break
            case .open:
                stack.append(Frame(id: nextID, key: nodeKey(), isObject: text.character(at: t.range.location) == 0x7b))
                nextID += 1
            case .close:
                guard let f = stack.popLast() else { return [] }
                finish(JSONTreeNode(id: f.id, key: f.key, preview: f.isObject ? "{\(f.children.count) keys}" : "[\(f.children.count) items]", children: f.children))
            case .string, .number, .keyword:
                finish(JSONTreeNode(id: nextID, key: nodeKey(), preview: text.substring(with: t.range), children: nil))
                nextID += 1
            }
        }
        guard stack.isEmpty, let root else { return [] }
        return root.children ?? [root]
    }
}
