import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct FlowListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("eyeproxy.flowColumns") private var columnCustomization = TableColumnCustomization<FlowRow>()

    var body: some View {
        @Bindable var model = model
        let rows = model.visibleRows
        let deviceNames = Dictionary(model.devices.devices.map { ($0.address, $0.displayName) }, uniquingKeysWith: { a, _ in a })

        Table(rows, selection: $model.selectedFlowID, sortOrder: $model.sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("#", value: \.number) { (row: FlowRow) in
                Text(row.number, format: .number.grouping(.never)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 32, ideal: 44, max: 80)
            .customizationID("index")
            TableColumn("Method", value: \.method) { (row: FlowRow) in MethodTag(method: row.method, selected: row.id == model.selectedFlowID) }
                .width(min: 50, ideal: 70, max: 110)
                .customizationID("method")
            TableColumn("URL", value: \.url) { (row: FlowRow) in
                (Text(row.host).foregroundStyle(.primary) + Text(row.flow.request.path).foregroundStyle(.secondary))
                    .lineLimit(1).truncationMode(.middle)
            }
            .width(min: 200, ideal: 480)
            .customizationID("url")
            TableColumn("앱") { (row: FlowRow) in
                if let identity = model.processes.attribution[row.id] {
                    HStack(spacing: 5) {
                        AppIcon(path: identity.path)
                        Text(identity.displayName(runtimes: model.simulatorRuntimes))
                    }
                    .lineLimit(1)
                }
            }
            .width(min: 80, ideal: 140, max: 240)
            .customizationID("app")
            TableColumn("Status", value: \.status) { (row: FlowRow) in StatusTag(flow: row.flow, selected: row.id == model.selectedFlowID) }
                .width(min: 44, ideal: 56, max: 80)
                .customizationID("status")
            TableColumn("Size", value: \.size) { (row: FlowRow) in Text(row.flow.response.map { Self.bytes($0.body.count) } ?? "") }
                .width(min: 50, ideal: 70, max: 110)
                .customizationID("size")
            TableColumn("Time", value: \.durationMS) { (row: FlowRow) in Text(Self.duration(row.flow)) }
                .width(min: 50, ideal: 70, max: 110)
                .customizationID("time")
            Group {
                TableColumn("Host", value: \.host) { (row: FlowRow) in Text(row.flow.request.host) }
                    .customizationID("host")
                    .defaultVisibility(.hidden)
                TableColumn("Content-Type") { (row: FlowRow) in Text(row.flow.response?.header("Content-Type") ?? "") }
                    .customizationID("contentType")
                    .defaultVisibility(.hidden)
                TableColumn("기기") { (row: FlowRow) in Text(deviceNames[row.flow.clientAddress] ?? row.flow.clientAddress) }
                    .customizationID("device")
                    .defaultVisibility(.hidden)
                TableColumn("시작 시각", value: \.startedAt) { (row: FlowRow) in Text(row.flow.startedAt, format: .dateTime.hour().minute().second()) }
                    .customizationID("startedAt")
                    .defaultVisibility(.hidden)
            }
        }
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: FlowID.self) { ids in
            if let id = ids.first, let flow = model.session.flow(id) {
                Button("Enable SSL Proxying for \(flow.request.host)") {
                    Task { await model.enableSSLProxying(for: flow.request.host) }
                }
                Button("Copy as cURL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CurlExport.command(for: flow.request), forType: .string)
                }
                Menu("Tools") {
                    ForEach(Self.toolWindows, id: \.id) { tool in
                        Button(tool.title) {
                            model.pendingNewRule = PendingNewRule(windowID: tool.id, flow: flow)
                            openWindow(id: tool.id)
                        }
                    }
                }
            }
        }
    }

    /// 우클릭 ▸ Tools ▸ … (스펙 §6.1). 선택 요청으로 미리 채운 새 규칙 편집기를 연다.
    private static let toolWindows: [(title: LocalizedStringKey, id: String)] = [
        ("Breakpoint…", "tool-breakpoint-rules"), ("Map Local…", "tool-map-local"), ("Map Remote…", "tool-map-remote"),
        ("Block List…", "tool-block"), ("Allow List…", "tool-allow"), ("Network Conditions…", "tool-network"),
    ]

    static func bytes(_ count: Int) -> String {
        Int64(count).formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    private static func duration(_ flow: Flow) -> String {
        guard let end = flow.completedAt else { return "" }
        let ms = Int((end.timeIntervalSince(flow.startedAt) * 1000).rounded())
        return String(localized: "\(ms) ms")
    }
}
