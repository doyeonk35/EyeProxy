import EyeProxyKit
import SwiftUI

/// 이 Mac: 캡처 토글 · 잔여 프록시 경고 · 로그인 키체인 CA 설치.
struct MacSection: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false

    /// VPN 복사본이 남아 있으면 켜진 것으로 보여 "끄기"로 정리할 수 있게 한다.
    private var captureShownOn: Bool { model.macCaptureEnabled || model.effectiveProxyLeftover }

    private var serverRunning: Bool { if case .running = model.serverState { true } else { false } }

    var body: some View {
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
                Label("시스템 프록시가 Prog로 설정되어 있음", systemImage: "network.badge.shield.half.filled")
                    .foregroundStyle(model.macCaptureEnabled ? Color.secondary : Color.orange)
            }
            if model.vpnPrimaryDetected {
                Text("VPN 상태에서는 켜고 끌 때 관리자 인증이 필요합니다").font(.caption).foregroundStyle(.secondary)
            }
            if model.effectiveProxyLeftover {
                Label("VPN 서비스에 Prog 프록시가 남아 있습니다 — 캡처를 끄거나 VPN을 재연결하세요", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            LabeledContent {
                Button("Mac에 CA 설치") { model.runCAInstall(busy: $busy) { try await model.installCAOnMac() } }
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
}

extension AppModel {
    /// Mac·시뮬레이터 CA 설치 버튼 공용: 실행 중 `busy`, 실패는 `systemError`.
    func runCAInstall(busy: Binding<Bool>, _ action: @escaping @MainActor () async throws -> Void) {
        busy.wrappedValue = true
        Task {
            defer { busy.wrappedValue = false }
            do { try await action() } catch { systemError = String(localized: "CA를 설치하지 못했습니다: \(Self.describe(error))") }
        }
    }
}
