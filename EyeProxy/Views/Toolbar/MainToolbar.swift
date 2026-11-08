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
        ToolbarItem(placement: .status) {
            HStack(spacing: 8) {
                status
                if model.settings.toolSwitches.noCaching {
                    Text("No Caching").modifier(Capsuled(color: .orange, selected: false))
                }
                PendingBreakpointsButton(count: model.breakpoints.pending.count)
            }
                .font(.caption)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
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
            // 검색 칸(.searchable) 바로 앞에 놓인다.
            @Bindable var model = model
            Toggle("숨김 포함", isOn: $model.filter.includeHidden)
                .toggleStyle(.checkbox)
                .help("Block List로 숨긴 요청도 목록에 보이기")
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
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill").labelStyle(.titleAndIcon).foregroundStyle(.red)
                Button("다시 시도") { Task { await model.startServer() } }
            }
        }
    }
}

/// 멈춘 Breakpoint가 있으면 "⏸ N건 대기". 누르면 Breakpoint 창을 연다.
private struct PendingBreakpointsButton: View {
    let count: Int
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if count > 0 {
            Button("⏸ \(count)건 대기") { openWindow(id: "breakpoints") }
                .buttonStyle(.link)
                .foregroundStyle(.orange)
                .help("Breakpoint 창 열기")
        }
    }
}
