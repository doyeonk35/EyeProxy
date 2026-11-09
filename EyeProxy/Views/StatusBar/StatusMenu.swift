import AppKit
import EyeProxyKit
import SwiftUI

/// 메뉴 막대 개구리 메뉴(Proxyman 순서). 툴바·Tools 메뉴와 같은 모델 값을 바인딩한다.
struct StatusMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = model.settings
        let port = model.runningPort.map(String.init)
        let ip = model.lanAddresses.first ?? "127.0.0.1"
        Button("Show Prog") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        .help("Prog 메인 창을 앞으로 가져오기")
        Divider()
        Toggle("Record Traffic", isOn: $settings.isRecording)
            .help("새 요청 기록 켜기/끄기")
        MacProxyOverrideToggle(title: "macOS Proxy Overridden", model: model)
        Divider()
        Menu(port.map { "Listen on \(ip):\($0)" } ?? "Listen on — (Stopped)") {
            if let port {
                Button("Copy") { copy("\(ip):\(port)") }
                    .help("프록시 주소(IP:포트) 복사")
                Divider()
                Button("Copy IP") { copy(ip) }
                    .help("프록시 IP 주소 복사")
                Button("Copy Port") { copy(port) }
                    .help("프록시 포트 번호 복사")
                Divider()
                Button("Copy Shell Command") {
                    copy("export https_proxy=http://\(ip):\(port) http_proxy=http://\(ip):\(port)")
                }
                .help("터미널용 https_proxy·http_proxy export 명령 복사")
            }
        }
        .disabled(port == nil)
        .help("프록시 주소 복사")
        Divider()
        Menu("Enable/Disable Tools") {
            Toggle("Breakpoint", isOn: $settings.toolSwitches.breakpoint).help("Breakpoint 규칙 전체 켜기/끄기")
            Divider()
            Toggle("Map Local", isOn: $settings.toolSwitches.mapLocal).help("Map Local 규칙 전체 켜기/끄기")
            Toggle("Map Remote", isOn: $settings.toolSwitches.mapRemote).help("Map Remote 규칙 전체 켜기/끄기")
            Divider()
            Toggle("Block List", isOn: $settings.toolSwitches.blockList).help("Block List 규칙 전체 켜기/끄기")
            Toggle("Allow List", isOn: $settings.toolSwitches.allowList).help("Allow List 규칙 전체 켜기/끄기")
            Divider()
            Toggle("Network Conditions", isOn: $settings.toolSwitches.networkConditions).help("Network Conditions 규칙 전체 켜기/끄기")
            Divider()
            Toggle("No Caching", isOn: $settings.toolSwitches.noCaching).help("캐시를 끄고 늘 서버에서 새로 받기")
            Divider()
            Toggle("SSL Proxying List", isOn: Binding(get: { settings.sslEnabled }, set: { model.setSSLEnabled($0) }))
                .help("HTTPS 복호화(SSL 프록싱) 켜기/끄기")
        }
        .help("규칙은 둔 채 도구별로 켜고 끄기")
        Divider()
        Button("Quit Prog") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .help("Prog 종료 — 바꾼 시스템 프록시는 되돌림 (⌘Q)")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
