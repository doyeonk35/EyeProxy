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
                ForEach(model.devices.devices) { device in
                    Label(device.displayName, systemImage: device.kind == .thisMac ? "laptopcomputer" : "display")
                        .badge(device.flowCount)
                        .tag(SidebarItem.device(device.address))
                }
            }
            Section("도메인") {
                ForEach(model.hosts, id: \.host) { entry in
                    Label(entry.host, systemImage: "globe")
                        .badge(entry.count)
                        .tag(SidebarItem.host(entry.host))
                }
            }
        }
    }
}
