import AppKit
import EyeProxyCore
import SwiftUI

struct KeyValueTable: View {
    let rows: [HTTPHeader]
    let emptyTitle: LocalizedStringKey
    @State private var hovered: Int?

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "list.bullet")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { i in
                        row(rows[i], index: i)
                        if i < rows.count - 1 { Divider().opacity(0.5) }
                    }
                }
            }
        }
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
