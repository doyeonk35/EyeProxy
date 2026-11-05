import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct FlowListView: View {
    @Environment(AppModel.self) private var model
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
            TableColumn("Method", value: \.method) { (row: FlowRow) in MethodTag(method: row.method) }
                .width(min: 50, ideal: 70, max: 110)
                .customizationID("method")
            TableColumn("URL", value: \.url) { (row: FlowRow) in
                (Text(row.host).foregroundStyle(.primary) + Text(row.flow.request.path).foregroundStyle(.secondary))
                    .lineLimit(1).truncationMode(.middle)
            }
            .width(min: 200, ideal: 480)
            .customizationID("url")
            TableColumn("Status", value: \.status) { (row: FlowRow) in StatusTag(flow: row.flow) }
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
                TableColumn("앱") { (row: FlowRow) in Text(model.processes.attribution[row.id]?.displayName(runtimes: model.simulatorRuntimes) ?? "") }
                    .customizationID("app")
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
            }
        }
    }

    static func bytes(_ count: Int) -> String {
        Int64(count).formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    private static func duration(_ flow: Flow) -> String {
        guard let end = flow.completedAt else { return "" }
        let ms = Int((end.timeIntervalSince(flow.startedAt) * 1000).rounded())
        return String(localized: "\(ms) ms")
    }
}
