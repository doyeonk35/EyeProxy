import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct FlowListView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("eyeproxy.flowColumns") private var columnCustomization = TableColumnCustomization<Flow>()

    var body: some View {
        @Bindable var model = model
        let rows = model.visibleFlows
        // ponytail: 렌더마다 O(n) 색인. 수만 행에서 느려지면 SessionStore에 순번 저장.
        let number = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0 + 1) })
        let deviceNames = Dictionary(model.devices.devices.map { ($0.address, $0.displayName) }, uniquingKeysWith: { a, _ in a })

        Table(rows, selection: $model.selectedFlowID, columnCustomization: $columnCustomization) {
            TableColumn("#") { (flow: Flow) in Text(number[flow.id] ?? 0, format: .number.grouping(.never)).monospacedDigit() }
                .width(min: 32, ideal: 44, max: 80)
                .customizationID("index")
            TableColumn("Method") { (flow: Flow) in Text(flow.request.method) }
                .width(min: 50, ideal: 70, max: 110)
                .customizationID("method")
            TableColumn("URL") { (flow: Flow) in Text(flow.request.url).lineLimit(1).truncationMode(.middle) }
                .width(min: 200, ideal: 480)
                .customizationID("url")
            TableColumn("Status") { (flow: Flow) in StatusText(flow: flow) }
                .width(min: 44, ideal: 56, max: 80)
                .customizationID("status")
            TableColumn("Size") { (flow: Flow) in Text(flow.response.map { Self.bytes($0.body.count) } ?? "") }
                .width(min: 50, ideal: 70, max: 110)
                .customizationID("size")
            TableColumn("Time") { (flow: Flow) in Text(Self.duration(flow)) }
                .width(min: 50, ideal: 70, max: 110)
                .customizationID("time")
            TableColumn("Host") { (flow: Flow) in Text(flow.request.host) }
                .customizationID("host")
                .defaultVisibility(.hidden)
            TableColumn("Content-Type") { (flow: Flow) in Text(flow.response?.header("Content-Type") ?? "") }
                .customizationID("contentType")
                .defaultVisibility(.hidden)
            TableColumn("기기") { (flow: Flow) in Text(deviceNames[flow.clientAddress] ?? flow.clientAddress) }
                .customizationID("device")
                .defaultVisibility(.hidden)
            TableColumn("시작 시각") { (flow: Flow) in Text(flow.startedAt, format: .dateTime.hour().minute().second()) }
                .customizationID("startedAt")
                .defaultVisibility(.hidden)
        }
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

private struct StatusText: View {
    let flow: Flow

    var body: some View {
        if let status = flow.response?.status {
            Text(String(status))
                .foregroundStyle(200..<300 ~= status ? Color.green : status >= 400 ? Color.red : Color.primary)
        } else if flow.error != nil {
            Text("오류").foregroundStyle(.red)
        } else {
            Text(verbatim: "…").foregroundStyle(.secondary)
        }
    }
}
