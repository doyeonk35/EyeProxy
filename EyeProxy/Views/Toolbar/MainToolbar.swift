import EyeProxyKit
import SwiftUI

struct MainToolbar: ToolbarContent {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some ToolbarContent {
        @Bindable var settings = model.settings
        ToolbarItemGroup(placement: .navigation) {
            Toggle(isOn: $settings.isRecording) {
                // Proxyman처럼 기록 중 ▶, 멈춤 ⏸ (녹화 심볼은 작게 보면 구분이 어렵다).
                Label("기록", systemImage: settings.isRecording ? "play.fill" : "pause.fill")
            }
            .help(settings.isRecording ? "기록 중 — 눌러서 일시정지 (⌘R)" : "일시정지됨 — 눌러서 기록 (⌘R)")
            Button("지우기", systemImage: "trash") { model.clear() }
                .help("목록 지우기 (⌘K)")
            Button("Compose", systemImage: "square.and.pencil") { openWindow(id: "compose") }
                .help("Compose Request (⌥⌘C)")
        }
        ToolbarItem(placement: .status) {
            HStack(spacing: 8) {
                status
                if model.settings.toolSwitches.noCaching {
                    Text("No Caching").modifier(Capsuled(color: .orange, selected: false))
                }
                PendingBreakpointsButton(count: model.breakpoints.pending.count)
                if !model.rules.loadWarnings.isEmpty {
                    Button("⚠︎ 규칙 경고 \(model.rules.loadWarnings.count)건") { model.showRuleWarnings = true }
                        .buttonStyle(.link)
                        .foregroundStyle(.red)
                        .help("규칙 파일을 읽거나 저장하지 못했습니다 — 눌러서 보기")
                }
            }
                .font(.caption)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
        // 보기 스위치 묶음: SSL 자물쇠 + 숨긴 요청 보기.
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: Binding(get: { settings.sslEnabled }, set: { model.setSSLEnabled($0) })) {
                Label("SSL 프록싱", systemImage: settings.sslEnabled ? "lock.fill" : "lock.open")
            }
            .help("SSL 프록싱 켜기/끄기")
            @Bindable var model = model
            Toggle(isOn: $model.filter.includeHidden) {
                Label("숨긴 요청 보기", systemImage: model.filter.includeHidden ? "eye" : "eye.slash")
            }
            .toggleStyle(.button)
        }
        ToolbarItemGroup(placement: .primaryAction) {
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
