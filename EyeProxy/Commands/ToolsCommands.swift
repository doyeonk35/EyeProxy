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

    var body: some View {
        let ids = selection ?? []
        Button("Repeat") { model.repeatFlows(ids) }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(ids.isEmpty)
        Button("Edit and Repeat…") {
            guard let id = ids.first, let flow = model.session.flow(id) else { return }
            model.composeSeed = flow.request
            openWindow(id: "compose")
        }
        .keyboardShortcut(.return, modifiers: [.command, .option])
        .disabled(ids.count != 1)
        Divider()
        let id = model.selectedFlowID
        Button(id.flatMap { model.session.comments[$0] } == nil ? "Add Comment…" : "Edit Comment…") { model.commentingFlowID = id }
            .disabled(id == nil)
        Divider()
        HighlightMenu(model: model, ids: ids)
        Divider()
        let listIDs = listSelection ?? []
        Button("Delete") { model.deleteFlows(listIDs) }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(listIDs.isEmpty)
        Button("Delete All") { model.deleteVisibleFlows() }
            .disabled((visibleCount ?? 0) == 0)
    }
}

/// Flow ▸ Highlight와 목록 우클릭 ▸ Highlight(스펙 §4). 색 ⌘1…⌘6, 취소선 ⇧⌘X(⌥⌘S는 사이드바 토글과 겹친다), 되돌리기 ⌘0.
struct HighlightMenu: View {
    let model: AppModel
    let ids: Set<FlowID>

    var body: some View {
        Menu("Highlight") {
            ForEach(Array(HighlightColor.allCases.enumerated()), id: \.element) { i, color in
                Button(color.rawValue.capitalized) { model.session.setHighlight(color, for: ids) }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))))
            }
            Divider()
            Button("Strikethrough") { model.session.toggleStrikethrough(for: ids) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Reset") { model.session.resetHighlight(for: ids) }
                .keyboardShortcut("0")
        }
        .disabled(ids.isEmpty)
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
