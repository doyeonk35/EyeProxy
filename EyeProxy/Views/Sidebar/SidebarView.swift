import AppKit
import EyeProxyKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var collapsed: Set<String> = []

    var body: some View {
        @Bindable var model = model
        let tree = model.sidebarTree
        List(selection: $model.sidebarSelection) {
            Label("전체", systemImage: "tray.full")
                .badge(model.session.flows.count)
                .tag(SidebarItem.allFlows)
            Section("고정") {
                if tree.pinned.isEmpty {
                    Text("호스트를 우클릭해 고정").foregroundStyle(.secondary)
                }
                ForEach(tree.pinned, id: \.host) { node in
                    hostRow(node, icon: "pin.fill", tag: .host(node.host))
                }
            }
            Section("기기") {
                ForEach(tree.devices, id: \.address) { device in
                    DisclosureGroup(isExpanded: expansion(device.address)) {
                        ForEach(device.apps, id: \.groupKey) { app in
                            DisclosureGroup(isExpanded: expansion("\(device.address)|\(app.groupKey)")) {
                                ForEach(app.hosts, id: \.host) { node in
                                    hostRow(node, icon: "globe", tag: .scope(FlowScope(device: device.address, process: app.groupKey, host: node.host)))
                                }
                            } label: {
                                Label { Text(app.displayName) } icon: { AppIcon(path: app.path) }
                                    .badge(app.count)
                                    .tag(SidebarItem.scope(FlowScope(device: device.address, process: app.groupKey)))
                            }
                        }
                        ForEach(device.hosts, id: \.host) { node in
                            hostRow(node, icon: "globe", tag: .scope(FlowScope(device: device.address, host: node.host)))
                        }
                    } label: {
                        Label(device.displayName, systemImage: icon(device.kind))
                            .badge(device.count)
                            .tag(SidebarItem.scope(FlowScope(device: device.address)))
                    }
                }
            }
            Section("도메인") {
                ForEach(tree.hosts, id: \.host) { node in
                    hostRow(node, icon: "globe", tag: .host(node.host))
                }
            }
        }
    }

    private func expansion(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(key) },
            set: { if $0 { collapsed.remove(key) } else { collapsed.insert(key) } }
        )
    }

    private func hostRow(_ node: HostNode, icon: String, tag: SidebarItem) -> some View {
        let isPinned = model.settings.pinnedHosts.contains(node.host)
        return Label(node.host, systemImage: icon)
            .badge(node.count)
            .tag(tag)
            .contextMenu {
                Button(isPinned ? "고정 해제" : "고정") { model.settings.togglePin(node.host) }
            }
    }

    private func icon(_ kind: DeviceKind) -> String {
        switch kind {
        case .thisMac: "laptopcomputer"
        case .appleTV: "appletv"
        case .iPhone: "iphone"
        case .iPad: "ipad"
        case .unknown: "display"
        }
    }
}
