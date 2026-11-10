import Foundation

/// 응답 Treeview의 ⌘F Search/Filter와 "모두 펼치기" 규칙.
/// 깊이 512까지 중첩될 수 있어 `JSONTreeNode.parse`처럼 재귀 없이 명시적 스택으로 돈다.
public enum JSONTreeSearch {
    /// 키나 미리보기에 검색어가 든 노드 id, 화면 순서(전위). 대소문자 무시. 빈 검색어 → [].
    /// 컨테이너는 키로만 맞춘다 — 미리보기("{3 keys}"/"[2 items]")는 원문 값이 아니라서.
    /// 배열 원소의 키는 인덱스("0","1"…)라 맞추지 않는다 — "1"이 1·10~19번 원소에 다 걸리지 않게(값은 맞춘다).
    public static func matches(in nodes: [JSONTreeNode], query: String) -> [Int] {
        guard !query.isEmpty else { return [] }
        var ids: [Int] = []
        walk(nodes) { n, _, inArray in
            if (!inArray && contains(n.key, query)) || (n.children == nil && contains(n.preview, query)) { ids.append(n.id) }
        }
        return ids
    }

    /// 그 노드들을 보이게 하려면 펼쳐야 할 조상 id(노드 자신은 빼고).
    public static func ancestors(of ids: Set<Int>, in nodes: [JSONTreeNode]) -> Set<Int> {
        guard !ids.isEmpty else { return [] }
        var parent: [Int: Int] = [:]
        walk(nodes) { n, p, _ in if let p { parent[n.id] = p } }
        var out: Set<Int> = []
        for id in ids {
            var cur = parent[id]
            while let p = cur, out.insert(p).inserted { cur = parent[p] }
        }
        return out
    }

    /// 일치 노드와 그 조상만 남긴다. 일치한 컨테이너는 자식 전체를 그대로 둔다. 빈 검색어 → 원본.
    public static func filter(_ nodes: [JSONTreeNode], query: String) -> [JSONTreeNode] {
        guard !query.isEmpty else { return nodes }
        return filter(nodes, hits: Set(matches(in: nodes, query: query)))
    }

    /// `matches`를 이미 구했으면 다시 돌지 않고 그 결과로 거른다. 빈 집합 → [].
    public static func filter(_ nodes: [JSONTreeNode], hits: Set<Int>) -> [JSONTreeNode] {
        let path = ancestors(of: hits, in: nodes)
        struct Frame { let node: JSONTreeNode?; let children: [JSONTreeNode]; var next = 0; var kept: [JSONTreeNode] = [] }
        var stack = [Frame(node: nil, children: nodes)]
        while true {
            let top = stack.count - 1
            if stack[top].next < stack[top].children.count {
                let c = stack[top].children[stack[top].next]
                stack[top].next += 1
                if hits.contains(c.id) { stack[top].kept.append(c) }
                else if path.contains(c.id) { stack.append(Frame(node: c, children: c.children ?? [])) }
            } else {
                let f = stack.removeLast()
                guard let n = f.node else { return f.kept }
                stack[stack.count - 1].kept.append(JSONTreeNode(id: n.id, key: n.key, preview: n.preview, children: f.kept))
            }
        }
    }

    /// 자식이 하나 이상 있는 모든 노드 id(모두 펼치기용).
    public static func containerIDs(in nodes: [JSONTreeNode]) -> Set<Int> {
        var ids: Set<Int> = []
        walk(nodes) { n, _, _ in if n.children?.isEmpty == false { ids.insert(n.id) } }
        return ids
    }

    private static func contains(_ s: String, _ q: String) -> Bool {
        s.range(of: q, options: .caseInsensitive) != nil
    }

    /// 전위 순회, (노드, 부모 id, 부모가 배열인가). 루트가 배열이면 parse가 벗겨낸 맨 위 노드들의 키가 "0","1"…이다.
    private static func walk(_ nodes: [JSONTreeNode], _ visit: (JSONTreeNode, Int?, Bool) -> Void) {
        let rootIsArray = !nodes.isEmpty && nodes.indices.allSatisfy { nodes[$0].key == String($0) }
        var stack: [(JSONTreeNode, Int?, Bool)] = nodes.reversed().map { ($0, nil, rootIsArray) }
        while let (n, p, inArray) = stack.popLast() {
            visit(n, p, inArray)
            if let c = n.children {
                let isArray = n.preview.hasPrefix("[")  // 컨테이너 미리보기: 배열 "[n items]", 객체 "{n keys}"
                stack.append(contentsOf: c.reversed().map { ($0, n.id, isArray) })
            }
        }
    }
}
