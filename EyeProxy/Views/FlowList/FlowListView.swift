import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct FlowListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    // 열 구성이 바뀌어(Task 15b) 예전 저장값의 순서·폭이 섞이지 않게 키를 새로 쓴다.
    @AppStorage("eyeproxy.flowColumns.v2") private var columnCustomization = TableColumnCustomization<FlowRow>()

    var body: some View {
        @Bindable var model = model
        let rows = model.visibleRows
        let deviceNames = Dictionary(model.devices.devices.map { ($0.address, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let comments = model.session.comments

        // Proxyman 메인 목록과 같은 열·순서(Task 15b). 선택 열은 숨김 기본값.
        Table(rows, selection: $model.selectedFlowIDs, sortOrder: $model.sortOrder, columnCustomization: $columnCustomization) {
            Group {
                TableColumn("", value: \.state) { (row: FlowRow) in cell(row) {
                    Circle().fill(FlowColors.state(row.state)).frame(width: 8, height: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .help(Self.stateText(row.state))
                        // 선택 행은 배경 대신 시스템 선택색이 보이므로 Highlight 색은 셀 높이만 한 막대로 보인다(스펙 §4).
                        .overlay(alignment: .leading) {
                            if let color = model.session.highlights[row.id]?.color {
                                color.swiftUIColor.frame(width: 3).padding(.vertical, -RowHighlight.verticalBleed)
                            }
                        }
                }}
                .width(16)
                .customizationID("stateDot")
                TableColumn("ID", value: \.number) { (row: FlowRow) in cell(row) {
                    Text(row.number, format: .number.grouping(.never)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }}
                .width(min: 32, ideal: 48, max: 80)
                .customizationID("id")
                TableColumn("URL", value: \.url) { (row: FlowRow) in cell(row) {
                    let struck = model.session.highlights[row.id]?.strikethrough ?? false
                    (Text(row.host).foregroundStyle(struck ? .secondary : .primary).strikethrough(struck)
                        + Text(row.flow.request.path).foregroundStyle(.secondary).strikethrough(struck))
                        .lineLimit(1).truncationMode(.middle)
                }}
                .width(min: 200, ideal: 360)
                .customizationID("url")
                TableColumn("Client") { (row: FlowRow) in cell(row) {
                    if let identity = model.processes.attribution[row.id] {
                        HStack(spacing: 5) {
                            AppIcon(path: identity.path)
                            Text(identity.displayName(runtimes: model.simulatorRuntimes))
                        }
                        .lineLimit(1)
                    } else if !FlowFilter.isLoopback(row.flow.clientAddress) {
                        Text(deviceNames[row.flow.clientAddress] ?? row.flow.clientAddress).lineLimit(1)
                    }
                }}
                .width(min: 80, ideal: 130, max: 240)
                .customizationID("client")
                TableColumn("Method", value: \.method) { (row: FlowRow) in cell(row) { MethodTag(method: row.method, selected: model.selectedFlowIDs.contains(row.id)) }}
                    .width(min: 50, ideal: 70, max: 110)
                    .customizationID("method")
                TableColumn("Status", value: \.state) { (row: FlowRow) in cell(row) { Text(Self.stateText(row.state)) }}
                    .width(min: 70, ideal: 86, max: 120)
                    .customizationID("state")
                TableColumn("Code", value: \.status) { (row: FlowRow) in cell(row) {
                    if row.flow.response != nil { StatusTag(flow: row.flow, selected: model.selectedFlowIDs.contains(row.id)) }
                }}
                .width(min: 40, ideal: 50, max: 80)
                .customizationID("code")
                TableColumn("Time", value: \.startedAt) { (row: FlowRow) in cell(row) {
                    Text(row.startedAt, format: Self.timeFormat).monospacedDigit()
                }}
                .width(min: 90, ideal: 102, max: 140)
                .customizationID("time")
                TableColumn("Duration", value: \.durationMS) { (row: FlowRow) in cell(row) {
                    Text(FlowRow.durationText(ms: row.durationMS)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }}
                .width(min: 50, ideal: 72, max: 110)
                .customizationID("duration")
                TableColumn("Request", value: \.requestSize) { (row: FlowRow) in cell(row) {
                    Text(row.requestSize > 0 ? ByteSize.format(row.requestSize) : "-").frame(maxWidth: .infinity, alignment: .trailing)
                }}
                .width(min: 72, ideal: 80, max: 120)
                .customizationID("requestSize")
            }
            Group {
                TableColumn("Response", value: \.responseSize) { (row: FlowRow) in cell(row) {
                    Text(row.responseSize > 0 ? ByteSize.format(row.responseSize) : "-").frame(maxWidth: .infinity, alignment: .trailing)
                }}
                .width(min: 72, ideal: 80, max: 120)
                .customizationID("responseSize")
                TableColumn("SSL") { (row: FlowRow) in cell(row) {
                    if row.isSSL { Image(systemName: "lock.fill").foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                }}
                .width(min: 28, ideal: 34, max: 50)
                .customizationID("ssl")
                TableColumn("Edited", value: \.edited) { (row: FlowRow) in cell(row) {
                    HStack(spacing: 4) {
                        ForEach(row.editedMarks, id: \.self) { EditedTag(mark: $0, selected: model.selectedFlowIDs.contains(row.id)) }
                    }
                    .lineLimit(1)
                }}
                .width(min: 60, ideal: 110, max: 260)
                .customizationID("edited")
                TableColumn("Comment") { (row: FlowRow) in cell(row) {
                    Text(comments[row.id].map { $0.replacing("\n", with: " ") } ?? "").lineLimit(1).truncationMode(.tail)
                }}
                .width(min: 60, ideal: 160)
                .customizationID("comment")
                TableColumn("Host", value: \.host) { (row: FlowRow) in cell(row) { Text(row.flow.request.host) }}
                    .customizationID("host")
                    .defaultVisibility(.hidden)
                TableColumn("Content-Type") { (row: FlowRow) in cell(row) { Text(row.flow.response?.header("Content-Type") ?? "") }}
                    .customizationID("contentType")
                    .defaultVisibility(.hidden)
                TableColumn("기기") { (row: FlowRow) in cell(row) { Text(deviceNames[row.flow.clientAddress] ?? row.flow.clientAddress) }}
                    .customizationID("device")
                    .defaultVisibility(.hidden)
            }
        }
        .alternatingRowBackgrounds(.disabled)
        // Flow ▸ Repeat(⌘↩)는 메인 창이 key일 때만 켜진다 → 다른 창의 ⌘↩를 빼앗지 않는다.
        .focusedSceneValue(\.flowSelection, model.selectedFlowIDs.isEmpty ? nil : model.selectedFlowIDs)
        // Flow ▸ Delete(⌫)는 목록에 포커스가 있을 때만 켜진다 → 검색창·코멘트 시트의 ⌫를 빼앗지 않는다.
        .focusedValue(\.flowListSelection, model.selectedFlowIDs)
        // Flow ▸ Delete All은 메인 창이 key이고 보이는 행이 있을 때만 → 창이 닫힌 뒤 확인 알림이 남지 않는다.
        .focusedSceneValue(\.visibleFlowCount, rows.count)
        .contextMenu(forSelectionType: FlowID.self) { ids in
            if !ids.isEmpty {
                Button("Repeat") { model.repeatFlows(ids) }
            }
            if ids.count == 1, let id = ids.first, let flow = model.session.flow(id) {
                Button("Edit and Repeat…") {
                    model.composeSeed = flow.request
                    openWindow(id: "compose")
                }
                Divider()
                Button("Enable SSL Proxying for \(flow.request.host)") {
                    Task { await model.enableSSLProxying(for: flow.request.host) }
                }
                Button(model.session.comments[id] == nil ? "Add Comment…" : "Edit Comment…") { model.commentingFlowID = id }
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
            if !ids.isEmpty {
                Divider()
                HighlightMenu(model: model, ids: ids)
                Button("Delete") { model.deleteFlows(ids) }
            }
        }
        // Flow ▸ Delete All에서 필터가 숨긴 행이 있을 때만(스펙 §5).
        .alert(model.pendingDeleteAll.map { String(localized: "보이는 \($0.ids.count)개를 지웁니다. 숨겨진 \($0.hiddenCount)개는 남습니다.") } ?? "",
               isPresented: Binding(get: { model.pendingDeleteAll != nil }, set: { if !$0 { model.pendingDeleteAll = nil } }),
               presenting: model.pendingDeleteAll) { pending in
            Button("지우기", role: .destructive) { model.deleteFlows(pending.ids) }
            Button("취소", role: .cancel) {}
        }
    }

    /// 모든 셀에 행 Highlight 배경을 깐다. 선택 행은 시스템 선택색이 우선이라 깔지 않는다(스펙 §4).
    private func cell(_ row: FlowRow, @ViewBuilder _ content: () -> some View) -> some View {
        let color = model.selectedFlowIDs.contains(row.id) ? nil : model.session.highlights[row.id]?.color
        return content().modifier(RowHighlight(color: color))
    }

    /// 우클릭 ▸ Tools ▸ … (스펙 §6.1). 선택 요청으로 미리 채운 새 규칙 편집기를 연다.
    private static let toolWindows: [(title: LocalizedStringKey, id: String)] = [
        ("Breakpoint…", "tool-breakpoint-rules"), ("Map Local…", "tool-map-local"), ("Map Remote…", "tool-map-remote"),
        ("Block List…", "tool-block"), ("Allow List…", "tool-allow"), ("Network Conditions…", "tool-network"),
    ]

    private static func stateText(_ state: FlowState) -> String {
        switch state {
        case .completed: "Completed"
        case .active: "Active"
        case .failed: "Failed"
        }
    }

    /// 시작 시각 `HH:mm:ss.SSS`(24시간, 로캘 무관).
    private static let timeFormat = Date.VerbatimFormatStyle(
        format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
        timeZone: .current, calendar: .current)
}
