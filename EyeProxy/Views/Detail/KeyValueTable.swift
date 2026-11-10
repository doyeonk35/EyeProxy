import AppKit
import EyeProxyCore
import SwiftUI

/// 이름·값 표. 포커스가 있을 때 ⌘F로 거르기 칸을 연다(이름 또는 값에 검색어 포함, 대소문자 무시). Esc로 닫는다.
struct KeyValueTable: View {
    let rows: [HTTPHeader]
    let emptyTitle: LocalizedStringKey
    @State private var hovered: Int?
    @State private var filterVisible = false
    @State private var query = ""
    @FocusState private var fieldFocused: Bool
    @FocusState private var tableFocused: Bool
    @State private var findID = UUID()

    /// 보이는 행의 원래 인덱스. 행·마우스 강조를 원래 인덱스로 묶어 거른 뒤에도 강조가 다른 행으로 옮겨 가지 않는다.
    private func shownIndices() -> [Int] {
        query.isEmpty ? Array(rows.indices)
            : rows.indices.filter { rows[$0].name.localizedCaseInsensitiveContains(query) || rows[$0].value.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let shown = shownIndices()
        VStack(spacing: 0) {
            if filterVisible { filterBar(count: shown.count); Divider() }
            if rows.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "list.bullet")
            } else if shown.isEmpty {
                ContentUnavailableView("일치 없음", systemImage: "magnifyingglass")
            } else {
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
    }

    private func filterBar(count: Int) -> some View {
        HStack(spacing: 6) {
            TextField("이름·값 거르기", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .help("이름 또는 값에 이 글자가 든 행만 보입니다 (대소문자 무시)")
            Text("\(count) / 전체 \(rows.count)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button { close() } label: { Label("닫기", systemImage: "xmark.circle.fill").labelStyle(.iconOnly) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("거르기 닫기 (Esc)")
        }
        .controlSize(.small)
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    /// 닫으면 표로 포커스를 돌려 다음 ⌘F가 다시 이 칸을 연다(툴바 검색칸으로 가지 않게).
    private func close() {
        filterVisible = false
        query = ""
        Task { @MainActor in tableFocused = true }
    }

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
