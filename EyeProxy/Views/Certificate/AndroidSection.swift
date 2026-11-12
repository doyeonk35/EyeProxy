import AppKit
import EyeProxyKit
import SwiftUI

/// Android 섹션의 탭. Certificate 메뉴가 고른 뒤 창을 연다.
enum AndroidTab: String, CaseIterable { case device, emulator, tv }

/// Android: 실기기 / 에뮬레이터 / Android TV·Google TV 탭별 프록시·CA 안내와 adb 도우미, 모든 탭 공통 "디버그 빌드에 CA 넣기".
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
                Text("Android TV·Google TV").tag(AndroidTab.tv)
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
        debugBuildSection
    }

    private var deviceSection: some View {
        Section("실기기") {
            proxyRow(host: macIP)
            steps {
                Text("1. Wi-Fi 설정 ▸ 프록시 수동 ▸ 위 Mac IP·포트를 입력합니다.")
                Text("2. Chrome으로 http://prog/ssl 을 열어 Prog-CA.crt를 내려받습니다.")
                Text("3. 설정 ▸ 보안 ▸ 암호화 및 사용자 인증 정보 ▸ 인증서 설치 ▸ CA 인증서 → 내려받은 파일을 선택합니다.")
                Text("Android 11+는 내려받은 파일을 눌러서는 설치되지 않습니다. 설정 ▸ 보안 ▸ 암호화 및 사용자 인증 정보 ▸ 인증서 설치에서만 됩니다.")
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
                Text("아래 디버그 빌드 방법도 됩니다.")
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
        Section("Android TV·Google TV") {
            proxyRow(host: macIP)
            steps {
                Text("1. 개발자 옵션 ▸ 네트워크(무선) 디버깅을 켜고 adb connect <TV IP>:<포트>로 연결합니다. 네트워크 디버깅은 :5555, 무선 디버깅은 화면에 보이는 포트입니다.")
                Text("2. CA는 TV에 설치하지 않습니다 — Android 11+는 설정 화면에서만 설치되고 Google TV에는 그 화면도 파일 선택기도 없습니다. 아래 '디버그 빌드에 CA 넣기'를 따르세요.")
                Text("3. adb로 TV 프록시를 위 Mac IP·포트로 설정합니다.")
                Text("4. 디버그 빌드를 실행해 Prog에 요청이 보이는지 확인합니다.")
                Text("5. 끝나면 adb로 프록시를 해제합니다.")
            }
            TextField("TV IP", text: $tvIP, prompt: Text(verbatim: "192.0.2.10"))
                .help("TV IP 또는 IP:포트. 포트를 빼면 5555(네트워크 디버깅)")
            if adb != nil {
                adbButton("adb connect") { await model.runADB(AndroidSetup.connectArguments(tvIP)) }
                    .disabled(tvIP.isEmpty || running)
                    .help("입력한 TV 주소로 adb 연결")
                adbButton("adb로 프록시 설정") { await model.adbSetProxy(host: macIP) }
                    .help("TV 프록시를 Prog(Mac IP:포트)로 설정")
                adbButton("adb로 프록시 해제") { await model.runADB(AndroidSetup.clearProxyArguments) }
                    .help("기기의 프록시 설정 지우기")
                clearProxyWarning
                adbResult
            } else {
                Text("adb를 찾지 못했습니다. 아래 명령을 터미널에서 실행하세요.").font(.callout)
                snippet(AndroidSetup.tvCommandLines(adb: "adb", tvIP: tvIP.isEmpty ? "<TV IP>" : tvIP,
                                                    host: macIP, port: port))
                snippet(AndroidSetup.clearProxyCommand(adb: "adb"))
                clearProxyWarning
            }
        }
    }

    private var clearProxyWarning: some View {
        Text("프록시를 켜 둔 채 Prog를 끄면 TV의 네트워크가 끊기고, 켜 둔 동안 다른 앱의 HTTPS가 실패할 수 있습니다. 끝나면 꼭 해제하세요.")
            .font(.callout)
            .foregroundStyle(.orange)
    }

    /// 모든 탭 공통: 앱 디버그 빌드에 Prog CA를 번들해 기기 CA 설치 없이 복호화한다.
    private var debugBuildSection: some View {
        Section("디버그 빌드에 CA 넣기") {
            steps {
                Text("Android 7 이상 앱은 사용자 CA를 믿지 않습니다. 앱의 network_security_config가 허용해야 합니다.")
                Text("스토어(release) 빌드는 볼 수 없습니다. 디버그 빌드가 필요합니다.")
                Text("스토어 앱이 깔려 있으면 서명이 달라 디버그 APK를 덮어 깔 수 없습니다(INSTALL_FAILED_UPDATE_INCOMPATIBLE). 스토어 앱을 지우면 로그인 데이터도 지워집니다.")
            }
            LabeledContent("Prog CA SHA-256") {
                HStack {
                    Text(verbatim: model.certificateAuthority.sha256Fingerprint)
                        .font(.caption.monospaced())
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                    Button("복사") { copy(model.certificateAuthority.sha256Fingerprint) }
                        .help("Prog CA SHA-256 지문 복사")
                }
            }
            Button("CA를 proxy_ca.crt로 저장…") { model.exportAndroidRawCA() }
                .help("Prog CA를 앱 프로젝트에 넣을 proxy_ca.crt(PEM)로 저장")
            Text("또는 앱 프로젝트 폴더에서 실행:").font(.callout)
            snippet(AndroidSetup.copyCACommand(caPEMPath: AppModel.caDirectory.appending(path: "ca.pem").path))
            snippet(AndroidSetup.bundledNetworkSecurityConfigXML)
            snippet(AndroidSetup.debugManifestXML)
            Text("확인: 출력의 지문이 위 SHA-256과 같아야 합니다.").font(.callout)
            snippet(AndroidSetup.fingerprintCommand)
            steps {
                Text("CA는 Mac마다 다르므로 커밋하지 마세요(.git/info/exclude에 추가).")
                Text("Prog CA를 초기화(Reset)하면 다시 복사하고 다시 빌드하세요.")
                Text("logcat에 `Trust anchor for certification path not found`가 보이면 앱이 Prog CA를 믿지 않는 것입니다(스플래시에서 멈출 수 있음).")
            }
            snippet(AndroidSetup.trustAnchorLogcatCommand)
        }
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

    /// 고정폭·선택 가능한 명령/XML과 복사 버튼.
    private func snippet(_ text: String) -> some View {
        HStack(alignment: .top) {
            Text(verbatim: text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("복사") { copy(text) }
                .help("이 내용 복사")
        }
    }

    /// 에뮬레이터 탭에서 adb가 없을 때: 저장한 CA 폴더에서 붙여 넣을 명령.
    private func commandText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("adb를 찾지 못했습니다. CA 저장(.crt)…로 저장한 폴더에서 아래 명령을 실행하세요.").font(.callout)
            snippet(text)
            Button("CA 저장(.crt)…") { model.exportCACrt() }
                .help("Prog CA를 Prog-CA.crt 파일로 저장")
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
