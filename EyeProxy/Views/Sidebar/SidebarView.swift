import EyeProxyKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Label("전체", systemImage: "tray.full")
                .badge(model.session.flows.count)
                .tag(SidebarItem.allFlows)
            Section("기기") {
                ForEach(model.sidebarTree.devices, id: \.address) { node in
                    Label(node.displayName, systemImage: node.kind == .thisMac ? "laptopcomputer" : "display")
                        .badge(node.count)
                        .tag(SidebarItem.scope(FlowScope(device: node.address)))
                }
            }
            Section("도메인") {
                ForEach(model.sidebarTree.hosts, id: \.host) { node in
                    Label(node.host, systemImage: "globe")
                        .badge(node.count)
                        .tag(SidebarItem.host(node.host))
                }
            }
        }
    }
}
