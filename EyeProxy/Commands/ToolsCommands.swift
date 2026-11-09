import EyeProxyCore
import EyeProxyKit
import SwiftUI

/// Flow·Tools 메뉴(스펙 §6.1).
struct ToolsCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Flow") { FlowMenu(model: model) }
        CommandMenu("Tools") { ToolsMenu(model: model) }
    }
}

extension FocusedValues {
    /// 메인 창이 key일 때의 목록 선택. 다른 창(Compose·Breakpoint 등)이 앞이면 nil → Repeat ⌘↩가 그 창의 ⌘↩를 가로채지 않는다.
    @Entry var flowSelection: Set<FlowID>?
    /// 목록 자체에 포커스가 있을 때의 선택. 맨 ⌫(Delete)가 검색창·시트의 글자 지우기를 빼앗지 않게 한다.
    @Entry var flowListSelection: Set<FlowID>?
    /// 메인 창이 key일 때 목록에 보이는 행 수. 다른 창이 앞이면 nil.
    @Entry var visibleFlowCount: Int?
}

/// 선택된 흐름에 적용하는 항목(스펙 §5.8·§6.1).
private struct FlowMenu: View {
    let model: AppModel
    @FocusedValue(\.flowSelection) private var selection
    @FocusedValue(\.flowListSelection) private var listSelection
    @FocusedValue(\.visibleFlowCount) private var visibleCount
    @Environment(\.openWindow) private var openWindow

    // 포커스 값은 켜짐·꺼짐 판단에만 쓴다. 대상은 실행 시점의 선택(`model.selectedFlowIDs`)이다 —
    // Auto Select가 앱이 뒤에 있을 때도 선택을 바꾸므로 마지막 메뉴 렌더 때 잡힌 값은 낡을 수 있다.
    var body: some View {
        let ids = selection ?? []
        let current = { selection == nil ? [] : model.selectedFlowIDs }
        Button("Repeat") { model.repeatFlows(current()) }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(ids.isEmpty)
        Button("Edit and Repeat…") {
            guard let id = current().first, current().count == 1, let flow = model.session.flow(id) else { return }
            model.composeSeed = flow.request
            openWindow(id: "compose")
        }
        .keyboardShortcut(.return, modifiers: [.command, .option])
        .disabled(ids.count != 1)
        Divider()
        let id = model.selectedFlowID
        Button(id.flatMap { model.session.comments[$0] } == nil ? "Add Comment…" : "Edit Comment…") {
            if selection != nil, let id = model.selectedFlowID { model.commentingFlowID = id }
        }
        .disabled(ids.count != 1)
        Divider()
        HighlightMenu(model: model, ids: current)
        Divider()
        Button("Delete") { if listSelection != nil { model.deleteFlows(model.selectedFlowIDs) } }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled((listSelection ?? []).isEmpty)
        Button("Delete All") { model.deleteVisibleFlows() }
            .disabled((visibleCount ?? 0) == 0)
        Divider()
        // 필터가 숨긴 선택은 저장하지 않는다 → 보이는 선택이 없으면 끈다.
        Button("Save Requests…") { Task { await model.saveRequests() } }
            .disabled(selection == nil || model.visibleSelectedFlowIDs.isEmpty)
        // 선택이 있으면 선택, 없으면 보이는 행 전체(스펙 §8.4).
        ExportMenu(model: model) { model.selectedFlowIDs }
            .disabled((visibleCount ?? 0) == 0)
    }
}

/// Flow ▸ Export와 목록 우클릭 ▸ Export(스펙 §8.4).
struct ExportMenu: View {
    let model: AppModel
    /// 실행 시점에 읽는다(Flow 메뉴는 현재 선택, 우클릭은 클릭한 행). 비면 보이는 행 전체.
    let ids: () -> Set<FlowID>

    var body: some View {
        Menu("Export") {
            Button("as HAR (HTTP Archive)…") { Task { await model.export(.har, scope: ids()) } }
            Button("as CSV…") { Task { await model.export(.csv, scope: ids()) } }
            Button("as Prog Session…") { Task { await model.export(.session, scope: ids()) } }
        }
    }
}

/// Flow ▸ Highlight와 목록 우클릭 ▸ Highlight(스펙 §4). 색 ⌘1…⌘6, 취소선 ⇧⌘X(⌥⌘S는 사이드바 토글과 겹친다), 되돌리기 ⌘0.
struct HighlightMenu: View {
    let model: AppModel
    /// 실행 시점에 읽는다(Flow 메뉴는 현재 선택, 우클릭은 클릭한 행).
    let ids: () -> Set<FlowID>

    var body: some View {
        Menu("Highlight") {
            ForEach(Array(HighlightColor.allCases.enumerated()), id: \.element) { i, color in
                Button(color.rawValue.capitalized) { model.session.setHighlight(color, for: ids()) }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))))
            }
            Divider()
            Button("Strikethrough") { model.session.toggleStrikethrough(for: ids()) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Reset") { model.session.resetHighlight(for: ids()) }
                .keyboardShortcut("0")
        }
        .disabled(ids().isEmpty)
    }
}

private struct ToolsMenu: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var settings = model.settings
        Button("SSL Proxying List…") {
            model.settingsTab = .ssl
            openSettings()
        }
        Button("Compose Request…") { openWindow(id: "compose") }
            .keyboardShortcut("c", modifiers: [.command, .option])
        Divider()
        Menu("Breakpoint") {
            Button("Rules…") { openWindow(id: "tool-breakpoint-rules") }
            Button("Breakpoints…") { openWindow(id: "breakpoints") }
            Button("Breakpoint Templates…") { openWindow(id: "breakpoint-templates") }
        }
        Button("Map Local…") { openWindow(id: "tool-map-local") }
            .keyboardShortcut("l", modifiers: [.command, .option])
        Button("Map Remote…") { openWindow(id: "tool-map-remote") }
            .keyboardShortcut("r", modifiers: [.command, .option])
        Button("Block List…") { openWindow(id: "tool-block") }
            .keyboardShortcut("[", modifiers: [.command, .option])
        Button("Allow List…") { openWindow(id: "tool-allow") }
            .keyboardShortcut("]", modifiers: [.command, .option])
        Toggle("No Caching", isOn: $settings.toolSwitches.noCaching)
            .keyboardShortcut("n", modifiers: [.command, .option])
        Divider()
        Button("Network Conditions…") { openWindow(id: "tool-network") }
            .keyboardShortcut("j", modifiers: [.command, .option])
        Divider()
        Menu("Enable/Disable Tools") {
            Toggle("Breakpoint", isOn: $settings.toolSwitches.breakpoint)
            Toggle("Map Local", isOn: $settings.toolSwitches.mapLocal)
            Toggle("Map Remote", isOn: $settings.toolSwitches.mapRemote)
            Toggle("Block List", isOn: $settings.toolSwitches.blockList)
            Toggle("Allow List", isOn: $settings.toolSwitches.allowList)
            Toggle("Network Conditions", isOn: $settings.toolSwitches.networkConditions)
        }
        Divider()
        Menu("Import Settings") {
            Button("From Proxyman…") { openWindow(id: "import-proxyman") }
        }
        Divider()
        Menu("Proxy Settings") {
            Toggle("Record Traffic", isOn: $settings.isRecording)
                .keyboardShortcut("r")
            MacProxyOverrideToggle(title: "Override macOS Proxy", model: model)
            Divider()
            Button("Restart Server") { Task { await model.restartServer() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Bypass Proxy Settings…") {
                model.settingsTab = .bypass
                openSettings()
            }
        }
    }
}

/// Tools ▸ Proxy Settings와 상태 막대 메뉴의 macOS 프록시 토글(같은 바인딩).
struct MacProxyOverrideToggle: View {
    let title: String
    let model: AppModel

    var body: some View {
        Toggle(title, isOn: Binding(get: { model.macCaptureEnabled || model.effectiveProxyLeftover },
                                    set: { on in Task { await model.setMacCapture(on) } }))
            .disabled(model.macCaptureBusy)
    }
}
