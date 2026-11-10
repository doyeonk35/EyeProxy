import AppKit
import EyeProxyKit
import Sparkle
import SwiftUI

@main struct EyeProxyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        Window("Prog", id: "main") {
            MainWindow()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 700)
                .task {
                    await model.startServer()
                    await model.autoOverrideSystemProxyAtLaunch()
                }
                // 앱 전체(설정·기기 창 포함)에 적용되도록 NSApp 수준에서 바꾼다.
                .onChange(of: model.settings.appearance, initial: true) { _, appearance in
                    NSApp.appearance = switch appearance {
                    case .system: nil
                    case .light: NSAppearance(named: .aqua)
                    case .dark: NSAppearance(named: .darkAqua)
                    }
                }
                .pendingProxyRestoreAlert(model)
                .systemErrorAlert(model, presenting: !model.devicesWindowOpen)
                .infoMessageAlert(model, presenting: !model.devicesWindowOpen)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("업데이트 확인…") { model.checkForUpdates() }
                    .help("새 버전이 있는지 확인")
            }
            CommandGroup(after: .newItem) {
                Button("세션 열기…") { Task { await model.openSession() } }
                    .keyboardShortcut("o")
                    .help("세션·HAR 파일을 열어 현재 세션 교체 (⌘O)")
                Button("세션 저장…") { Task { await model.saveSession() } }
                    .keyboardShortcut("s")
                    .help("현재 세션 전체를 Prog 세션 파일로 저장 (⌘S)")
                Button("세션 지우기") { model.clear() }
                    .keyboardShortcut("k")
                    .help("세션의 모든 요청 지우기 (⌘K)")
            }
            CommandGroup(after: .pasteboard) {
                CopyCurlButton(model: model)
            }
            CommandGroup(after: .toolbar) {
                LayoutPicker(model: model)
                Toggle("Auto Select the Latest Request", isOn: Bindable(model.settings).autoSelectLatest)
                    .help("새 요청이 오면 자동 선택 — 다른 행을 고르면 꺼짐")
            }
            FindCommands()
            ToolsCommands(model: model)
            CertificateCommands(model: model)
        }
        Settings {
            SettingsView()
                .environment(model)
        }
        Window("Breakpoints", id: "breakpoints") {
            BreakpointWindow().environment(model)
        }
        .defaultSize(width: 1100, height: 720)
        Window("Breakpoint Rules", id: "tool-breakpoint-rules") {
            BreakpointRulesWindow().environment(model)
        }
        .defaultSize(width: 1200, height: 672)
        Window("Breakpoint Templates", id: "breakpoint-templates") {
            BreakpointTemplatesWindow().environment(model)
        }
        .defaultSize(width: 800, height: 632)
        Window("Network Conditions", id: "tool-network") {
            NetworkConditionsWindow().environment(model)
        }
        .defaultSize(width: 1200, height: 672)
        Window("Block List", id: "tool-block") {
            BlockListWindow().environment(model)
        }
        .defaultSize(width: 1200, height: 672)
        Window("Allow List", id: "tool-allow") {
            AllowListWindow().environment(model)
        }
        .defaultSize(width: 1200, height: 672)
        Window("Map Local", id: "tool-map-local") {
            MapLocalWindow().environment(model)
        }
        .defaultSize(width: 1200, height: 672)
        WindowGroup("Map Local Editor", id: "map-local-editor", for: String.self) { $ruleID in
            if let ruleID { MapLocalEditor(ruleID: ruleID).environment(model) }
        }
        .defaultSize(width: 1050, height: 900)
        .restorationBehavior(.disabled)
        Window("Map Remote", id: "tool-map-remote") {
            MapRemoteWindow().environment(model)
        }
        .defaultSize(width: 1200, height: 672)
        Window("Compose", id: "compose") {
            ComposeView().environment(model)
        }
        .defaultSize(width: 1200, height: 732)
        // 복원으로 열리면 실행할 때마다 Proxyman 폴더를 읽게 되므로 복원하지 않는다.
        Window("Import from Proxyman", id: "import-proxyman") {
            ImportProxymanSheet().environment(model)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        Window("Certificate", id: "devices") {
            CertificateWindow()
                .environment(model)
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 860, height: 600)
        MenuBarExtra(isInserted: Bindable(model.settings).showStatusItem) {
            StatusMenu().environment(model)
        } label: {
            let icon = model.statusIcon
            Image(nsImage: StatusIconImage.make(icon)).accessibilityLabel(icon.accessibilityLabel)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct CopyCurlButton: View {
    let model: AppModel
    var body: some View {
        Button("cURL로 복사") { if let id = model.selectedFlowID { model.copyCurl(id) } }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.selectedFlowID == nil)
            .help("선택한 요청을 cURL 명령으로 복사 (⇧⌘C)")
    }
}

private struct LayoutPicker: View {
    let model: AppModel
    var body: some View {
        Picker("레이아웃", selection: Bindable(model.settings).layout) {
            Text("레이아웃 A").tag(FlowLayout.classic).help("상세 패널을 목록 아래에 두기")
            Text("레이아웃 B").tag(FlowLayout.sideBySide).help("상세 패널을 목록 오른쪽에 두기")
        }
        .pickerStyle(.inline)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    let model = AppModel()
    private var quitTask: Task<Void, Never>?
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        updaterController = updater
        model.checkForUpdates = { updater.checkForUpdates(nil) }
        // Advanced ▸ Show Update Notification at Launch: Sparkle 값을 그대로 보이고, 바꿀 때만 Sparkle에 쓴다.
        model.automaticUpdateChecks = updater.updater.automaticallyChecksForUpdates
        model.setAutomaticUpdateChecks = { updater.updater.automaticallyChecksForUpdates = $0 }
    }

    // 자동·수동 확인 모두 여기로 온다. 새 버전이 있을 때만 툴바 배지를 띄운다.
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { model.updateAvailable = true }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { model.updateAvailable = false }

    /// 시스템 프록시가 EyeProxy를 가리킬 수 있으면(캡처 중·변경 중·백업 잔여) 진행 중인 변경을 기다려 되돌린 뒤 종료한다.
    /// 실패해도 오류를 기록하고 종료 — 백업이 남아 다음 실행에서 복원을 제안한다. 두 번째 ⌘Q는 같은 작업을 기다린다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Advanced ▸ Show Alert when quitting the app.
        // 취소하면 아무것도 바꾸지 않게 Breakpoint를 놓기 전에 묻는다. 종료가 이미 진행 중이면 다시 묻지 않는다.
        if quitTask == nil, model.settings.showQuitAlert {
            let alert = NSAlert()
            alert.messageText = String(localized: "Prog를 종료할까요?")
            alert.addButton(withTitle: String(localized: "종료"))
            alert.addButton(withTitle: String(localized: "취소"))
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        // 멈춘 Breakpoint는 모두 원본대로 보낸다(§5.1).
        model.breakpoints.releaseAll()
        if quitTask != nil { return .terminateLater }
        guard model.needsProxyCleanupOnQuit else { return .terminateNow }
        model.quitting = true
        quitTask = Task {
            await model.prepareForQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 리슨 소켓은 프로세스 종료 시 커널이 닫는다. 종료를 NIO graceful shutdown에 묶지 않는다.
        try? model.devices.save()
    }
}

extension View {
    /// 관리자 인증창 등 다른 프로세스가 앞에 있어도 표시되도록 활성 상태에 묶지 않는다.
    /// 기기 창이 열려 있으면 거기서만(`presenting`), 닫혀 있으면 메인 창에서 띄워 한 번만 보이게 한다.
    func systemErrorAlert(_ model: AppModel, presenting: Bool) -> some View {
        alert("오류", isPresented: Binding(get: { presenting && model.systemError != nil },
                                         set: { if !$0 { model.systemError = nil } })) {
            Button("확인", role: .cancel) { model.systemError = nil }
        } message: {
            Text(model.systemError ?? "")
        }
    }

    /// 안내는 `systemErrorAlert`와 같은 창에서, 오류를 닫은 뒤에 뜬다.
    func infoMessageAlert(_ model: AppModel, presenting: Bool) -> some View {
        alert("안내", isPresented: Binding(get: { presenting && model.systemError == nil && model.infoMessage != nil },
                                         set: { if !$0 { model.infoMessage = nil } })) {
            Button("확인", role: .cancel) { model.infoMessage = nil }
        } message: {
            Text(model.infoMessage ?? "")
        }
    }

    func pendingProxyRestoreAlert(_ model: AppModel) -> some View {
        alert("이전 실행이 비정상 종료되어 시스템 프록시가 남아 있습니다. 복원할까요?",
              isPresented: Binding(get: { model.pendingProxyRestore != nil }, set: { if !$0 { model.pendingProxyRestore = nil } })) {
            Button("복원", role: .cancel) { Task { await model.restorePendingProxy() } }
                .keyboardShortcut(.defaultAction)
            Button("유지") { Task { await model.adoptPendingProxy() } }
        } message: {
            if let b = model.pendingProxyRestore { Text("네트워크 서비스: \(b.service)") }
        }
    }
}
