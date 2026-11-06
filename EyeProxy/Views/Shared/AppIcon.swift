import AppKit
import SwiftUI

struct AppIcon: View {
    let path: String?

    var body: some View {
        if let path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: "app.dashed")
        }
    }
}
