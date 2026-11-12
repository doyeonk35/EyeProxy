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

    // 포커스 값은 켜짐·꺼짐 판단에만 쓴다. 대상은 실행 시점의 선택(`activeTab.selectedFlowIDs`)이다 —
    // Auto Select가 앱이 뒤에 있을 때도 선택을 바꾸므로 마지막 메뉴 렌더 때 잡힌 값은 낡을 수 있다.
    var body: some View {
        let ids = selection ?? []
        let noTab = model.activeTab == nil
        let current = { selection == nil ? [] : model.activeTab?.selectedFlowIDs ?? [] }
        Button("Repeat") { model.repeatFlows(current()) }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(ids.isEmpty || noTab)
            .help("선택한 요청을 그대로 다시 보내기 (⌘↩)")
        Button("Edit and Repeat…") {
            guard let id = current().first, current().count == 1, let flow = model.activeTab?.session.flow(id) else { return }
            model.composeSeed = flow.request
            openWindow(id: "compose")
        }
        .keyboardShortcut(.return, modifiers: [.command, .option])
        .disabled(ids.count != 1 || noTab)
        .help("선택한 요청을 Compose에서 고쳐 보내기 (⌥⌘↩)")
        Divider()
        let tab = model.activeTab
        let id = tab?.selectedFlowID
        Button(id.flatMap { tab?.session.comments[$0] } == nil ? "Add Comment…" : "Edit Comment…") {
            if selection != nil, let tab = model.activeTab, let id = tab.selectedFlowID { tab.commentingFlowID = id }
        }
        .disabled(ids.count != 1 || noTab)
        .help("선택한 요청의 코멘트 쓰기·고치기")
        Divider()
        // 대상 탭과 선택은 같은 탭에서 읽는다(대상은 그린 때의 앞 탭, 선택은 실행 시점).
        HighlightMenu(tab: tab) { selection == nil ? [] : tab?.visibleSelectedFlowIDs ?? [] }
        Divider()
        Button("Delete") { if listSelection != nil, let tab = model.activeTab { tab.deleteFlows(tab.selectedFlowIDs) } }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled((listSelection ?? []).isEmpty || noTab)
            .help("선택한 요청을 목록에서 지우기 (⌫)")
        Button("Delete All") { model.activeTab?.deleteVisibleFlows() }
            .disabled((visibleCount ?? 0) == 0 || noTab)
            .help("목록에 보이는 요청 모두 지우기(숨은 요청은 남김)")
        Divider()
        // 필터가 숨긴 선택은 저장하지 않는다 → 보이는 선택이 없으면 끈다.
        Button("Save Requests…") { Task { await model.activeTab?.saveRequests() } }
            .disabled(selection == nil || (tab?.visibleSelectedFlowIDs ?? []).isEmpty)
            .help("선택한 요청을 Prog 세션 파일로 저장")
        // 선택이 있으면 선택, 없으면 보이는 행 전체(스펙 §8.4).
        ExportMenu(tab: tab) { tab?.selectedFlowIDs ?? [] }
            .disabled((visibleCount ?? 0) == 0)
    }
}

/// Flow ▸ Export와 목록 우클릭 ▸ Export(스펙 §8.4).
struct ExportMenu: View {
    /// nil이면(앞 탭 없음) 끈다.
    let tab: SessionTab?
    /// 실행 시점에 읽는다(Flow 메뉴는 현재 선택, 우클릭은 클릭한 행). 비면 보이는 행 전체.
    let ids: () -> Set<FlowID>

    var body: some View {
        Menu("Export") {
            Button("as HAR (HTTP Archive)…") { Task { await tab?.export(.har, scope: ids()) } }
                .help("HAR 1.2 파일로 저장")
            Button("as CSV…") { Task { await tab?.export(.csv, scope: ids()) } }
                .help("CSV 표 파일로 저장(Excel에서 열림)")
            Button("as Prog Session…") { Task { await tab?.export(.session, scope: ids()) } }
                .help("Prog 세션 파일로 저장")
        }
        .disabled(tab == nil)
        .help("선택한 요청(없으면 보이는 요청 전체)을 파일로 내보내기")
    }
}

/// Flow ▸ Highlight와 목록 우클릭 ▸ Highlight(스펙 §4). 색 ⌘1…⌘6, 취소선 ⇧⌘X(⌥⌘S는 사이드바 토글과 겹친다), 되돌리기 ⌘0.
struct HighlightMenu: View {
    /// nil이면(앞 탭 없음) 끈다.
    let tab: SessionTab?
    /// 실행 시점에 읽는다(Flow 메뉴는 현재 선택, 우클릭은 클릭한 행).
    let ids: () -> Set<FlowID>

    var body: some View {
        Menu("Highlight") {
            ForEach(Array(HighlightColor.allCases.enumerated()), id: \.element) { i, color in
                Button(color.rawValue.capitalized) { tab?.session.setHighlight(color, for: ids()) }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))))
                    .help("요청 행을 \(color.rawValue.capitalized) 색으로 표시 (⌘\(i + 1))")
            }
            Divider()
            Button("Strikethrough") { tab?.session.toggleStrikethrough(for: ids()) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .help("요청 행에 취소선 긋기/지우기 (⇧⌘X)")
            Button("Reset") { tab?.session.resetHighlight(for: ids()) }
                .keyboardShortcut("0")
                .help("색과 취소선 모두 지우기 (⌘0)")
        }
        .disabled(tab == nil || ids().isEmpty)
        .help("요청 행에 색·취소선 표시")
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
        .help("HTTPS를 복호화할 호스트 목록 설정 열기")
        Button("Compose Request…") { openWindow(id: "compose") }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .help("요청을 직접 만들어 보내기 (⌥⌘C)")
        Divider()
        Menu("Breakpoint") {
            Button("Rules…") { openWindow(id: "tool-breakpoint-rules") }
                .help("멈출 요청을 정하는 규칙 편집")
            Button("Breakpoints…") { openWindow(id: "breakpoints") }
                .help("멈춘 요청·응답을 보고 고쳐 보내기")
            Button("Breakpoint Templates…") { openWindow(id: "breakpoint-templates") }
                .help("Breakpoint에서 불러 쓸 템플릿 관리")
        }
        .help("요청·응답을 멈춰 고치는 Breakpoint 도구")
        Button("Map Local…") { openWindow(id: "tool-map-local") }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .help("요청에 로컬 파일로 응답하는 규칙 (⌥⌘L)")
        Button("Map Remote…") { openWindow(id: "tool-map-remote") }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .help("요청을 다른 주소로 보내는 규칙 (⌥⌘R)")
        Button("Block List…") { openWindow(id: "tool-block") }
            .keyboardShortcut("[", modifiers: [.command, .option])
            .help("요청을 막거나 목록에서 숨기는 규칙 (⌥⌘[)")
        Button("Allow List…") { openWindow(id: "tool-allow") }
            .keyboardShortcut("]", modifiers: [.command, .option])
            .help("규칙에 맞는 요청만 기록하는 규칙 (⌥⌘])")
        Toggle("No Caching", isOn: $settings.toolSwitches.noCaching)
            .keyboardShortcut("n", modifiers: [.command, .option])
            .help("캐시를 끄고 늘 서버에서 새로 받기 (⌥⌘N)")
        Divider()
        Button("Network Conditions…") { openWindow(id: "tool-network") }
            .keyboardShortcut("j", modifiers: [.command, .option])
            .help("느린 네트워크를 흉내 내는 규칙 (⌥⌘J)")
        Divider()
        Menu("Enable/Disable Tools") {
            Toggle("Breakpoint", isOn: $settings.toolSwitches.breakpoint).help("Breakpoint 규칙 전체 켜기/끄기")
            Toggle("Map Local", isOn: $settings.toolSwitches.mapLocal).help("Map Local 규칙 전체 켜기/끄기")
            Toggle("Map Remote", isOn: $settings.toolSwitches.mapRemote).help("Map Remote 규칙 전체 켜기/끄기")
            Toggle("Block List", isOn: $settings.toolSwitches.blockList).help("Block List 규칙 전체 켜기/끄기")
            Toggle("Allow List", isOn: $settings.toolSwitches.allowList).help("Allow List 규칙 전체 켜기/끄기")
            Toggle("Network Conditions", isOn: $settings.toolSwitches.networkConditions).help("Network Conditions 규칙 전체 켜기/끄기")
        }
        .help("규칙은 둔 채 도구별로 켜고 끄기")
        Divider()
        Menu("Import Settings") {
            Button("From Proxyman…") { openWindow(id: "import-proxyman") }
                .help("Proxyman의 규칙·설정 가져오기")
        }
        .help("다른 앱의 규칙·설정 가져오기")
        Divider()
        Menu("Proxy Settings") {
            Toggle("Record Traffic", isOn: $settings.isRecording)
                .keyboardShortcut("r")
                .help("새 요청 기록 켜기/끄기 (⌘R)")
            MacProxyOverrideToggle(title: "Override macOS Proxy", model: model)
            Divider()
            Button("Restart Server") { Task { await model.restartServer() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("프록시 서버 다시 시작 (⇧⌘R)")
            Button("Bypass Proxy Settings…") {
                model.settingsTab = .bypass
                openSettings()
            }
            .help("프록시를 거치지 않을 호스트 설정 열기")
        }
        .help("기록·시스템 프록시·서버 설정")
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
            .help("macOS 시스템 프록시를 Prog로 바꾸기/되돌리기")
    }
}
