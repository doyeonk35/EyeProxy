import EyeProxyKit
import SwiftUI

/// 편집기 공통 Matching Rule 칸(스펙 §6.3). `Form` 안에 넣어 쓴다.
struct MatchRuleFields: View {
    @Binding var name: String
    @Binding var match: MatchRule
    /// Block·Allow: 호스트만 있는 규칙은 CONNECT에서 판정하므로 복호화하지 않는다.
    var hostOnlyDecidedAtConnect = false

    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var testing = false
    @FocusState private var urlFocused: Bool

    static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    var body: some View {
        Group {
            TextField("Name", text: $name)
            VStack(alignment: .leading, spacing: 4) {
                TextField("URL", text: $match.url, prompt: Text(verbatim: "api.example.com/v1/*"))
                    .focused($urlFocused)
                    .onSubmit(moveQueryToTable)
                    // 붙여 넣기(한 번에 여러 글자)는 바로 옮긴다. 규칙을 불러올 때 바뀐 값은 포커스가 없어 건드리지 않는다.
                    .onChange(of: match.url) { old, new in if urlFocused && new.count - old.count > 1 { moveQueryToTable() } }
                    .onChange(of: urlFocused) { if !urlFocused { moveQueryToTable() } }
                hostHint.font(.caption)
            }
            HStack(spacing: 8) {
                methodMenu
                Picker("Mode", selection: $match.mode) {
                    Text("Use Wildcard").tag(MatchMode.wildcard)
                    Text("Use Regex").tag(MatchMode.regex)
                }
                .labelsHidden()
                .fixedSize()
                if match.mode == .wildcard { Text("와일드카드 * 와 ? 지원").foregroundStyle(.secondary) }
                Spacer()
                Button("Test your Rule") { testing = true }.buttonStyle(.link)
            }
            Toggle("Include all subpaths of this URL", isOn: $match.includeSubpaths)
                .toggleStyle(.checkbox)
            QueryFields(match: $match)
            if let error = match.validationError { Text(error).foregroundStyle(.red) }
            if match.queryMode != .exact && match.hasQueryLikePattern {
                Text("쿼리가 '무시'·'선택한 항목만'이라 패턴의 쿼리 부분과는 비교하지 않습니다").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $testing) {
            TestRuleSheet(match: match, firstSample: selectedFlowURL)
        }
    }

    @ViewBuilder private var hostHint: some View {
        if hostOnlyDecidedAtConnect && match.isDecidedAtConnect {
            Text("호스트 전체 규칙은 연결(CONNECT) 단계에서 판정합니다").foregroundStyle(.secondary)
        } else if match.hostPattern != nil {
            Text("이 호스트는 자동으로 복호화됩니다").foregroundStyle(.secondary)
        } else if match.needsSSLListEntry {
            HStack(spacing: 4) {
                Text("SSL Proxying 목록에 호스트를 추가해야 동작합니다").foregroundStyle(.orange)
                // 경고는 호스트를 뽑을 수 없는 규칙에만 뜨므로 설정의 SSL Proxying 탭을 연다.
                Button("목록에 추가") {
                    model.settingsTab = .ssl
                    openSettings()
                }
                .buttonStyle(.link)
            }
        }
    }

    /// URL 칸의 `k=v` 쿼리를 체크된 조건으로 옮기고 '선택한 항목만'으로. '전체 일치'와 정규식 규칙은 그대로 둔다.
    private func moveQueryToTable() {
        guard match.queryMode != .exact, match.mode == .wildcard else { return }
        let split = MatchRule.splitQuery(fromPattern: match.url, mode: match.mode)
        guard !split.conditions.isEmpty else { return }
        match.url = split.url
        match.queryConditions += split.conditions
        match.queryMode = .selected
    }

    private var selectedMethods: [String] {
        if case .exact(let list) = match.methods { list.map { $0.uppercased() } } else { [] }
    }

    private var methodMenu: some View {
        Menu {
            Toggle("ANY", isOn: Binding(get: { match.methods == .any }, set: { if $0 { match.methods = .any } }))
            Divider()
            ForEach(Self.methods, id: \.self) { method in
                Toggle(method, isOn: Binding(get: { selectedMethods.contains(method) }, set: { on in
                    let next = on ? selectedMethods + [method] : selectedMethods.filter { $0 != method }
                    match.methods = next.isEmpty ? .any : .exact(next)
                }))
            }
        } label: {
            Text(verbatim: RuleText.method(match))
        }
        .fixedSize()
    }

    private var selectedFlowURL: String {
        model.activeTab.flatMap { tab in tab.selectedFlowID.flatMap { tab.session.flow($0) } }.map { MatchRule.urlString($0.request, includeQuery: true) } ?? ""
    }
}

/// 쿼리 모드 Picker와 조건 표(Proxyman Edit & Repeat의 Query 탭 모양). 편집기와 Test your Rule이 같이 쓴다.
struct QueryFields: View {
    @Binding var match: MatchRule
    @State private var selection: QueryCondition.ID?
    @State private var newKey = ""
    @State private var newValue = ""
    @FocusState private var newField: NewField?

    private enum NewField { case key, value }

    /// '선택한 항목만'이거나, 우클릭 ▸ Tools로 채운 체크 해제 조건이 있는 '무시'.
    private var showsTable: Bool {
        match.queryMode == .selected
            || (match.queryMode == .ignore && !match.queryConditions.isEmpty && !match.queryConditions.contains(where: \.isEnabled))
    }

    var body: some View {
        Group {
            Picker("쿼리", selection: $match.queryMode) {
                Text("무시").tag(QueryMode.ignore)
                Text("선택한 항목만").tag(QueryMode.selected)
                Text("전체 일치").tag(QueryMode.exact)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            if showsTable {
                VStack(alignment: .leading, spacing: 4) {
                    Text("체크한 항목만 비교합니다. 값을 *로 두면 키만 있으면 됩니다.").font(.caption).foregroundStyle(.secondary)
                    table
                }
            }
        }
    }

    /// 사용자가 '무시'에서 하나라도 체크하면 '선택한 항목만'으로. 저장된 규칙을 불러올 때는 바꾸지 않는다.
    private func checked() {
        if match.queryMode == .ignore { match.queryMode = .selected }
    }

    private var table: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach($match.queryConditions) { $c in
                    row(Toggle("", isOn: Binding(get: { c.isEnabled }, set: { c.isEnabled = $0; if $0 { checked() } })), TextField("", text: $c.key), TextField("", text: $c.value, prompt: Text("값 또는 *")))
                }
                row(Toggle("", isOn: .constant(true)).disabled(true).hidden(),
                    TextField("", text: $newKey, prompt: Text("New Key…")).focused($newField, equals: .key).onSubmit { newField = .value },
                    TextField("", text: $newValue, prompt: Text("New Value…")).focused($newField, equals: .value).onSubmit(addNewRow))
                    .selectionDisabled()
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 130)
            // Key → Value로 옮길 때는 더하지 않고, 새 행의 두 칸을 모두 벗어나면 더한다.
            .onChange(of: newField) { old, new in if old != nil && new == nil { addNewRow() } }
            HStack {
                Button {
                    match.queryConditions.removeAll { $0.id == selection }
                    selection = nil
                } label: { Image(systemName: "minus") }
                .disabled(selection == nil)
                .help("선택한 행 삭제")
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func row(_ check: some View, _ key: some View, _ value: some View) -> some View {
        HStack(spacing: 6) {
            check.toggleStyle(.checkbox).labelsHidden()
            key.frame(width: 160)
            value
        }
        .textFieldStyle(.plain)
        .font(.system(.body, design: .monospaced))
    }

    /// 새 행 입력이 끝나면 체크된 조건으로 더한다.
    private func addNewRow() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        match.queryConditions.append(QueryCondition(key: key, value: newValue, isEnabled: true))
        checked()
        newKey = ""
        newValue = ""
    }
}
