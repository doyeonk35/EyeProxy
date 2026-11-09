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
                .help("루트 CA를 PEM 파일로 저장")
            Button("Root Certificate as DER…") { model.exportCertificate(.der) }
                .help("루트 CA를 DER 파일로 저장")
            Button("Root Certificate as P12…") { model.exportCertificate(.p12) }
                .help("루트 CA와 개인키를 P12 파일로 저장")
            Button("Private Key…") { model.exportCertificate(.privateKey) }
                .help("CA 개인키를 PEM 파일로 저장(유출 주의)")
        }
        Section {
            Button("Reset all Prog Certificates…", role: .destructive) {
                resetting = true
                Task {
                    await model.resetCertificatesWithConfirmation()
                    resetting = false
                }
            }
            .disabled(resetting)
            .help("새 루트 CA 만들기 — 설치한 CA는 다시 설치")
        } footer: {
            Text("새 루트 CA를 만듭니다. 이전 CA는 백업 폴더로 옮겨집니다.")
        }
    }
}
