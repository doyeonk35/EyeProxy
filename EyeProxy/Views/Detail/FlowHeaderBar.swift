import AppKit
import EyeProxyCore
import SwiftUI

struct FlowHeaderBar: View {
    @Environment(AppModel.self) private var model
    let flow: Flow

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                MethodTag(method: flow.request.method)
                StatusTag(flow: flow)
                Text(urlText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(flow.request.url, forType: .string)
                }
                Button("cURL") { model.copyCurl(flow.id) }
            }
            .buttonStyle(.accessoryBar)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
        }
    }

    private var urlText: AttributedString {
        let request = flow.request
        func part(_ s: String, _ color: Color, bold: Bool = false) -> AttributedString {
            var a = AttributedString(s)
            a.foregroundColor = color
            if bold { a.inlinePresentationIntent = .stronglyEmphasized }
            return a
        }
        let path = request.path
        let q = path.firstIndex(of: "?")
        var out = part("\(request.scheme)://", .secondary) + part(request.host, .primary, bold: true)
        out += part(q.map { String(path[..<$0]) } ?? path, .accentColor)
        if let q {
            out += part("?", .secondary)
            let pairs = path[path.index(after: q)...].split(separator: "&", omittingEmptySubsequences: false)
            for (i, pair) in pairs.enumerated() {
                if i > 0 { out += part("&", .secondary) }
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                out += part(String(kv[0]), .primary)
                if kv.count > 1 { out += part("=", .secondary) + part(String(kv[1]), .secondary) }
            }
        }
        return out
    }
}
