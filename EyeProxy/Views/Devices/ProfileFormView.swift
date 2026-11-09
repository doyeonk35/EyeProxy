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
        Picker("Mac IP", selection: hostBinding) {
            if addresses.isEmpty { Text("(LAN 주소 없음)").tag("") }
            ForEach(addresses, id: \.self) { Text(verbatim: $0).tag($0) }
        }
        .disabled(addresses.isEmpty)
        LabeledContent("포트") { Text(verbatim: String(model.runningPort ?? model.settings.port)) }
        HStack {
            Spacer()
            Button("프로필 저장…") {
                if needsPassword { confirmingPlaintext = true } else { save() }
            }
            .disabled(ssid.isEmpty || effectiveHost.isEmpty)
            .help("Wi-Fi·프록시 설정 프로필(.mobileconfig) 저장")
        }
        .alert("이 파일에 Wi-Fi 비밀번호가 평문으로 들어 있습니다", isPresented: $confirmingPlaintext) {
            Button("계속") { save() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("tvOS는 Wi-Fi 프로필로만 프록시를 지정할 수 있어 비밀번호가 암호화되지 않은 채 저장됩니다. 신뢰할 수 있는 곳에만 보관·전달하세요.")
        }
    }

    /// 선택값이 목록에 없으면(초기·주소 변경) 첫 주소, 목록이 비면 "". onAppear 없이 항상 유효한 tag를 유지한다.
    private var effectiveHost: String {
        let addresses = model.lanAddresses
        return addresses.contains(host) ? host : (addresses.first ?? "")
    }
    private var hostBinding: Binding<String> { Binding(get: { effectiveHost }, set: { host = $0 }) }

    private var needsPassword: Bool { security != .none && !password.isEmpty }

    private func save() {
        Task {
            if await model.saveWiFiProfile(ssid: ssid, security: security, password: needsPassword ? password : nil, proxyHost: effectiveHost) {
                password = ""   // 저장 후 메모리에도 남기지 않는다
            }
        }
    }
}
