import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

/// 이름·값 표(머리 줄 `Key | Value`). 포커스가 있을 때 ⌘F 또는 패널 탭 줄 `≡`로 거르기 칸을 연다(이름 또는 값,
/// `⋯` 메뉴로 대소문자·정규식). Esc로 닫는다. 칸 보임·옵션은 패널이 쥐어 흐름·탭을 바꿔도 남고, 검색어는 표마다 새로 시작한다.
struct KeyValueTable: View {
    let rows: [HTTPHeader]
    let emptyTitle: LocalizedStringKey
    @Binding var filterVisible: Bool
    @Binding var options: TableFilter
    @State private var hovered: Int?
    @State private var query = ""
    @FocusState private var fieldFocused: Bool
    @FocusState private var tableFocused: Bool
    @State private var findID = UUID()

    var body: some View {
        // 보이는 행의 원래 인덱스. 행·마우스 강조를 원래 인덱스로 묶어 거른 뒤에도 강조가 다른 행으로 옮겨 가지 않는다.
        // 틀린 정규식이면 nil → 칸을 빨갛게 하고 모든 행을 보인다.
        let matched = options.indices(of: rows, query: query)
        let shown = matched ?? Array(rows.indices)
        VStack(spacing: 0) {
            if filterVisible { filterBar(count: shown.count, invalid: matched == nil); Divider() }
            if rows.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "list.bullet")
            } else if shown.isEmpty {
                ContentUnavailableView("일치 없음", systemImage: "magnifyingglass")
            } else {
                columnHeader
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element) { pos, i in
                            row(rows[i], index: i)
                            if pos < shown.count - 1 { Divider().opacity(0.5) }
                        }
                    }
                }
                // 이름 칸·행 빈 곳을 클릭하면 표가 포커스를 받아 ⌘F가 이 표로 온다. 값 글자 클릭은 글자 선택이 가져간다
                // (탭 제스처로 포커스를 주면 더블클릭 단어 선택·⌘C가 깨져서 쓰지 않는다 — 실측).
                .focusable(interactions: .edit)
                .focusEffectDisabled()
                .focused($tableFocused)
            }
        }
        // 칸이 그려진 다음 포커스를 준다(같은 갱신 안에서는 아직 칸이 없다).
        .focusedValue(\.detailFind, DetailFind(id: findID, open: { filterVisible = true; Task { @MainActor in fieldFocused = true } }))
        .onExitCommand { if filterVisible { close() } }
        // `≡`로 열면 칸에, 닫으면 표로 포커스(다음 ⌘F가 다시 이 칸을 연다).
        .onChange(of: filterVisible) { _, open in
            if open { Task { @MainActor in fieldFocused = true } } else { query = ""; Task { @MainActor in tableFocused = true } }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text(verbatim: "Key").frame(width: 160, alignment: .leading)
                .overlay(alignment: .trailing) { Divider().offset(x: 6) }
            Text(verbatim: "Value").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 3)
        .background(.bar)
    }

    private func filterBar(count: Int, invalid: Bool) -> some View {
        HStack(spacing: 6) {
            TextField("이름·값 거르기", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .overlay { if invalid { RoundedRectangle(cornerRadius: 5).stroke(Color("StatusError"), lineWidth: 1.5) } }
                .help(invalid ? "정규식이 올바르지 않습니다 — 고칠 때까지 모든 행을 보입니다" : "이름 또는 값에 이 글자가 든 행만 보입니다 (⋯에서 대소문자·정규식)")
            Menu {
                Picker("대소문자", selection: $options.caseSensitive) {
                    Text(verbatim: "Case Insensitive").tag(false)
                    Text(verbatim: "Case Sensitive").tag(true)
                }
                .pickerStyle(.inline).labelsHidden()
                Divider()
                Picker("일치 방식", selection: $options.regex) {
                    Text(verbatim: "Text").tag(false)
                    Text(verbatim: "Regular Expression").tag(true)
                }
                .pickerStyle(.inline).labelsHidden()
            } label: {
                Label("거르기 옵션", systemImage: "ellipsis").labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("거르기 옵션: 대소문자 구분·정규식")
            // 포커스 링이 빨간 테두리를 덮으므로 개수 자리에도 오류를 보인다.
            if invalid {
                Text("정규식 오류").font(.caption).foregroundStyle(Color("StatusError"))
            } else {
                Text("\(count) / 전체 \(rows.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { close() } label: { Label("닫기", systemImage: "xmark.circle.fill").labelStyle(.iconOnly) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("거르기 닫기 (Esc)")
        }
        .controlSize(.small)
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func close() { filterVisible = false }

    private func row(_ header: HTTPHeader, index i: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(header.name).fontWeight(.semibold).foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
            Text(header.value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovered == i ? Color.primary.opacity(0.06) : .clear)
        .onHover { inside in
            if inside { hovered = i } else if hovered == i { hovered = nil }
        }
        .contextMenu {
            Button("값 복사") { copy(header.value) }
            Button("이름: 값 복사") { copy("\(header.name): \(header.value)") }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
