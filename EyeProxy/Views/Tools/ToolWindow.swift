import EyeProxyKit
import SwiftUI

/// 도구 창 표의 한 행. 트리를 깊이 우선으로 펼친 것(접힌 폴더의 하위는 빠진다).
struct ToolRow<Rule: ToolRule>: Identifiable {
    let node: RuleNode<Rule>
    let depth: Int
    var id: String { node.id }
    var rule: Rule? { node.rule }
}

enum ToolEditorStyle {
    case sheet
    /// 편집기가 별도 창이다. 규칙은 `model.editorDrafts[id]`로 넘기고 `openWindow(id:value: 규칙 id)`로 연다. `editor`는 쓰지 않는다.
    case window(id: String)
}

/// Proxyman 도구 창 레이아웃(스펙 §6.2). 규칙 트리는 `model.rules`에서 읽고 모든 변경은 `set`으로 쓴다.
/// 앞의 Enabled·Name 열은 이 뷰가 그리고, 도구별 열은 `columns`로 받는다(`ruleColumn` 참고).
struct ToolWindow<Rule: ToolRule, Columns: TableColumnContent, Editor: View>: View
where Columns.TableRowValue == ToolRow<Rule>, Columns.TableColumnSortComparator == Never {
    /// 이 창의 Window id. 우클릭 ▸ Tools(`model.pendingNewRule`)가 어느 창을 겨냥하는지 가린다.
    let windowID: String
    let title: String
    let description: String
    let toolSwitch: WritableKeyPath<ToolSwitches, Bool>
    let file: RuleFile<Rule>
    let newRule: () -> Rule
    var editorStyle: ToolEditorStyle = .sheet
    var helpURL: URL?
    /// 표 아래 회색 안내(Map Remote의 /etc/hosts 안내).
    var note: LocalizedStringKey?
    /// 우클릭 ▸ Tools로 만든 새 규칙을 편집기에 넘기기 전에 도구별로 더 채운다(Map Local 응답 메시지).
    var prefill: ((inout Rule, PendingNewRule) -> Void)?
    let moreItems: AnyView
    /// 하단 More 왼쪽에 놓는 도구별 버튼(Breakpoint의 Templates…).
    let accessory: AnyView
    let editor: (Binding<Rule>, _ onSave: @escaping (Rule) -> Void, _ onCancel: @escaping () -> Void) -> Editor
    let columns: Columns

    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var selection = Set<String>()
    @State private var collapsed = Set<String>()
    @State private var draft: Rule?
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var filter = ""
    @State private var importing: URL?
    @State private var exportError: String?

    init(windowID: String, title: String, description: String, toolSwitch: WritableKeyPath<ToolSwitches, Bool>,
         file: RuleFile<Rule>, newRule: @escaping () -> Rule, editorStyle: ToolEditorStyle = .sheet, helpURL: URL? = nil,
         note: LocalizedStringKey? = nil, prefill: ((inout Rule, PendingNewRule) -> Void)? = nil,
         @ViewBuilder moreItems: () -> some View = { EmptyView() },
         @ViewBuilder accessory: () -> some View = { EmptyView() },
         @ViewBuilder editor: @escaping (Binding<Rule>, _ onSave: @escaping (Rule) -> Void, _ onCancel: @escaping () -> Void) -> Editor,
         @TableColumnBuilder<ToolRow<Rule>, Never> columns: () -> Columns) {
        self.windowID = windowID
        self.title = title
        self.description = description
        self.toolSwitch = toolSwitch
        self.file = file
        self.newRule = newRule
        self.editorStyle = editorStyle
        self.helpURL = helpURL
        self.note = note
        self.prefill = prefill
        self.moreItems = AnyView(moreItems())
        self.accessory = AnyView(accessory())
        self.editor = editor
        self.columns = columns()
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Enable \(title) Tool", isOn: Binding(
                    get: { model.settings.toolSwitches[keyPath: toolSwitch] },
                    set: { model.settings.toolSwitches[keyPath: toolSwitch] = $0 }))
                Text(description)
                Text("Each request is checked against the rules from top to bottom, stopping when a match is found.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            table(rows)
                .overlay {
                    if tree.nodes.isEmpty { Text("Click \"+\" or ⌘N to add new entry").foregroundStyle(.secondary) }
                }
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.top, 6)
            }
            Text("New: ⌘N  Edit: ⌘↩  Delete: ⌘⌫  Duplicate: ⌘D  Toggle: ␣")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            Divider()
            bottomBar
        }
        .frame(minWidth: 800, minHeight: 420)
        .background { shortcuts }
        .sheet(item: $draft) { rule in
            editor(Binding(get: { draft ?? rule }, set: { draft = $0 }), { saved in commit(saved) }, { draft = nil })
        }
        // ponytail: 폴더 이름은 표 셀 안 TextField가 포커스를 받지 못해(NSTableView) 이름 입력 창으로 바꾼다.
        .alert("폴더 이름", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("폴더 이름", text: $renameText)
            Button("취소", role: .cancel) { renaming = nil }
            Button("저장", action: commitRename)
        }
        .confirmationDialog("선택한 규칙을 삭제할까요? 되돌릴 수 없습니다.", isPresented: $confirmDelete) {
            Button("삭제", role: .destructive) { deleteSelection() }
            Button("취소", role: .cancel) {}
        }
        .onAppear(perform: consumePendingRule)
        .onChange(of: model.pendingNewRule) { consumePendingRule() }
    }

    // MARK: - 표

    private func table(_ rows: [ToolRow<Rule>]) -> some View {
        Table(of: ToolRow<Rule>.self, selection: $selection) {
            TableColumn("Enabled") { (row: ToolRow<Rule>) in
                Toggle("", isOn: Binding(get: { row.node.isEnabled },
                                         set: { on in change { $0.update(row.id) { $0.isEnabled = on } } }))
                    .labelsHidden()
            }
            .width(56)
            TableColumn("Name") { (row: ToolRow<Rule>) in nameCell(row) }
                .width(min: 120, ideal: 220)
            columns
        } rows: {
            ForEach(rows) { row in
                TableRow(row)
                    .draggable(row.id)
                    // 폴더 위에 놓으면 그 폴더 끝으로, 규칙 위에 놓으면 그 규칙 앞으로.
                    .dropDestination(for: String.self) { ids in
                        if row.rule == nil { move(ids, into: row.id, before: nil) } else { move(ids, into: tree.parent(of: row.id), before: row.id) }
                    }
            }
            .dropDestination(for: String.self) { index, ids in
                if index < rows.count { move(ids, into: tree.parent(of: rows[index].id), before: rows[index].id) } else { move(ids, into: nil, before: nil) }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                Button("Edit") { edit(ids.first) }.disabled(ids.count != 1)
                Button("Duplicate") { duplicate(ids) }
                Button("Toggle") { toggle(ids) }
                Divider()
                Button("Delete") { selection = ids; confirmDelete = true }
            }
        } primaryAction: { ids in
            if ids.count == 1 { edit(ids.first) }
        }
        .onKeyPress(.space) {
            guard !selection.isEmpty else { return .ignored }
            toggle(selection)
            return .handled
        }
    }

    @ViewBuilder private func nameCell(_ row: ToolRow<Rule>) -> some View {
        HStack(spacing: 4) {
            if row.depth > 0 { Color.clear.frame(width: CGFloat(row.depth) * 16, height: 1) }
            if row.rule == nil {
                Button {
                    if collapsed.contains(row.id) { collapsed.remove(row.id) } else { collapsed.insert(row.id) }
                } label: {
                    Image(systemName: collapsed.contains(row.id) ? "chevron.right" : "chevron.down").frame(width: 12)
                }
                .buttonStyle(.plain)
                Image(systemName: "folder").foregroundStyle(.secondary)
            }
            Text(row.node.name).lineLimit(1)
        }
    }

    // MARK: - 하단

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button { openEditor(newRule()) } label: { Image(systemName: "plus") }
                .keyboardShortcut("n")
                .help("New (⌘N)")
            Button { confirmDelete = true } label: { Image(systemName: "minus") }
                .keyboardShortcut(.delete)
                .disabled(selection.isEmpty)
                .help("Delete (⌘⌫)")
            Button("New Folder", action: newFolder)
            if let helpURL { HelpLink(destination: helpURL) }
            Spacer()
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            accessory
            Menu("More") {
                Button("Import…") { importing = RuleBundlePanel.chooseImport() }
                Button("Export…", action: export).disabled(tree.nodes.isEmpty)
                moreItems
            }
            .fixedSize()
        }
        .padding(8)
        .sheet(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } })) {
            ImportProxymanSheet(file: importing, tool: importTool)
        }
        .alert("내보내지 못했습니다", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("확인") { exportError = nil }
        } message: {
            Text(verbatim: exportError ?? "")
        }
    }

    private var importTool: ImportTool {
        switch Rule.self {
        case is MapLocalRule.Type: .mapLocal
        case is MapRemoteRule.Type: .mapRemote
        case is BreakpointRule.Type: .breakpoint
        case is BlockRule.Type: .block
        default: .allow
        }
    }

    private func export() {
        do {
            guard let url = try RuleBundlePanel.chooseExport(name: title) else { return }
            try RuleBundle.export(tree, toolName: title, mapLocalDirectory: model.rules.mapLocalDirectory, to: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// 버튼이 없는 단축키(⌘↩ 편집, ⌘D 복제). 창이 키 창일 때만 동작한다.
    /// 창 안 버튼이어야 메뉴의 기기 ⌘D보다 먼저 받는다(onKeyPress·메뉴 명령은 진다). 프레임을 0×0으로 줄이면 동작하지 않는다(실측).
    private var shortcuts: some View {
        Group {
            Button("Edit") { edit(selection.first) }
                .keyboardShortcut(.return)
                .disabled(selection.count != 1)
            Button("Duplicate") { duplicate(selection) }
                .keyboardShortcut("d")
                .disabled(selection.isEmpty)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - 데이터

    /// `rules`의 캐시는 관찰되지 않으므로 `revision`을 읽어 변경 때 다시 그린다.
    private var tree: RuleTree<Rule> {
        _ = model.rules.revision
        return model.rules.tree(file)
    }

    private var rows: [ToolRow<Rule>] {
        let searching = !filter.isEmpty
        func flat(_ list: [RuleNode<Rule>], _ depth: Int) -> [ToolRow<Rule>] {
            list.flatMap { n in
                [ToolRow(node: n, depth: depth)] + (!searching && collapsed.contains(n.id) ? [] : flat(n.children, depth + 1))
            }
        }
        let all = flat(tree.nodes, 0)
        guard searching else { return all }
        return all.filter {
            $0.node.name.localizedCaseInsensitiveContains(filter) || ($0.rule?.match.url.localizedCaseInsensitiveContains(filter) ?? false)
        }
    }

    private func change(_ body: (inout RuleTree<Rule>) -> Void) {
        var t = model.rules.tree(file)
        body(&t)
        model.rules.set(t, for: file)
    }

    private func openEditor(_ rule: Rule) {
        switch editorStyle {
        case .sheet: draft = rule
        case .window(let id):
            model.editorDrafts[rule.id] = rule
            openWindow(id: id, value: rule.id)
        }
    }

    /// 있는 규칙이면 제자리에서 바꾸고, 새 규칙이면 최상위 끝에 넣는다.
    private func commit(_ rule: Rule) {
        change { t in
            if t.node(rule.id) != nil { t.update(rule.id) { $0 = .rule(rule) } } else { t.insert([.rule(rule)], into: nil) }
        }
        draft = nil
        filter = ""
        selection = [rule.id]
    }

    private func edit(_ id: String?) {
        guard let id, let node = tree.node(id) else { return }
        if let rule = node.rule {
            openEditor(rule)
        } else {
            renameText = node.name
            renaming = id
        }
    }

    private func commitRename() {
        guard let id = renaming else { return }
        renaming = nil
        let name = renameText.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, tree.node(id)?.name != name { change { $0.update(id) { $0.name = name } } }
    }

    private func newFolder() {
        filter = ""   // 새 행이 필터에 가려지지 않게
        let id = RuleTree<Rule>.newID()
        change { $0.insert([.folder(RuleFolder(id: id, name: String(localized: "새 폴더")))], into: nil) }
        selection = [id]
        edit(id)
    }

    private func toggle(_ ids: Set<String>) {
        change { t in for id in ids { t.update(id) { $0.isEnabled.toggle() } } }
    }

    private func duplicate(_ ids: Set<String>) {
        var created: [String] = []
        change { created = $0.duplicate(ids) }
        selection = Set(created)
    }

    private func deleteSelection() {
        change { $0.remove(selection) }
        selection = []
    }

    private func move(_ ids: [String], into folder: String?, before: String?) {
        change { $0.move(Set(ids), into: folder, before: before) }
    }

    /// 우클릭 ▸ Tools로 미리 채운 새 규칙. 저장 전에는 트리에 들어가지 않는다.
    private func consumePendingRule() {
        guard let pending = model.pendingNewRule, pending.windowID == windowID else { return }
        model.pendingNewRule = nil
        var rule = newRule()
        rule.match = pending.match
        prefill?(&rule, pending)
        openEditor(rule)
    }
}

/// 도구별 열. 폴더 행에서는 비어 있다.
func ruleColumn<Rule: ToolRule, V: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: @escaping (Rule) -> V)
    -> TableColumn<ToolRow<Rule>, Never, some View, Text> {
    TableColumn(title) { (row: ToolRow<Rule>) in
        if let rule = row.rule { content(rule) }
    }
}

enum RuleText {
    static func method(_ match: MatchRule) -> String {
        if case .exact(let list) = match.methods { list.joined(separator: ", ") } else { "ANY" }
    }

    static func matching(_ match: MatchRule) -> String {
        "\(match.mode == .regex ? "Regex" : "Wildcard"): \(match.url)"
    }
}

/// "Wildcard: <url>"과, 자동 복호화가 안 되는 규칙이면 주황 경고 아이콘(스펙 §4.4).
struct MatchingRuleCell: View {
    let match: MatchRule
    var body: some View {
        HStack(spacing: 4) {
            if match.needsSSLListEntry {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("SSL Proxying 목록에 호스트를 추가해야 동작합니다")
            }
            Text(RuleText.matching(match)).lineLimit(1).truncationMode(.middle)
        }
    }
}

extension MatchRule {
    /// 자동 복호화 대상이 아니라(정규식·호스트가 와일드카드뿐) SSL Proxying 목록에 호스트를 직접 넣어야 하는 HTTPS 규칙.
    var needsSSLListEntry: Bool {
        !url.isEmpty && hostPattern == nil && !url.lowercased().hasPrefix("http://")
    }
}
