import AppKit
import EyeProxyKit
import SwiftUI

/// Proxyman 하이어라키(스펙 §5): Favorites ▸ Pinned, Remote devices, All ▸ All Requests·Apps·Domains, 맨 아래 필터 칸.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(SessionTab.self) private var tab
    @Environment(\.openWindow) private var openWindow
    /// 기본값과 다르게 펼치거나 접은 줄의 키.
    @State private var toggled: Set<String> = []
    @State private var addingPin = false
    @State private var filterFindID = UUID()
    @FocusState private var filterFocused: Bool

    var body: some View {
        @Bindable var tab = tab
        let tree = tab.sidebarTree
        VStack(spacing: 0) {
            List(selection: $tab.sidebarSelection) {
                Section("Favorites") {
                    DisclosureGroup(isExpanded: expansion("pinned")) {
                        if tree.pinned.isEmpty, tab.sidebarFilterText.isEmpty {
                            Text("도메인을 우클릭해 고정").foregroundStyle(.secondary)
                        }
                        ForEach(tree.pinned) { domainRow($0, icon: "pin.fill") }
                    } label: {
                        Label("Pinned", systemImage: "pin")
                    }
                }
                if !tree.remoteDevices.isEmpty {
                    Section("Remote devices") {
                        ForEach(tree.remoteDevices) { device in
                            DisclosureGroup(isExpanded: expansion("device|\(device.address)")) {
                                ForEach(device.hosts) { hostRow($0, icon: "globe", tag: .scope(FlowScope(device: device.address, host: $0.host))) }
                            } label: {
                                Label(device.displayName, systemImage: icon(device.kind))
                                    .badge(device.count)
                                    .tag(SidebarItem.scope(FlowScope(device: device.address)))
                                    .contextMenu { openAsNewTab(.scope(FlowScope(device: device.address))) }
                            }
                        }
                    }
                }
                Section("All") {
                    Label("All Requests", systemImage: "tray.full")
                        .badge(tab.sidebarFlowCount)
                        .tag(SidebarItem.allFlows)
                    DisclosureGroup(isExpanded: expansion("apps")) {
                        ForEach(tree.apps) { app in
                            DisclosureGroup(isExpanded: expansion("app|\(app.groupKey)", default: false)) {
                                ForEach(app.hosts) { hostRow($0, icon: "globe", tag: .scope(FlowScope(device: SidebarTree.thisMac, process: app.groupKey, host: $0.host))) }
                            } label: {
                                Label { Text(app.displayName) } icon: { AppIcon(path: app.path) }
                                    .badge(app.count)
                                    .tag(SidebarItem.scope(FlowScope(device: SidebarTree.thisMac, process: app.groupKey)))
                                    .contextMenu { openAsNewTab(.scope(FlowScope(device: SidebarTree.thisMac, process: app.groupKey))) }
                            }
                        }
                    } label: {
                        Label("Apps", systemImage: "square.grid.2x2")
                            .badge(tree.appsCount)
                            .tag(SidebarItem.scope(FlowScope(device: SidebarTree.thisMac)))
                            .help("이 Mac의 앱(프로세스)별 요청")
                    }
                    DisclosureGroup(isExpanded: expansion("domains")) {
                        ForEach(tree.domains) { domainRow($0, icon: "globe") }
                    } label: {
                        Label("Domains", systemImage: "globe")
                            .badge(tab.sidebarFlowCount)
                    }
                }
            }
            Divider()
            HStack(spacing: 6) {
                Button { addingPin = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Pinned에 도메인 추가")
                TextField("Filter (⌘⇧F)", text: $tab.sidebarFilterText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($filterFocused)
                    .onExitCommand { tab.sidebarFilterText = "" }
                    .help("사이드바 항목 이름으로 거르기 (⌘⇧F)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .focusedValue(\.sidebarFilter, DetailFind(id: filterFindID, open: { filterFocused = true }))
        .sheet(isPresented: $addingPin) { AddPinnedDomainSheet() }
    }

    /// 거르는 중이면 맞는 줄이 보이게 모두 펼친다.
    private func expansion(_ key: String, default open: Bool = true) -> Binding<Bool> {
        Binding(
            get: { !tab.sidebarFilterText.isEmpty || toggled.contains(key) != open },
            set: { if $0 != open { toggled.insert(key) } else { toggled.remove(key) } }
        )
    }

    /// Pinned·Domains의 도메인: 펼치면 경로 트리. 경로 트리는 펼친 도메인만 AppModel이 계산한다.
    @ViewBuilder
    private func domainRow(_ node: HostNode, icon: String) -> some View {
        let row = hostRow(node, icon: icon, tag: .host(node.host))
        if tab.sidebarTree.hostsWithPaths.contains(node.host) {
            DisclosureGroup(isExpanded: Binding(
                get: { tab.expandedDomains.contains(node.host) },
                set: { if $0 { tab.expandedDomains.insert(node.host) } else { tab.expandedDomains.remove(node.host) } }
            )) {
                OutlineGroup(tab.pathTrees[node.host] ?? [], children: \.childNodes) { path in
                    Label("/" + path.segment, systemImage: path.children.isEmpty ? "doc" : "folder")
                        .badge(path.count)
                        .tag(SidebarItem.path(host: node.host, prefix: path.fullPath))
                        .contextMenu { openAsNewTab(.path(host: node.host, prefix: path.fullPath)) }
                }
            } label: { row }
        } else {
            row
        }
    }

    private func hostRow(_ node: HostNode, icon: String, tag: SidebarItem) -> some View {
        let host = node.host
        let isPinned = model.settings.pinnedHosts.contains(host)
        return Label(host, systemImage: icon)
            .badge(node.count)
            .tag(tag)
            .contextMenu {
                openAsNewTab(tag)
                Divider()
                Button(isPinned ? "Unpin" : "Pin") { model.settings.togglePin(host) }
                    .help(isPinned ? "Pinned에서 빼기" : "Pinned에 고정")
                Button("Enable SSL Proxying") { Task { await model.enableSSLProxying(for: host) } }
                    .help("이 도메인을 SSL Proxying List에 넣고 복호화 켜기")
                Button("Copy Domain") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(host, forType: .string)
                }
                .help("도메인 이름 복사")
            }
    }

    /// 우클릭 맨 위(스펙 §4.4): 같은 세션을 보고 이 항목을 고른 새 탭.
    private func openAsNewTab(_ item: SidebarItem) -> some View {
        Button("Open as New Tab") { openWindow(id: "main", value: model.newTabID(sharing: tab, selecting: item)) }
            .help("이 항목을 고른 새 탭 열기")
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

private extension PathNode {
    /// OutlineGroup용: 잎이면 nil(펼침 표시 없음).
    var childNodes: [PathNode]? { children.isEmpty ? nil : children }
}

/// 사이드바 `+`: Pinned에 도메인 하나 추가. URL을 붙여 넣으면 호스트만 쓴다.
private struct AddPinnedDomainSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var host: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: t)?.host ?? t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Pinned Domain").font(.headline)
            TextField("api.example.com", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(host.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func add() {
        guard !host.isEmpty else { return }
        if !model.settings.pinnedHosts.contains(host) { model.settings.togglePin(host) }
        dismiss()
    }
}
