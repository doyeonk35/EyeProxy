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

    private var shown: [HTTPHeader] {
        query.isEmpty ? rows : rows.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if filterVisible { filterBar; Divider() }
            let shown = shown
            if rows.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "list.bullet")
            } else if shown.isEmpty {
                ContentUnavailableView("일치 없음", systemImage: "magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown.indices, id: \.self) { i in
                            row(shown[i], index: i)
                            if i < shown.count - 1 { Divider().opacity(0.5) }
                        }
                    }
                }
                // 클릭하면 표가 포커스를 받아 ⌘F가 이 표로 온다. focusable만으로는 클릭이 포커스를 늘 옮기지 않았다(실측).
                .focusable(interactions: .edit)
                .focusEffectDisabled()
                .focused($tableFocused)
                .simultaneousGesture(TapGesture().onEnded { tableFocused = true })
            }
        }
        .focusedValue(\.detailFind, DetailFind(open: { filterVisible = true; fieldFocused = true }))
        .onExitCommand { close() }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            TextField("이름·값 거르기", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .help("이름 또는 값에 이 글자가 든 행만 보입니다 (대소문자 무시)")
            Text("\(shown.count) / 전체 \(rows.count)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button { close() } label: { Label("닫기", systemImage: "xmark.circle.fill").labelStyle(.iconOnly) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("거르기 닫기 (Esc)")
        }
        .controlSize(.small)
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func close() {
        filterVisible = false
        query = ""
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
