import SwiftUI

struct JSONNode: Identifiable, Sendable {
    let id = UUID()
    let key: String
    let preview: String
    let children: [JSONNode]?

    /// pretty 텍스트를 파싱해 트리를 만든다. 키 순서는 사전순(원문과 다를 수 있음).
    static func parse(_ text: String) -> [JSONNode] {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) else { return [] }
        let root = node("", obj)
        return root.children ?? [root]
    }

    private static func node(_ key: String, _ value: Any) -> JSONNode {
        switch value {
        case let d as [String: Any]:
            return JSONNode(key: key, preview: "{\(d.count) keys}", children: d.keys.sorted().map { node($0, d[$0]!) })
        case let a as [Any]:
            return JSONNode(key: key, preview: "[\(a.count) items]", children: a.indices.map { node("\($0)", a[$0]) })
        case let s as String:
            return JSONNode(key: key, preview: "\"\(s)\"", children: nil)
        case let n as NSNumber:
            return JSONNode(key: key, preview: CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue, children: nil)
        default:
            return JSONNode(key: key, preview: "null", children: nil)
        }
    }
}

struct JSONTreeView: View {
    let nodes: [JSONNode]

    var body: some View {
        List {
            OutlineGroup(nodes, children: \.children) { n in
                HStack(spacing: 6) {
                    if !n.key.isEmpty { Text(n.key).foregroundStyle(.secondary) }
                    Text(n.preview).lineLimit(2)
                }
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            }
        }
    }
}
