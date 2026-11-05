import EyeProxyKit
import SwiftUI

/// 기기 온보딩: 이 Mac · 시뮬레이터 · 실기기 프로필 · 연결된 기기 · 연결 로그.
struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @State private var installedSimulators: Set<String> = []
    @State private var busy = false

    var body: some View {
        Form {
            macSection
            simulatorSection
            Section("실기기 프로필 만들기") {
                ProfileFormView()
                checklist
            }
            ConnectedDevicesSection()
            ConnectionLogSection()
        }
        .formStyle(.grouped)
        .onAppear { model.devicesWindowOpen = true }
        .onDisappear { model.devicesWindowOpen = false }
        .systemErrorAlert(model, presenting: true)
        .task {
            await model.refreshMacCAInstalled()
            await model.refreshEffectiveProxyWarning()
            await model.refreshSimulators()
        }
    }

    /// VPN 복사본이 남아 있으면 켜진 것으로 보여 "끄기"로 정리할 수 있게 한다.
    private var captureShownOn: Bool { model.macCaptureEnabled || model.effectiveProxyLeftover }

    private var serverRunning: Bool { if case .running = model.serverState { true } else { false } }

    private var macSection: some View {
        Section("이 Mac") {
            Toggle(isOn: Binding(get: { captureShownOn }, set: { on in Task { await model.setMacCapture(on) } })) {
                Text("이 Mac 캡처")
                Text("시스템 HTTP·HTTPS 프록시를 127.0.0.1:\(String(model.runningPort ?? model.settings.port))로 설정합니다. 끄거나 종료하면 되돌립니다.")
            }
            // 서버가 안 떠 있을 때 켜면 Mac 인터넷이 끊긴다. 끄기는 언제나 허용.
            .disabled(model.macCaptureBusy || (!captureShownOn && !serverRunning))
            if let error = model.systemError {
                LabeledContent {
                    Button("지우기") { model.systemError = nil }
                } label: {
                    Label("마지막 오류: \(error)", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
            if model.systemProxyBackupExists {
                Label("시스템 프록시가 EyeProxy로 설정되어 있음", systemImage: "network.badge.shield.half.filled")
                    .foregroundStyle(model.macCaptureEnabled ? Color.secondary : Color.orange)
            }
            if model.vpnPrimaryDetected {
                Text("VPN 상태에서는 켜고 끌 때 관리자 인증이 필요합니다").font(.caption).foregroundStyle(.secondary)
            }
            if model.effectiveProxyLeftover {
                Label("VPN 서비스에 EyeProxy 프록시가 남아 있습니다 — 캡처를 끄거나 VPN을 재연결하세요", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            LabeledContent {
                Button("Mac에 CA 설치") { run { try await model.installCAOnMac() } }
                    .disabled(model.macCAInstalled || busy)
            } label: {
                Text("CA 인증서")
                if model.macCAInstalled {
                    Label("로그인 키체인에 설치됨", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    Text("설치되지 않음")
                }
            }
            if let error = model.caSaveError {
                Label("CA를 디스크에 저장하지 못해 실행할 때마다 새 CA가 만들어집니다: \(error)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var simulatorSection: some View {
        Section {
            if model.bootedSimulators.isEmpty {
                Text("부팅된 시뮬레이터가 없습니다").foregroundStyle(.secondary)
            }
            ForEach(model.bootedSimulators) { sim in
                LabeledContent {
                    if installedSimulators.contains(sim.udid) {
                        Label("설치됨", systemImage: "checkmark").foregroundStyle(.green)
                    } else {
                        Button("CA 설치") {
                            run {
                                try await model.installCA(toSimulator: sim.udid)
                                installedSimulators.insert(sim.udid)
                            }
                        }
                        .disabled(busy)
                    }
                } label: {
                    Text(sim.name)
                    Text(sim.runtime)
                }
            }
        } header: {
            HStack {
                Text("시뮬레이터")
                Spacer()
                Button("새로고침", systemImage: "arrow.clockwise") { Task { await model.refreshSimulators() } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("새로고침")
            }
        } footer: {
            Text("설치 후 앱을 다시 실행하세요")
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apple TV").font(.headline)
            Text("1. Apple Configurator에서 Apple TV를 페어링하고 저장한 프로필을 TV로 드래그합니다.")
            Text("2. TV의 설정 > 일반 > 프로필 > 프로필 추가에 http://eyeproxy/ssl 을 입력해 CA 프로필을 설치합니다.")
            Text("3. 설정 > 일반 > 정보 > 인증서 신뢰 설정에서 EyeProxy CA를 신뢰로 켭니다.")
            Text("iPhone·iPad").font(.headline).padding(.top, 4)
            Text("1. 프로필을 AirDrop·메일로 보내 설치하거나, Wi-Fi 설정에서 수동 프록시(Mac IP·포트)를 입력합니다.")
            Text("2. Safari로 http://eyeproxy/ssl 을 열어 CA 프로필을 설치하고 인증서 신뢰 설정에서 신뢰합니다.")
        }
        .font(.callout)
        .textSelection(.enabled)
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await action() } catch { model.systemError = String(localized: "CA를 설치하지 못했습니다: \(AppModel.describe(error))") }
        }
    }
}
