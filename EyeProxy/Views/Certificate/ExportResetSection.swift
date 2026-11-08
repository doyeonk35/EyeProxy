import SwiftUI

/// 현재 CA 정보 · 내보내기 네 가지 · 초기화.
struct ExportResetSection: View {
    @Environment(AppModel.self) private var model
    @State private var resetting = false

    var body: some View {
        Section("현재 CA") {
            LabeledContent("이름") { Text(verbatim: model.certificateAuthority.commonName).textSelection(.enabled) }
            LabeledContent("SHA-256") {
                Text(verbatim: model.certificateAuthority.sha256Fingerprint)
                    .font(.caption.monospaced())
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
        Section("내보내기") {
            Button("Root Certificate as PEM…") { model.exportCertificate(.pem) }
            Button("Root Certificate as DER…") { model.exportCertificate(.der) }
            Button("Root Certificate as P12…") { model.exportCertificate(.p12) }
            Button("Private Key…") { model.exportCertificate(.privateKey) }
        }
        Section {
            Button("Reset all EyeProxy Certificates…", role: .destructive) {
                resetting = true
                Task {
                    await model.resetCertificatesWithConfirmation()
                    resetting = false
                }
            }
            .disabled(resetting)
        } footer: {
            Text("새 루트 CA를 만듭니다. 이전 CA는 백업 폴더로 옮겨집니다.")
        }
    }
}
