import EyeProxyKit
import SwiftUI

struct MainToolbar: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        @Bindable var settings = model.settings
        ToolbarItemGroup(placement: .navigation) {
            Toggle(isOn: $settings.isRecording) {
                Label("기록", systemImage: settings.isRecording ? "record.circle.fill" : "record.circle")
            }
            .help("기록 켜기/끄기 (⌘R)")
            Button("지우기", systemImage: "trash") { model.clear() }
                .help("목록 지우기 (⌘K)")
        }
        ToolbarItem(placement: .status) { status }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: Binding(get: { settings.sslEnabled }, set: { enabled in
                settings.sslEnabled = enabled
                Task { await model.applySettingsToServer() }
            })) {
                Label("SSL 프록싱", systemImage: settings.sslEnabled ? "lock.fill" : "lock.open")
            }
            .help("SSL 프록싱 켜기/끄기")
            Picker("레이아웃", selection: $settings.layout) {
                Label("위아래", systemImage: "rectangle.split.1x2").tag(FlowLayout.classic)
                Label("좌우", systemImage: "rectangle.split.2x1").tag(FlowLayout.sideBySide)
            }
            .pickerStyle(.segmented)
            .help("레이아웃 전환")
        }
    }

    @ViewBuilder private var status: some View {
        switch model.serverState {
        case .stopped:
            Text("중지됨").foregroundStyle(.secondary)
        case .running(let port):
            let ips = model.lanAddresses.joined(separator: ", ")
            Group {
                if ips.isEmpty { Text("실행 중 · 포트 \(String(port))") } else { Text("실행 중 · 포트 \(String(port)) · \(ips)") }
            }
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").labelStyle(.titleAndIcon).foregroundStyle(.red)
        }
    }
}
