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
        Divider()
        Menu("Install Certificate on iOS") {
            Button("Physical Devices…") { open(.iosDevices) }
            Button("Simulators…") { open(.simulators) }
            Button("watchOS or tvOS…") { open(.tvWatch) }
        }
        Menu("Install Certificate on Android") {
            Button("Physical Devices…") { model.androidTab = .device; open(.android) }
            Button("Emulators…") { model.androidTab = .emulator; open(.android) }
        }
        Divider()
        Menu("Install Certificate on Developments") {
            ForEach(DevPlatform.allCases.filter { $0 != .firefox }) { platform in
                Button(platform.title + "…") { openDevelopments(platform) }
            }
        }
        Button("Install Certificate on Firefox Browsers…") { openDevelopments(.firefox) }
        Divider()
        Menu("Export") {
            Button("Root Certificate as PEM…") { model.exportCertificate(.pem) }
            Button("Root Certificate as DER…") { model.exportCertificate(.der) }
            Button("Root Certificate as P12…") { model.exportCertificate(.p12) }
            Button("Private Key…") { model.exportCertificate(.privateKey) }
        }
        Divider()
        Button("Reset all Prog Certificates…") { Task { await model.resetCertificatesWithConfirmation() } }
        Divider()
        Button("Certificate & Devices Window…") { openWindow(id: "devices") }
            .keyboardShortcut("d")
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
