import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct FlowListView: View {
    @Environment(AppModel.self) private var model
    @Environment(SessionTab.self) private var tab
    @Environment(\.openWindow) private var openWindow
    // 열 구성이 바뀌어(Task 15b) 예전 저장값의 순서·폭이 섞이지 않게 키를 새로 쓴다.
    @AppStorage("eyeproxy.flowColumns.v2") private var columnCustomization = TableColumnCustomization<FlowRow>()
    /// 창이 열릴 때 첫 포커스는 목록(되살린 필터 막대 검색칸이 아니라) — ⌫·⌘N 같은 단축키가 그대로 동작하게(스펙 §9).
    @FocusState private var tableFocused: Bool

    var body: some View {
        @Bindable var tab = tab
        let rows = tab.visibleRows
        let deviceNames = Dictionary(model.devices.devices.map { ($0.address, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let comments = tab.session.comments

        let latest = AutoSelect.latest(in: rows)
        // Advanced ▸ Use 24-Hour Time · Display Full Time Format.
        let timeFormat = FlowRow.timeFormat(use24Hour: model.settings.use24HourTime, full: model.settings.displayFullTimeFormat)
        // General ▸ Truncation Style: URL·Client 열.
        let truncation: Text.TruncationMode = switch model.settings.truncationStyle {
        case .head: .head
        case .middle: .middle
        case .tail: .tail
        }

        // Proxyman 메인 목록과 같은 열·순서(Task 15b). 선택 열은 숨김 기본값.
        ScrollViewReader { proxy in
            // 사용자 선택만 `userSelect`를 거친다(Auto Select를 끄는 경로).
            Table(rows, selection: Binding(get: { tab.selectedFlowIDs }, set: { tab.userSelect($0) }), sortOrder: $tab.sortOrder, columnCustomization: $columnCustomization) {
                Group {
                    TableColumn("", value: \.state) { (row: FlowRow) in cell(row) {
                        Circle().fill(FlowColors.state(row.state)).frame(width: 8, height: 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .help(Self.stateText(row.state))
                            // 선택 행은 배경 대신 시스템 선택색이 보이므로 Highlight 색은 셀 높이만 한 막대로 보인다(스펙 §4).
                            .overlay(alignment: .leading) {
                                if let color = tab.session.highlights[row.id]?.color {
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
                        let struck = tab.session.highlights[row.id]?.strikethrough ?? false
                        (Text(row.host).foregroundStyle(struck ? .secondary : .primary).strikethrough(struck)
                            + Text(row.flow.request.path).foregroundStyle(.secondary).strikethrough(struck))
                            .lineLimit(1).truncationMode(truncation)
                    }}
                    .width(min: 200, ideal: 360)
                    .customizationID("url")
                    TableColumn("Client") { (row: FlowRow) in cell(row) {
                        let name = tab.clientName(for: row.flow)
                        if let identity = tab.processes.attribution[row.id] {
                            HStack(spacing: 5) {
                                AppIcon(path: identity.path)
                                Text(name)
                            }
                            .lineLimit(1).truncationMode(truncation)
                        } else if !name.isEmpty {
                            Text(name).lineLimit(1).truncationMode(truncation)
                        }
                    }}
                    .width(min: 80, ideal: 130, max: 240)
                    .customizationID("client")
                    TableColumn("Method", value: \.method) { (row: FlowRow) in cell(row) { MethodTag(method: row.method, selected: tab.selectedFlowIDs.contains(row.id)) }}
                        .width(min: 50, ideal: 70, max: 110)
                        .customizationID("method")
                    TableColumn("Status", value: \.state) { (row: FlowRow) in cell(row) { Text(Self.stateText(row.state)) }}
                        .width(min: 70, ideal: 86, max: 120)
                        .customizationID("state")
                    TableColumn("Code", value: \.status) { (row: FlowRow) in cell(row) {
                        if row.flow.response != nil {
                            StatusTag(flow: row.flow, selected: tab.selectedFlowIDs.contains(row.id))
                        } else if row.state == .active {
                            Text("-").foregroundStyle(.secondary)
                        }
                    }}
                    .width(min: 40, ideal: 50, max: 80)
                    .customizationID("code")
                    TableColumn("Time", value: \.startedAt) { (row: FlowRow) in cell(row) {
                        // 문자열로 먼저 만든다 — `Text(_:format:)`는 화면 로캘을 끼워 넣어 PM이 "오후"가 된다.
                        Text(verbatim: row.startedAt.formatted(timeFormat)).monospacedDigit()
                    }}
                    // 저장된 열 폭이 좁아도 형식이 잘리지 않게 최소 폭을 형식에 맞춘다.
                    .width(min: model.settings.displayFullTimeFormat ? 240 : model.settings.use24HourTime ? 90 : 140, ideal: 102, max: 280)
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
                            ForEach(row.editedMarks, id: \.self) { EditedTag(mark: $0, selected: tab.selectedFlowIDs.contains(row.id)) }
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
            // Appearance ▸ Alternative Rows Background Colors·Use Monospaced Font(스펙 §11).
            .alternatingRowBackgrounds(model.settings.alternativeRowBackgrounds ? .enabled : .disabled)
            .monospaced(model.settings.useMonospacedFont)
            .focused($tableFocused)
            .defaultFocus($tableFocused, true)
            // AppKit이 창을 처음 key로 만들며 키 뷰 순서의 첫 검색칸에 포커스를 주므로, 그 뒤에 목록으로 되돌린다.
            .task { tableFocused = true }
            // 필터 막대를 숨기면(막대에 포커스가 있었을 때) 목록으로 돌아온다.
            .onChange(of: tab.focusFlowList) { _, on in
                guard on else { return }
                tab.focusFlowList = false
                tableFocused = true
            }
            // 최신 행이 바뀔 때만 따라간다 — 응답 도착 같은 행 갱신으로 선택을 다시 쓰지 않는다. 켜면 바로 최신을 고른다.
            .onChange(of: latest) { followLatest(proxy) }
            .onChange(of: model.settings.autoSelectLatest, initial: true) { followLatest(proxy) }
            // Flow ▸ Repeat(⌘↩)는 메인 창이 key일 때만 켜진다 → 다른 창의 ⌘↩를 빼앗지 않는다.
            .focusedSceneValue(\.flowSelection, tab.selectedFlowIDs.isEmpty ? nil : tab.selectedFlowIDs)
            // Flow ▸ Delete(⌫)는 목록에 포커스가 있을 때만 켜진다 → 검색창·코멘트 시트의 ⌫를 빼앗지 않는다.
            .focusedValue(\.flowListSelection, tab.selectedFlowIDs)
            // Flow ▸ Delete All은 메인 창이 key이고 보이는 행이 있을 때만 → 창이 닫힌 뒤 확인 알림이 남지 않는다.
            .focusedSceneValue(\.visibleFlowCount, rows.count)
            .contextMenu(forSelectionType: FlowID.self) { ids in
                if !ids.isEmpty {
                    Button("Repeat") { model.repeatFlows(ids) }
                        .help("선택한 요청을 그대로 다시 보내기")
                }
                if ids.count == 1, let id = ids.first, let flow = tab.session.flow(id) {
                    Button("Edit and Repeat…") {
                        model.composeSeed = flow.request
                        openWindow(id: "compose")
                    }
                    .help("이 요청을 Compose에서 고쳐 보내기")
                    Divider()
                    Button("Enable SSL Proxying for \(flow.request.host)") {
                        Task { await model.enableSSLProxying(for: flow.request.host) }
                    }
                    .help("이 호스트를 SSL Proxying List에 넣고 복호화 켜기")
                    Button(tab.session.comments[id] == nil ? "Add Comment…" : "Edit Comment…") { tab.commentingFlowID = id }
                        .help("이 요청의 코멘트 쓰기·고치기")
                    Button("Copy as cURL") { tab.copyCurl(flow.id) }
                    .help("이 요청을 cURL 명령으로 복사")
                    Menu("Tools") {
                        ForEach(Self.toolWindows, id: \.id) { tool in
                            Button(tool.title) {
                                model.pendingNewRule = PendingNewRule(windowID: tool.id, flow: flow)
                                openWindow(id: tool.id)
                            }
                            .help("이 요청 URL로 채운 새 규칙 열기")
                        }
                    }
                    .help("이 요청으로 새 규칙 만들기")
                }
                if !ids.isEmpty {
                    Divider()
                    HighlightMenu(tab: tab) { ids }
                    ExportMenu(tab: tab) { ids }
                    Button("Delete") { tab.deleteFlows(ids) }
                        .help("선택한 요청을 목록에서 지우기")
                }
            }
            // Flow ▸ Delete All에서 필터가 숨긴 행이 있을 때만(스펙 §5).
            .alert(tab.pendingDeleteAll.map { String(localized: "보이는 \($0.ids.count)개를 지웁니다. 숨겨진 \($0.hiddenCount)개는 남습니다.") } ?? "",
                   isPresented: Binding(get: { tab.pendingDeleteAll != nil }, set: { if !$0 { tab.pendingDeleteAll = nil } }),
                   presenting: tab.pendingDeleteAll) { pending in
                Button("지우기", role: .destructive) { tab.deleteFlows(pending.ids) }
                Button("취소", role: .cancel) {}
            }
        }
    }

    /// 표가 새 행을 반영한 다음 고르고 스크롤한다 — 같은 갱신 안에서 바꾸면 아직 없는 행이라 스크롤되지 않는다.
    private func followLatest(_ proxy: ScrollViewProxy) {
        Task { if let id = tab.selectLatestIfAuto() { proxy.scrollTo(id) } }
    }

    /// 모든 셀에 행 Highlight 배경을 깐다. 선택 행은 시스템 선택색이 우선이라 깔지 않는다(스펙 §4).
    private func cell(_ row: FlowRow, @ViewBuilder _ content: () -> some View) -> some View {
        let color = tab.selectedFlowIDs.contains(row.id) ? nil : tab.session.highlights[row.id]?.color
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
}
