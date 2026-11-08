import EyeProxyCore
import EyeProxyKit
import SwiftUI

/// Flow·Tools 메뉴(스펙 §6.1). 각 창은 해당 태스크가 채운다(아직 없는 창은 자리표시자).
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
}

/// 선택된 흐름에 적용하는 항목(스펙 §5.8·§6.1).
private struct FlowMenu: View {
    let model: AppModel
    @FocusedValue(\.flowSelection) private var selection
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
    }
}

/// 다음 태스크가 채울 창 자리. 메뉴·우클릭에서 열리는지만 보장한다.
struct PlaceholderToolScenes: Scene {
    var body: some Scene {
        placeholder("Import from Proxyman", id: "import-proxyman")
    }

    private func placeholder(_ title: String, id: String) -> some Scene {
        Window(title, id: id) {
            Text("다음 작업에서 추가됩니다").frame(minWidth: 400, minHeight: 200)
        }
    }
}
