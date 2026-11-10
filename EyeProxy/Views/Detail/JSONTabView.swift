import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

/// JSON·Treeview 탭(스펙 §7). Content-Type과 상관없이 본문이 JSON으로 읽히면
/// JSON 탭은 색 입힌 Pretty(⌘F는 NSTextFinder), Treeview 탭은 트리(모두 펼치기·접기, ⌘F 찾기·거르기)를 보인다.
/// 줄 접기·JSON Path·미니맵은 2단계.
struct JSONTabView: View {
    let data: Data
    let headers: [HTTPHeader]
    /// true = Treeview 탭, false = JSON 탭.
    let tree: Bool

    private enum Prepared: Sendable { case notJSON, pretty(String, [JSONToken], truncated: Bool), tree([JSONTreeNode]) }
    private enum Loaded { case notJSON, pretty(NSAttributedString, truncated: Bool), tree([JSONTreeNode]) }

    @State private var loaded: Loaded?
    @State private var expanded: Set<Int> = []
    @State private var findVisible = false

    var body: some View {
        Group {
            switch loaded {
            case nil: ProgressView()
            case .notJSON?: ContentUnavailableView("JSON이 아닙니다", systemImage: "curlybraces")
            case .pretty(let text, let truncated)?: CodeBody(text: text, truncated: truncated)
            case .tree(let nodes)?:
                VStack(spacing: 0) {
                    HStack {
                        Button { expanded = JSONTreeSearch.containerIDs(in: nodes) } label: { Label("모두 펼치기", systemImage: "rectangle.expand.vertical") }
                            .help("트리 모두 펼치기")
                        Button { expanded = [] } label: { Label("모두 접기", systemImage: "rectangle.compress.vertical") }
                            .help("트리 모두 접기")
                        Toggle(isOn: $findVisible) { Label("찾기", systemImage: "magnifyingglass") }
                            .toggleStyle(.button)
                            .help("트리에서 찾기·거르기 (⌘F)")
                        Spacer()
                    }
                    .labelStyle(.iconOnly)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    Divider()
                    JSONTreeView(nodes: nodes, expanded: $expanded, findVisible: $findVisible)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 본문이 바뀔 때만(세션 이벤트마다가 아니라), 메인 밖에서 정렬·색 토큰·트리를 만든다.
        .task(id: data.count) {
            let (body, headers, tree) = (data, headers, tree)
            let p = await Task.detached { () -> Prepared in
                guard let pretty = BodyDecoder.json(body: body, headers: headers) else { return .notJSON }
                if tree { return .tree(JSONTreeNode.parse(pretty: pretty)) }
                let (s, cut) = BodyView.capped(pretty)
                return .pretty(s, s.utf8.count <= BodyView.highlightLimit ? JSONHighlighter.tokens(s) : [], truncated: cut)
            }.value
            if Task.isCancelled { return }
            expanded = []
            findVisible = false
            switch p {
            case .notJSON: loaded = .notJSON
            case .pretty(let s, let tokens, let cut): loaded = .pretty(BodyView.highlighted(s, tokens), truncated: cut)
            case .tree(let nodes): loaded = .tree(nodes)
            }
        }
    }
}
