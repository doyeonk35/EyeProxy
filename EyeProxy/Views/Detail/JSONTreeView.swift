import EyeProxyKit
import SwiftUI

/// 펼친 id 집합으로 보이는 행만 평탄화해 그린다. 깊이 512·수천 노드에서도 뷰가 재귀로 중첩되지 않고,
/// 모두 펼치기·찾기가 펼침 상태를 밖에서 바꿀 수 있다(OutlineGroup은 못 한다).
struct JSONTreeView: View {
    let nodes: [JSONTreeNode]
    @Binding var expanded: Set<Int>
    @Binding var findVisible: Bool

    private enum FindMode { case search, filter }

    @State private var query = ""
    @State private var findMode = FindMode.search
    @State private var matches: [Int] = []
    @State private var current = 0
    @State private var filtered: [JSONTreeNode]?
    @State private var savedExpanded: Set<Int> = []
    @FocusState private var fieldFocused: Bool

    private struct Row: Identifiable {
        let node: JSONTreeNode
        let depth: Int
        var id: Int { node.id }
    }

    /// 전위 순회로 펼친 노드의 자식만 내려간다(재귀 없음).
    private static func rows(_ nodes: [JSONTreeNode], _ expanded: Set<Int>) -> [Row] {
        var out: [Row] = []
        var stack = nodes.reversed().map { Row(node: $0, depth: 0) }
        while let r = stack.popLast() {
            out.append(r)
            if expanded.contains(r.id), let c = r.node.children {
                stack.append(contentsOf: c.reversed().map { Row(node: $0, depth: r.depth + 1) })
            }
        }
        return out
    }

    private var currentID: Int? {
        findVisible && findMode == .search && matches.indices.contains(current) ? matches[current] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if findVisible { findBar; Divider() }
            ScrollViewReader { proxy in
                let hits = findVisible && findMode == .search ? Set(matches) : []
                List(Self.rows(filtered ?? nodes, expanded)) { r in
                    row(r)
                        .listRowBackground(
                            r.id == currentID ? Color.accentColor.opacity(0.4)
                                : hits.contains(r.id) ? Color.yellow.opacity(0.18) : Color.clear)
                }
                .onChange(of: currentID) { _, id in
                    guard let id else { return }
                    // 조상 펼침이 행 목록에 반영된 다음 굴린다.
                    Task { @MainActor in proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .onChange(of: findVisible) { _, open in
            if open { savedExpanded = expanded; fieldFocused = true } else { reset() }
        }
        .onDisappear { if findVisible { findVisible = false; reset() } }
    }

    private func row(_ r: Row) -> some View {
        let n = r.node
        let open = expanded.contains(n.id)
        return HStack(spacing: 6) {
            if n.children?.isEmpty == false {
                Button { if open { expanded.remove(n.id) } else { expanded.insert(n.id) } } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(open ? "접기" : "펼치기")
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
            if !n.key.isEmpty { Text(n.key).foregroundStyle(.secondary) }
            Text(n.preview).lineLimit(2)
        }
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .padding(.leading, CGFloat(r.depth) * 14)
    }

    private var findBar: some View {
        HStack(spacing: 6) {
            TextField("트리에서 찾기", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { step(1) }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    step(-1)
                    return .handled
                }
                .help("키·값에 이 글자가 든 노드를 찾습니다 (대소문자 무시)")
            Picker("", selection: $findMode) {
                Text("Search").tag(FindMode.search)
                Text("Filter").tag(FindMode.filter)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("Search는 일치를 강조하고, Filter는 일치한 노드만 남깁니다")
            if findMode == .search {
                Button { step(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(matches.isEmpty).help("이전 일치 (⇧Enter)")
                Button { step(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(matches.isEmpty).help("다음 일치 (Enter)")
                Text(verbatim: matches.isEmpty ? "0 / 0" : "\(current + 1) / \(matches.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text("\(matches.count)개 일치").font(.caption).foregroundStyle(.secondary)
            }
            Button { findVisible = false } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("찾기 막대 닫기 (Esc)")
        }
        .controlSize(.small)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .onExitCommand { findVisible = false }
        // 새 값을 인자로 넘긴다 — 빠르게 칠 때 클로저 안에서 읽은 query가 한 박자 늦은 값이었다(실측).
        .onChange(of: query) { _, q in apply(q, findMode) }
        .onChange(of: findMode) { _, m in apply(query, m) }
    }

    /// 검색어·모드가 바뀔 때: 일치를 다시 구하고 펼침을 (열 때 저장한 상태 + 필요한 만큼)으로 맞춘다.
    private func apply(_ query: String, _ mode: FindMode) {
        matches = JSONTreeSearch.matches(in: nodes, query: query)
        current = 0
        if mode == .filter, !query.isEmpty {
            let f = JSONTreeSearch.filter(nodes, query: query)
            filtered = f
            expanded = JSONTreeSearch.containerIDs(in: f)
        } else {
            filtered = nil
            expanded = savedExpanded.union(JSONTreeSearch.ancestors(of: Set(matches), in: nodes))
        }
    }

    private func step(_ d: Int) {
        guard !matches.isEmpty else { return }
        current = (current + d + matches.count) % matches.count
    }

    /// 막대를 닫으면 원래 트리·펼침 상태로.
    private func reset() {
        expanded = savedExpanded
        query = ""
        matches = []
        current = 0
        filtered = nil
    }
}
