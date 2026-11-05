import EyeProxyKit
import SwiftUI

struct JSONTreeView: View {
    let nodes: [JSONTreeNode]

    var body: some View {
        List {
            OutlineGroup(nodes, children: \.children) { n in
                HStack(spacing: 6) {
                    if !n.key.isEmpty { Text(n.key).foregroundStyle(.secondary) }
                    Text(n.preview).lineLimit(2)
                }
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            }
        }
    }
}
