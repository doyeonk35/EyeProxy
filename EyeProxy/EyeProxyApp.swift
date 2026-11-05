import AppKit
import EyeProxyKit
import Sparkle
import SwiftUI

@main struct EyeProxyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var model: AppModel { appDelegate.model }
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        Window("EyeProxy", id: "main") {
            MainWindow()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 700)
                .task { await model.startServer() }
                .pendingProxyRestoreAlert(model)
                .systemErrorAlert(model)
        }
        .commands {
            // 툴바 버튼의 keyboardShortcut은 동작하지 않아 메뉴 막대에 둔다.
            CommandMenu("프록시") {
                Toggle("기록", isOn: Bindable(model.settings).isRecording)
                    .keyboardShortcut("r")
                Divider()
                OpenDevicesButton()
            }
            CommandGroup(after: .appInfo) {
                Button("업데이트 확인…") { updaterController.checkForUpdates(nil) }
            }
            CommandGroup(after: .newItem) {
                Button("세션 열기…") { Task { await model.openSession() } }
                    .keyboardShortcut("o")
                Button("세션 저장…") { Task { await model.saveSession() } }
                    .keyboardShortcut("s")
                Button("세션 지우기") { model.clear() }
                    .keyboardShortcut("k")
            }
            CommandGroup(after: .pasteboard) {
                CopyCurlButton(model: model)
            }
            CommandGroup(after: .toolbar) {
                LayoutPicker(model: model)
            }
        }
        Settings {
            SettingsView()
                .environment(model)
                .systemErrorAlert(model)
        }
        Window("기기", id: "devices") {
            DevicesView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 600)
                .systemErrorAlert(model)
        }
    }
}

private struct CopyCurlButton: View {
    let model: AppModel
    var body: some View {
        Button("cURL로 복사") { if let id = model.selectedFlowID { model.copyCurl(id) } }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.selectedFlowID == nil)
    }
}

private struct LayoutPicker: View {
    let model: AppModel
    var body: some View {
        Picker("레이아웃", selection: Bindable(model.settings).layout) {
            Text("레이아웃 A").tag(FlowLayout.classic)
            Text("레이아웃 B").tag(FlowLayout.sideBySide)
        }
        .pickerStyle(.inline)
    }
}

private struct OpenDevicesButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("기기…") { openWindow(id: "devices") }
            .keyboardShortcut("d")
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var quitTask: Task<Void, Never>?

    /// 시스템 프록시가 EyeProxy를 가리킬 수 있으면(캡처 중·변경 중·백업 잔여) 진행 중인 변경을 기다려 되돌린 뒤 종료한다.
    /// 실패해도 오류를 기록하고 종료 — 백업이 남아 다음 실행에서 복원을 제안한다. 두 번째 ⌘Q는 같은 작업을 기다린다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
    /// 기기·메인 윈도우가 함께 떠 있어도 키 윈도우 한 곳에만 띄운다.
    func systemErrorAlert(_ model: AppModel) -> some View { modifier(SystemErrorAlert(model: model)) }

    func pendingProxyRestoreAlert(_ model: AppModel) -> some View {
        alert("이전 실행이 비정상 종료되어 시스템 프록시가 남아 있습니다. 복원할까요?",
              isPresented: Binding(get: { model.pendingProxyRestore != nil }, set: { if !$0 { model.pendingProxyRestore = nil } })) {
            Button("복원", role: .cancel) { Task { await model.restorePendingProxy() } }
            Button("유지") { Task { await model.adoptPendingProxy() } }
        } message: {
            if let b = model.pendingProxyRestore { Text("네트워크 서비스: \(b.service)") }
        }
    }
}

private struct SystemErrorAlert: ViewModifier {
    let model: AppModel
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content.alert("오류", isPresented: Binding(get: { appearsActive && model.systemError != nil },
                                                 set: { if !$0 { model.systemError = nil } })) {
            Button("확인", role: .cancel) { model.systemError = nil }
        } message: {
            Text(model.systemError ?? "")
        }
    }
}
