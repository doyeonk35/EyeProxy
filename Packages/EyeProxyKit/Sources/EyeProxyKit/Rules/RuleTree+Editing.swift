import Foundation

extension RuleNode {
    public var name: String {
        get { switch self { case .rule(let r): r.name; case .folder(let f): f.name } }
        set {
            switch self {
            case .rule(var r): r.name = newValue; self = .rule(r)
            case .folder(var f): f.name = newValue; self = .folder(f)
            }
        }
    }

    public var isEnabled: Bool {
        get { switch self { case .rule(let r): r.isEnabled; case .folder(let f): f.isEnabled } }
        set {
            switch self {
            case .rule(var r): r.isEnabled = newValue; self = .rule(r)
            case .folder(var f): f.isEnabled = newValue; self = .folder(f)
            }
        }
    }

    public var rule: Rule? { if case .rule(let r) = self { r } else { nil } }
    public var children: [RuleNode] { if case .folder(let f) = self { f.children } else { [] } }
}

/// 도구 창의 편집 동작. 노드는 트리 어디에 있든 id로 찾는다.
extension RuleTree {
    /// Proxyman과 같은 8자리 16진 id.
    public static func newID() -> String { String(UUID().uuidString.prefix(8)) }

    public func node(_ id: String) -> RuleNode<Rule>? { Self.find(id, in: nodes) }

    /// 노드가 든 폴더의 id. 최상위(또는 없는 id)면 nil.
    public func parent(of id: String) -> String? {
        var copy = nodes, result: String?
        Self.walk(&copy, parent: nil) { p, list in
            guard list.contains(where: { $0.id == id }) else { return false }
            result = p
            return true
        }
        return result
    }

    /// 깊이 우선 순서의 모든 노드 id.
    public var allIDs: [String] {
        func ids(_ list: [RuleNode<Rule>]) -> [String] { list.flatMap { [$0.id] + ids($0.children) } }
        return ids(nodes)
    }

    public mutating func update(_ id: String, _ change: (inout RuleNode<Rule>) -> Void) {
        Self.walk(&nodes, parent: nil) { _, list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return false }
            change(&list[i])
            return true
        }
    }

    /// 지운 노드를 트리 순서로 돌려준다. 폴더를 지우면 하위도 함께 빠진다.
    @discardableResult
    public mutating func remove(_ ids: Set<String>) -> [RuleNode<Rule>] {
        var removed: [RuleNode<Rule>] = []
        func strip(_ list: [RuleNode<Rule>]) -> [RuleNode<Rule>] {
            list.compactMap { node in
                if ids.contains(node.id) { removed.append(node); return nil }
                guard case .folder(var f) = node else { return node }
                f.children = strip(f.children)
                return .folder(f)
            }
        }
        nodes = strip(nodes)
        return removed
    }

    /// `folder`(nil = 최상위) 안 `before` 앞에 넣는다. `before`가 없으면 끝에, 폴더가 없으면 최상위 끝에.
    public mutating func insert(_ new: [RuleNode<Rule>], into folder: String?, before: String? = nil) {
        let done = Self.walk(&nodes, parent: nil) { p, list in
            guard p == folder else { return false }
            let i = before.flatMap { b in list.firstIndex { $0.id == b } } ?? list.endIndex
            list.insert(contentsOf: new, at: i)
            return true
        }
        if !done { nodes.append(contentsOf: new) }
    }

    /// 드래그로 순서 바꾸기. 폴더를 자기 자신·하위로 옮기거나 옮기는 노드 앞으로 놓으면 무시한다.
    public mutating func move(_ ids: Set<String>, into folder: String?, before: String?) {
        if let before, ids.contains(before) { return }
        if let folder, ids.compactMap({ node($0) }).contains(where: { $0.id == folder || Self.find(folder, in: $0.children) != nil }) { return }
        insert(remove(ids), into: folder, before: before)
    }

    /// 새 id와 " 복사본" 이름으로 원본 바로 뒤에 복제한다. 새 노드 id를 돌려준다.
    @discardableResult
    public mutating func duplicate(_ ids: Set<String>) -> [String] {
        var created: [String] = []
        for id in allIDs where ids.contains(id) {
            guard let original = node(id) else { continue }
            let copy = Self.copy(original, suffix: " 복사본")
            Self.walk(&nodes, parent: nil) { _, list in
                guard let i = list.firstIndex(where: { $0.id == id }) else { return false }
                list.insert(copy, at: i + 1)
                return true
            }
            created.append(copy.id)
        }
        return created
    }

    // MARK: - 내부

    private static func find(_ id: String, in list: [RuleNode<Rule>]) -> RuleNode<Rule>? {
        for node in list {
            if node.id == id { return node }
            if let hit = find(id, in: node.children) { return hit }
        }
        return nil
    }

    private static func copy(_ node: RuleNode<Rule>, suffix: String) -> RuleNode<Rule> {
        switch node {
        case .rule(var r):
            r.id = newID()
            r.name += suffix
            return .rule(r)
        case .folder(var f):
            f.id = newID()
            f.name += suffix
            f.children = f.children.map { copy($0, suffix: "") }
            return .folder(f)
        }
    }

    /// 최상위부터 깊이 우선으로 각 형제 목록에 `body`를 적용하고, true를 돌려주면 멈춘다.
    /// `body`는 true를 돌려줄 때만 목록을 바꿔야 한다.
    @discardableResult
    private static func walk(_ list: inout [RuleNode<Rule>], parent: String?,
                             _ body: (String?, inout [RuleNode<Rule>]) -> Bool) -> Bool {
        if body(parent, &list) { return true }
        for i in list.indices {
            guard case .folder(var f) = list[i] else { continue }
            if walk(&f.children, parent: f.id, body) {
                list[i] = .folder(f)
                return true
            }
        }
        return false
    }
}
