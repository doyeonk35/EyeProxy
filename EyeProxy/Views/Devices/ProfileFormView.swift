import EyeProxyKit
import SwiftUI

/// Wi-Fi + 수동 프록시 .mobileconfig. 비밀번호는 @State에만 있고 저장하지 않는다(스펙 §7.2).
struct ProfileFormView: View {
    @Environment(AppModel.self) private var model
    @State private var ssid = ""
    @State private var security = WiFiSecurity.wpa2
    @State private var password = ""
    @State private var host = ""
    @State private var confirmingPlaintext = false

    var body: some View {
        let addresses = model.lanAddresses
        TextField("SSID", text: $ssid)
        Picker("보안", selection: $security) {
            ForEach(WiFiSecurity.allCases, id: \.self) { s in
                if s == .none { Text("없음").tag(s) } else { Text(verbatim: s.rawValue).tag(s) }
            }
        }
        if security != .none {
            SecureField("비밀번호", text: $password)
        }
        if addresses.isEmpty {
            LabeledContent("Mac IP") { Text("LAN 주소 없음").foregroundStyle(.secondary) }
        } else {
            Picker("Mac IP", selection: $host) {
                ForEach(addresses, id: \.self) { Text(verbatim: $0).tag($0) }
            }
        }
        LabeledContent("포트") { Text(verbatim: String(model.runningPort ?? model.settings.port)) }
        HStack {
            Spacer()
            Button("프로필 저장…") {
                if needsPassword { confirmingPlaintext = true } else { save() }
            }
            .disabled(ssid.isEmpty || !addresses.contains(host))
        }
        .onAppear { if !addresses.contains(host) { host = addresses.first ?? "" } }
        .alert("이 파일에 Wi-Fi 비밀번호가 평문으로 들어 있습니다", isPresented: $confirmingPlaintext) {
            Button("계속") { save() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("tvOS는 Wi-Fi 프로필로만 프록시를 지정할 수 있어 비밀번호가 암호화되지 않은 채 저장됩니다. 신뢰할 수 있는 곳에만 보관·전달하세요.")
        }
    }

    private var needsPassword: Bool { security != .none && !password.isEmpty }

    private func save() {
        Task {
            if await model.saveWiFiProfile(ssid: ssid, security: security, password: needsPassword ? password : nil, proxyHost: host) {
                password = ""   // 저장 후 메모리에도 남기지 않는다
            }
        }
    }
}
