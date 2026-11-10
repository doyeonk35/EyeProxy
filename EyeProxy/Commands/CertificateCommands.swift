import EyeProxyKit
import SwiftUI

/// Certificate 메뉴(스펙 §4.1). 섹션 항목은 섹션을 고른 뒤 Certificate 창을 연다(이미 열려 있으면 앞으로 가져온다).
struct CertificateCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Certificate") { CertificateMenu(model: model) }
    }
}

private struct CertificateMenu: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Install Certificate on this Mac…") { model.installCAOnMacWithConfirmation() }
            .help("Prog CA를 이 Mac 로그인 키체인에 설치·신뢰")
        Divider()
        Menu("Install Certificate on iOS") {
            Button("Physical Devices…") { open(.iosDevices) }
                .help("iPhone·iPad 프로필과 CA 설치 안내")
            Button("Simulators…") { open(.simulators) }
                .help("부팅된 iOS 시뮬레이터에 CA 설치")
            Button("watchOS or tvOS…") { open(.tvWatch) }
                .help("Apple TV·Watch 프로필과 CA 설치 안내")
        }
        .help("iOS 기기·시뮬레이터에 CA 설치")
        Menu("Install Certificate on Android") {
            Button("Physical Devices…") { model.androidTab = .device; open(.android) }
                .help("Android 실기기 프록시·CA 설치 안내")
            Button("Emulators…") { model.androidTab = .emulator; open(.android) }
                .help("Android 에뮬레이터 프록시·CA 설치 안내")
        }
        .help("Android 기기·에뮬레이터에 CA 설치")
        Divider()
        Menu("Install Certificate on Developments") {
            ForEach(DevPlatform.allCases.filter { $0 != .firefox }) { platform in
                Button(platform.title + "…") { openDevelopments(platform) }
                    .help("\(platform.title)에서 Prog CA를 믿게 하는 설정 안내")
            }
        }
        .help("개발 도구가 Prog CA를 믿게 하는 설정 안내")
        Button("Install Certificate on Firefox Browsers…") { openDevelopments(.firefox) }
            .help("Firefox가 Prog CA를 믿게 하는 설정 안내")
        Divider()
        Menu("Export") {
            Button("Root Certificate as PEM…") { model.exportCertificate(.pem) }
                .help("루트 CA를 PEM 파일로 저장")
            Button("Root Certificate as DER…") { model.exportCertificate(.der) }
                .help("루트 CA를 DER 파일로 저장")
            Button("Root Certificate as P12…") { model.exportCertificate(.p12) }
                .help("루트 CA와 개인키를 P12 파일로 저장")
            Button("Private Key…") { model.exportCertificate(.privateKey) }
                .help("CA 개인키를 PEM 파일로 저장(유출 주의)")
        }
        .help("루트 CA나 개인키를 파일로 저장")
        Divider()
        Button("Reset all Prog Certificates…") { Task { await model.resetCertificatesWithConfirmation() } }
            .help("새 루트 CA 만들기 — 설치한 CA는 다시 설치해야 함")
        Divider()
        Button("Certificate & Devices Window…") { openWindow(id: "devices") }
            .keyboardShortcut("d")
            .help("인증서 설치·연결된 기기 창 열기 (⌘D)")
    }

    private func open(_ section: CertificateSection) {
        model.certificateSection = section
        openWindow(id: "devices")
    }

    private func openDevelopments(_ platform: DevPlatform) {
        model.developmentPlatform = platform
        open(.developments)
    }
}
