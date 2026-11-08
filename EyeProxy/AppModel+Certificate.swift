import AppKit
import EyeProxyKit
import Foundation

enum CertificateExportFormat {
    case pem, der, p12, privateKey

    var defaultFileName: String {
        switch self {
        case .pem: "EyeProxy-CA.pem"
        case .der: "EyeProxy-CA.cer"
        case .p12: "EyeProxy-CA.p12"
        case .privateKey: "EyeProxy-CA-key.pem"
        }
    }
}

/// Certificate 창·메뉴의 확인 알림과 저장 패널. 결과는 `infoMessage`, 실패는 `systemError`.
extension AppModel {
    func installCAOnMacWithConfirmation() {
        guard confirm(String(localized: "이 Mac에 CA를 설치할까요?"),
                      String(localized: "로그인 키체인에 EyeProxy CA를 추가하고 SSL 신뢰를 켭니다. 관리자 인증이 필요합니다."),
                      button: String(localized: "설치")) else { return }
        Task {
            do {
                try await installCAOnMac()
                infoMessage = String(localized: "이 Mac에 CA를 설치했습니다.")
            } catch {
                systemError = String(localized: "CA를 설치하지 못했습니다: \(Self.describe(error))")
            }
        }
    }

    func exportCertificate(_ format: CertificateExportFormat) {
        var password = ""
        switch format {
        case .privateKey:
            guard confirm(String(localized: "개인키를 내보낼까요?"),
                          String(localized: "이 키로 누구나 EyeProxy CA를 신뢰하는 기기의 HTTPS를 가로챌 수 있습니다"),
                          button: String(localized: "내보내기"), destructive: true) else { return }
        case .p12:
            guard let entered = askP12Password() else { return }
            password = entered
        case .pem, .der: break
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = format.defaultFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ca = certificateAuthority
        Task {
            do {
                switch format {
                case .pem: try CertificateExporter.writePEM(ca, to: url)
                case .der: try CertificateExporter.writeDER(ca, to: url)
                case .privateKey: try CertificateExporter.writePrivateKey(ca, to: url)
                case .p12: try await CertificateExporter.writeP12(ca, to: url, password: password)
                }
            } catch {
                systemError = String(localized: "인증서를 내보내지 못했습니다: \(Self.describe(error))")
            }
        }
    }

    func resetCertificatesWithConfirmation() async {
        guard confirm(String(localized: "모든 EyeProxy 인증서를 초기화할까요?"),
                      String(localized: "새 루트 CA를 만듭니다. Mac·시뮬레이터·기기에 설치한 CA는 모두 다시 설치해야 합니다."),
                      button: String(localized: "초기화"), destructive: true) else { return }
        await resetCertificateAuthority()
    }

    private func confirm(_ message: String, _ info: String, button: String, destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: button).hasDestructiveAction = destructive
        alert.addButton(withTitle: String(localized: "취소"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 취소하면 nil. 빈 문자열은 비밀번호 없는 P12.
    private func askP12Password() -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "P12 비밀번호")
        alert.informativeText = String(localized: "비워 두면 비밀번호 없이 만듭니다.")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "계속"))
        alert.addButton(withTitle: String(localized: "취소"))
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
