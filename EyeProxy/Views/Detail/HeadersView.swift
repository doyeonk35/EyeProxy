import EyeProxyCore
import SwiftUI

struct HeadersView: View {
    let headers: [HTTPHeader]

    var body: some View {
        if headers.isEmpty {
            ContentUnavailableView("헤더 없음", systemImage: "list.bullet")
        } else {
            ScrollView {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(headers.indices, id: \.self) { i in
                        GridRow {
                            Text(headers[i].name).bold().gridColumnAlignment(.trailing)
                            Text(headers[i].value)
                        }
                    }
                }
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
    }
}
