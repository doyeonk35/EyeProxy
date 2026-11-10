import EyeProxyKit
import SwiftUI

/// 필터 막대가 받는 단축키 동작(스펙 §4). 막대 안에 포커스가 있을 때만 메뉴 항목이 켜진다.
enum FilterBarCommand { case add, remove, up, down, toggle }

/// 비교는 막대 인스턴스 `id`만 — 클로저는 막대의 @State·@FocusState 저장소를 가리켜 처음 값으로도 최신 상태에 작용한다(`DetailFind`와 같다).
struct FilterBarActions: Equatable {
    let id: UUID
    let perform: @MainActor (FilterBarCommand) -> Void
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

extension FocusedValues {
    @Entry var filterBar: FilterBarActions?
}

/// 목록 위 Proxyman식 필터 막대: 한 줄 = 규칙 하나 `[켜짐] [키 ▾] [매칭 ▾] [검색어] − +`, 아래 단축키 안내와 AND/OR.
struct FilterRulesBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: FilterRule.ID?
    /// 마지막으로 포커스가 있던 규칙. ⌘F는 이 규칙 검색칸으로 돌아온다.
    @State private var current: FilterRule.ID?
    @State private var actionsID = UUID()

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 4) {
            ForEach($model.filter.rules) { $rule in row($rule) }
            HStack(spacing: 8) {
                Text(verbatim: "Show ⌘F · New ⌘N · Remove ⇧⌘N · Up ⌘↑ · Down ⌘↓ · On/Off ⌘B · Hide ESC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Picker("", selection: $model.filter.combineWithOr) {
                    Text(verbatim: "AND").tag(false)
                    Text(verbatim: "OR").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
                .help("규칙을 모두 만족(AND)·하나라도 만족(OR)할 때 보이기")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.bar)
        .focusedValue(\.filterBar, FilterBarActions(id: actionsID, perform: perform))
        .onExitCommand { model.isFilterBarVisible = false }
        .onAppear { if model.filter.rules.isEmpty { model.filter.rules = [FilterRule()] } }
        .onChange(of: focused) { _, id in
            if let id { current = id }
            model.filterBarHasFocus = id != nil
        }
        .onChange(of: model.focusFilterBar, initial: true) { _, on in
            guard on else { return }
            model.focusFilterBar = false
            // 막대가 막 나타난 갱신 안에서는 포커스가 붙지 않아 다음 차례에 준다.
            Task { focused = currentRule ?? model.filter.rules.first?.id }
        }
    }

    private var currentRule: FilterRule.ID? {
        model.filter.rules.contains { $0.id == current } ? current : nil
    }

    private func row(_ rule: Binding<FilterRule>) -> some View {
        let r = rule.wrappedValue
        let count = model.filter.rules.count
        return HStack(spacing: 6) {
            Toggle("", isOn: rule.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("이 규칙 켜기·끄기 (⌘B)")
            Picker("", selection: Binding(get: { r.key }, set: { key in
                rule.wrappedValue.key = key
                // `<`·`>=`는 숫자 키에서만.
                if rule.wrappedValue.match.isNumericOnly, !key.isNumeric { rule.wrappedValue.match = .contains }
            })) {
                ForEach(FilterKey.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help(r.key == .color ? "Highlight 색 이름(red·yellow 등)과 맞춰 보기" : "검색할 항목")
            Picker("", selection: rule.match) {
                ForEach(FilterMatch.allCases, id: \.self) { m in
                    Text(verbatim: m.rawValue).tag(m).selectionDisabled(m.isNumericOnly && !r.key.isNumeric)
                }
            }
            .labelsHidden()
            .fixedSize()
            .help("맞춰 보는 방식(대소문자 무시) — < · >=는 숫자 키에서만")
            TextField("Filter", text: rule.text, prompt: Text(verbatim: "\(r.key.rawValue)"))
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: r.id)
                // 포커스 링이 테두리를 덮으므로 칸 안 오른쪽에 경고 표시도 둔다.
                .overlay(alignment: .trailing) {
                    if r.isInvalid {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).padding(.trailing, 6)
                    }
                }
                .overlay {
                    if r.isInvalid { RoundedRectangle(cornerRadius: 5).stroke(Color.red, lineWidth: 1.5) }
                }
                .help(r.isInvalid ? "정규식이 올바르지 않아 이 규칙은 적용되지 않습니다" : "검색어 — 비우면 이 규칙은 적용되지 않습니다")
            Button { remove(r.id) } label: { Image(systemName: "minus") }
                .buttonStyle(.borderless)
                .disabled(count <= 1)
                .help("이 규칙 지우기 (⇧⌘N)")
            Button { add(after: r.id) } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .disabled(count >= FlowFilter.maxRules)
                .help("규칙 추가 (⌘N)")
        }
        .opacity(r.isEnabled ? 1 : 0.6)
    }

    private func perform(_ command: FilterBarCommand) {
        let rules = model.filter.rules
        let id = focused ?? currentRule
        let index = id.flatMap { id in rules.firstIndex { $0.id == id } }
        switch command {
        case .add: add(after: id)
        case .remove: if let id { remove(id) }
        case .up: if let index, index > 0 { focused = rules[index - 1].id }
        case .down: if let index, index + 1 < rules.count { focused = rules[index + 1].id }
        case .toggle: if let index { model.filter.rules[index].isEnabled.toggle() }
        }
    }

    /// 그 규칙 아래(없으면 맨 끝)에 빈 규칙을 넣고 검색칸에 포커스.
    private func add(after id: FilterRule.ID?) {
        guard model.filter.rules.count < FlowFilter.maxRules else { return }
        let rule = FilterRule()
        let at = id.flatMap { id in model.filter.rules.firstIndex { $0.id == id } }.map { $0 + 1 } ?? model.filter.rules.endIndex
        model.filter.rules.insert(rule, at: at)
        focused = rule.id
    }

    /// 하나는 남긴다. 지운 자리의 다음(없으면 이전) 규칙으로 포커스.
    private func remove(_ id: FilterRule.ID) {
        let rules = model.filter.rules
        guard rules.count > 1, let i = rules.firstIndex(where: { $0.id == id }) else { return }
        model.filter.rules.remove(at: i)
        focused = model.filter.rules[min(i, model.filter.rules.count - 1)].id
    }
}
