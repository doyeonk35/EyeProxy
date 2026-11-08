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
        Divider()
        Toggle("Record Traffic", isOn: $settings.isRecording)
        MacProxyOverrideToggle(title: "macOS Proxy Overridden", model: model)
        Divider()
        Menu(port.map { "Listen on \(ip):\($0)" } ?? "Listen on — (Stopped)") {
            if let port {
                Button("Copy") { copy("\(ip):\(port)") }
                Divider()
                Button("Copy IP") { copy(ip) }
                Button("Copy Port") { copy(port) }
                Divider()
                Button("Copy Shell Command") {
                    copy("export https_proxy=http://\(ip):\(port) http_proxy=http://\(ip):\(port)")
                }
            }
        }
        .disabled(port == nil)
        Divider()
        Menu("Enable/Disable Tools") {
            Toggle("Breakpoint", isOn: $settings.toolSwitches.breakpoint)
            Divider()
            Toggle("Map Local", isOn: $settings.toolSwitches.mapLocal)
            Toggle("Map Remote", isOn: $settings.toolSwitches.mapRemote)
            Divider()
            Toggle("Block List", isOn: $settings.toolSwitches.blockList)
            Toggle("Allow List", isOn: $settings.toolSwitches.allowList)
            Divider()
            Toggle("Network Conditions", isOn: $settings.toolSwitches.networkConditions)
            Divider()
            Toggle("No Caching", isOn: $settings.toolSwitches.noCaching)
            Divider()
            Toggle("SSL Proxying List", isOn: Binding(get: { settings.sslEnabled }, set: { model.setSSLEnabled($0) }))
        }
        Divider()
        Button("Quit Prog") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
