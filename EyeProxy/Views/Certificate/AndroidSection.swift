import AppKit
import EyeProxyKit
import SwiftUI

/// Android 섹션의 탭. Certificate 메뉴가 고른 뒤 창을 연다.
enum AndroidTab: String, CaseIterable { case device, emulator, tv }

/// Android: 실기기 / 에뮬레이터 / Android TV 탭별 프록시·CA 설치 안내와 adb 도우미.
struct AndroidSection: View {
    @Environment(AppModel.self) private var model
    @State private var tvIP = ""
    @State private var adbOutput = ""
    @State private var running = false
    @State private var adb = AndroidSetup.locateADB()

    private var macIP: String { model.lanAddresses.first ?? "127.0.0.1" }
    private var port: Int { model.runningPort ?? model.settings.port }
    /// adb가 없을 때 복사용 명령에 쓰는 CA 파일 이름(`CA 저장(.crt)…`로 저장한 폴더에서 실행).
    private let savedCRT = URL(string: "Prog-CA.crt")!

    var body: some View {
        @Bindable var model = model
        Section {
            Picker("기기", selection: $model.androidTab) {
                Text("실기기").tag(AndroidTab.device)
                Text("에뮬레이터").tag(AndroidTab.emulator)
                Text("Android TV").tag(AndroidTab.tv)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Android 기기 종류별 안내 전환")
        }
        switch model.androidTab {
        case .device: deviceSection
        case .emulator: emulatorSection
        case .tv: tvSection
        }
        caveatSection
    }

    private var deviceSection: some View {
        Section("실기기") {
            proxyRow(host: macIP)
            steps {
                Text("1. Wi-Fi 설정 ▸ 프록시 수동 ▸ 위 Mac IP·포트를 입력합니다.")
                Text("2. Chrome으로 http://prog/ssl 을 열어 Prog-CA.crt를 내려받습니다.")
                Text("3. 설정 ▸ 보안 ▸ 암호화 및 사용자 인증 정보 ▸ 인증서 설치 ▸ CA 인증서 → 내려받은 파일을 선택합니다.")
            }
            Button("CA 저장(.crt)…") { model.exportCACrt() }
                .help("Prog CA를 Prog-CA.crt 파일로 저장")
        }
    }

    private var emulatorSection: some View {
        Section("에뮬레이터") {
            proxyRow(host: "10.0.2.2")
            steps {
                Text("에뮬레이터 안에서는 Mac IP 대신 10.0.2.2가 Mac을 가리킵니다.")
                Text("1. adb로 프록시를 설정하고 CA를 기기 Download 폴더로 복사합니다.")
                Text("2. 설정 ▸ 보안 ▸ 암호화 및 사용자 인증 정보 ▸ 인증서 설치 ▸ CA 인증서 → Download/Prog-CA.crt를 선택합니다.")
            }
            if adb != nil {
                adbButton("adb로 프록시 설정 + CA 복사") { await model.adbSetProxyAndPushCA(host: "10.0.2.2") }
                    .help("에뮬레이터 프록시를 Prog로 설정하고 CA를 Download로 복사")
                adbButton("adb로 프록시 해제") { await model.runADB(AndroidSetup.clearProxyArguments) }
                    .help("기기의 프록시 설정 지우기")
                adbResult
            } else {
                commandText(AndroidSetup.commandLines(adb: "adb", host: "10.0.2.2", port: port, crt: savedCRT))
            }
        }
    }

    private var tvSection: some View {
        Section("Android TV") {
            proxyRow(host: macIP)
            steps {
                Text("1. TV 설정 ▸ 기기 환경설정 ▸ 정보 ▸ 빌드를 7번 눌러 개발자 옵션을 켜고, 개발자 옵션 ▸ 네트워크 디버깅을 켭니다.")
                Text("2. adb connect <TV IP>:5555 로 TV에 연결합니다.")
                Text("3. 프록시 설정·CA 복사는 에뮬레이터와 같은 명령입니다(호스트는 Mac LAN IP).")
                Text("4. 설치 인텐트로 인증서 설치 화면을 띄워 리모컨으로 진행합니다. 화면이 안 뜨면 설정 ▸ 보안 ▸ 저장소에서 설치합니다.")
            }
            TextField("TV IP", text: $tvIP, prompt: Text(verbatim: "192.168.0.10"))
            if adb != nil {
                adbButton("adb connect") { await model.runADB(AndroidSetup.connectArguments(tvIP)) }
                    .disabled(tvIP.isEmpty || running)
                    .help("입력한 TV IP로 adb 연결")
                adbButton("adb로 프록시 설정 + CA 복사") { await model.adbSetProxyAndPushCA(host: macIP) }
                    .help("TV 프록시를 Prog로 설정하고 CA를 Download로 복사")
                adbButton("adb로 프록시 해제") { await model.runADB(AndroidSetup.clearProxyArguments) }
                    .help("기기의 프록시 설정 지우기")
                adbButton("인증서 설치 화면 열기") { await model.runADB(AndroidSetup.installIntentArguments) }
                    .help("기기에 인증서 설치 화면 띄우기")
                adbResult
            } else {
                commandText(AndroidSetup.tvCommandLines(adb: "adb", tvIP: tvIP.isEmpty ? "<TV IP>" : tvIP,
                                                        host: macIP, port: port, crt: savedCRT))
            }
        }
    }

    private var caveatSection: some View {
        Section("주의") {
            if model.androidTab == .tv {
                Text("앱이 사용자 CA를 신뢰하려면 디버그 빌드에 network_security_config가 필요합니다. Play가 없는 Android TV 에뮬레이터는 adb root; adb remount 뒤 /system/etc/security/cacerts/에 넣으면 시스템 CA로 모든 앱이 복호화됩니다(해시 파일명은 openssl x509 -subject_hash_old).")
            } else {
                Text("Android 7 이상 앱은 사용자 CA를 기본으로 신뢰하지 않습니다. 디버그 빌드에 network_security_config로 사용자 CA를 허용해야 합니다.")
            }
            Text(verbatim: AndroidSetup.networkSecurityConfigXML)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Button("XML 복사") { copy(AndroidSetup.networkSecurityConfigXML) }
                .help("network_security_config XML 복사")
        }
        .font(.callout)
    }

    private func proxyRow(host: String) -> some View {
        LabeledContent("프록시") {
            HStack {
                Text(verbatim: "\(host):\(String(port))").monospaced().textSelection(.enabled)
                Button("복사") { copy("\(host):\(String(port))") }
                    .help("프록시 주소(호스트:포트) 복사")
            }
        }
    }

    private func steps(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .font(.callout)
            .textSelection(.enabled)
    }

    /// adb가 없을 때: 저장한 CA 폴더에서 붙여 넣을 명령.
    private func commandText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("adb를 찾지 못했습니다. CA 저장(.crt)…로 저장한 폴더에서 아래 명령을 실행하세요.").font(.callout)
            Text(verbatim: text).font(.caption.monospaced()).textSelection(.enabled)
            HStack {
                Button("명령 복사") { copy(text) }
                    .help("위 adb 명령 복사")
                Button("CA 저장(.crt)…") { model.exportCACrt() }
                    .help("Prog CA를 Prog-CA.crt 파일로 저장")
            }
        }
    }

    private func adbButton(_ title: LocalizedStringKey, _ work: @escaping () async -> String) -> some View {
        Button(title) {
            running = true
            Task {
                adbOutput = await work()
                running = false
            }
        }
        .disabled(running)
    }

    @ViewBuilder private var adbResult: some View {
        if running {
            ProgressView().controlSize(.small)
        } else if !adbOutput.isEmpty {
            Text(verbatim: adbOutput).font(.caption.monospaced()).textSelection(.enabled)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
