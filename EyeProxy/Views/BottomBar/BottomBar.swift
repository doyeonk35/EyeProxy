import Darwin
import EyeProxyKit
import SwiftUI

/// 창 맨 아래 한 줄(스펙 §6): 왼쪽 Clear·Filter·Auto Select, 가운데 선택/보이는 행 수, 오른쪽 메모리·속도와 켜진 도구 배지.
/// 목록 수는 캐시된 `visibleFlows`(묶어서 갱신)만 읽는다 — 세션 흐름을 body에서 읽으면 요청마다 다시 그려진다.
struct BottomBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showNoCaching = false

    var body: some View {
        @Bindable var settings = model.settings
        HStack(spacing: 4) {
            barButton("Clear", systemImage: "trash", on: false, help: "세션의 모든 요청 지우기 (⌘K)") { model.clear() }
            barButton("Filter", systemImage: "line.3.horizontal.decrease", on: model.isFilterBarVisible || model.hasActiveFilterRules,
                      help: "필터 막대 보이기·숨기기 (⌘F)") {
                if model.isFilterBarVisible { model.isFilterBarVisible = false } else { model.showFilterBar() }
            }
            barButton("Auto Select", systemImage: "arrow.down.to.line", on: settings.autoSelectLatest,
                      help: "새 요청이 오면 자동 선택 — 다른 행을 고르면 꺼짐") { settings.autoSelectLatest.toggle() }
            Text(verbatim: "\(model.visibleSelectedFlowIDs.count)/\(model.visibleFlows.count) rows selected")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
            ResourceUsage()
            ForEach(ActiveToolBadge.active(switches: settings.toolSwitches,
                                           proxyOverridden: model.macCaptureEnabled || model.effectiveProxyLeftover,
                                           sslEnabled: settings.sslEnabled), id: \.self) { badge in
                Button { open(badge) } label: {
                    Text(verbatim: badge.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .foregroundStyle(Self.color(badge))
                        .background(Self.color(badge).opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(Self.help(badge))
                .popover(isPresented: badge == .noCaching ? $showNoCaching : .constant(false), arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("No Caching", isOn: $settings.toolSwitches.noCaching)
                        Text("캐시를 끄고 늘 서버에서 새로 받기 — 끄면 배지가 사라집니다 (⌥⌘N)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(.bar)
    }

    private func open(_ badge: ActiveToolBadge) {
        switch badge {
        case .noCaching: showNoCaching = true
        case .sslProxyingOff:
            model.settingsTab = .ssl
            openSettings()
        case .proxyOverridden:
            model.certificateSection = .mac
            openWindow(id: "devices")
        default:
            if let id = badge.windowID { openWindow(id: id) }
        }
    }

    private func barButton(_ title: String, systemImage: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .fontWeight(on ? .semibold : .regular)
                .background(on ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .help(help)
    }

    private static func color(_ badge: ActiveToolBadge) -> Color {
        switch badge {
        case .breakpoint, .blockList, .sslProxyingOff: .red
        case .mapLocal, .allowList: .green
        case .mapRemote, .networkConditions: .blue
        case .noCaching: .secondary
        case .proxyOverridden: .orange
        }
    }

    private static func help(_ badge: ActiveToolBadge) -> String {
        switch badge {
        case .breakpoint: "Breakpoint 켜짐 — 규칙 창 열기"
        case .mapLocal: "Map Local 켜짐 — 규칙 창 열기"
        case .mapRemote: "Map Remote 켜짐 — 규칙 창 열기"
        case .blockList: "Block List 켜짐 — 규칙 창 열기"
        case .allowList: "Allow List 켜짐 — 규칙 창 열기"
        case .networkConditions: "Network Conditions 켜짐 — 규칙 창 열기"
        case .noCaching: "No Caching 켜짐 — 눌러서 끄기"
        case .proxyOverridden: "macOS 시스템 프록시가 Prog를 가리킴 — Certificate 창의 이 Mac 열기"
        case .sslProxyingOff: "SSL Proxying 꺼짐 — HTTPS를 복호화하지 않음, 설정 열기"
        }
    }
}

/// 앱 메모리(상주 크기)와 최근 1초 속도. 자기 1초 타이머로만 갱신한다(흐름 이벤트마다가 아니라).
/// 설정으로 숨길 수 있게 따로 둔 뷰(스펙 §11 Show Resource Usage in Bottom Bar).
struct ResourceUsage: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""

    var body: some View {
        Text(verbatim: text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .padding(.trailing, 6)
            .help("앱 메모리 · 최근 1초 업로드↑·다운로드↓(요청·응답 본문 크기 합)")
            .task {
                while !Task.isCancelled {
                    // task 안의 읽기는 관찰되지 않는다 → 세션이 바뀌어도 다시 그리지 않는다.
                    let rate = Throughput.lastSecond(model.session.flows, now: .now)
                    text = Throughput.format(memory: Self.residentBytes(), up: rate.up, down: rate.down)
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }

    private static func residentBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
}
