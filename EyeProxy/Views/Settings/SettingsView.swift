import EyeProxyKit
import SwiftUI

/// Proxyman 설정 탭 순서(스펙 §11). Privacy·GitHub·Platform은 Prog에 기능이 없어 뺀다.
enum SettingsTab: Hashable { case general, appearance, tools, ssl, bypass, advanced }

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }.tag(SettingsTab.appearance)
            ToolSettings().tabItem { Label("Tools", systemImage: "hammer") }.tag(SettingsTab.tools)
            SSLSettings().tabItem { Label("SSL Proxying", systemImage: "lock") }.tag(SettingsTab.ssl)
            BypassSettings().tabItem { Label("Bypass", systemImage: "arrow.uturn.right") }.tag(SettingsTab.bypass)
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "gearshape.2") }.tag(SettingsTab.advanced)
        }
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var runningPort: Int? { model.runningPort }
    private var parsed: Int? { Int(draft).flatMap { (1024...65535).contains($0) ? $0 : nil } }

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Picker("Content Layout:", selection: $settings.layout) {
                    Text(verbatim: "Vertical").tag(FlowLayout.classic)
                    Text(verbatim: "Horizontal").tag(FlowLayout.sideBySide)
                }
                .pickerStyle(.segmented).fixedSize()
                .help("상세 패널을 목록 아래(Vertical) 또는 오른쪽(Horizontal)에 두기")
                Toggle("Show Prog Icon on Menu Bar", isOn: $settings.showStatusItem)
                    .help("메뉴 막대에 Prog 상태 아이콘 보이기")
                Picker("Truncation Style:", selection: $settings.truncationStyle) {
                    Text(verbatim: "Head").tag(TruncationStyle.head)
                    Text(verbatim: "Middle").tag(TruncationStyle.middle)
                    Text(verbatim: "Tail").tag(TruncationStyle.tail)
                }
                .fixedSize()
                .help("목록 URL·Client 열이 길 때 말줄임(…) 위치")
                Toggle("Restore Tabs at Launch", isOn: $settings.restoreTabsAtLaunch)
                    .help("다시 실행할 때 종료 전에 열려 있던 탭 다시 열기")
            }
            Section {
                TextField("Port Number:", text: $draft)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                    .help("프록시 포트(1024–65535) — 바꾸면 서버를 다시 시작해야 적용")
                if parsed == nil, !focused {
                    Text("1024–65535 사이의 숫자를 입력하세요").foregroundStyle(.red)
                }
                if model.settings.port != runningPort {
                    LabeledContent {
                        Button("재시작") { Task { await model.restartServer() } }
                            .help("새 포트로 서버 다시 시작")
                    } label: {
                        Text("재시작 후 적용").foregroundStyle(.orange)
                    }
                }
                Toggle("Auto Override System Proxy Settings at Launch", isOn: $settings.autoOverrideSystemProxy)
                    .help("실행할 때 \"이 Mac 캡처\"를 켜 시스템 프록시를 Prog로 바꾸기")
                Toggle("Auto Start Recording Traffic at Launch", isOn: $settings.autoStartRecording)
                    .help("끄면 실행할 때 기록 멈춤으로 시작")
            }
            Section { RootCertificateCard() }
        }
        .formStyle(.grouped)
        .onAppear { draft = String(model.settings.port) }
    }

    /// 입력 중에는 저장하지 않는다(엔터·포커스 해제 때만). 잘못된 값이면 저장된 값으로 되돌린다.
    private func commit() {
        if let p = parsed { model.settings.port = p } else { draft = String(model.settings.port) }
    }
}

/// 루트 인증서 카드: CA 이름·유효기간·이 Mac 설치 상태(Certificate 창과 같은 `macCAInstalled`).
private struct RootCertificateCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var resetting = false

    var body: some View {
        let ca = model.certificateAuthority
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal").font(.system(size: 28)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: ca.commonName).fontWeight(.semibold).textSelection(.enabled)
                Text("유효기간 \(ca.validity.lowerBound.formatted(date: .numeric, time: .omitted)) ~ \(ca.validity.upperBound.formatted(date: .numeric, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                // Certificate 창 이 Mac 섹션과 같은 값·문구(키체인에 있는지만 본다 — 신뢰 여부는 확인하지 않는다).
                Group {
                    if model.macCAInstalled {
                        Label("로그인 키체인에 설치됨", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        Text("설치되지 않음").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .help("이 Mac 로그인 키체인에 이 CA가 있는지")
                HStack {
                    Button("Open Certificate…") {
                        model.certificateSection = .mac
                        openWindow(id: "devices")
                    }
                    .help("Certificate 창의 이 Mac 섹션 열기")
                    Button("Generate new…") {
                        resetting = true
                        Task {
                            await model.resetCertificatesWithConfirmation()
                            resetting = false
                        }
                    }
                    .disabled(resetting)
                    .help("새 루트 CA 만들기 — 설치한 CA는 다시 설치해야 함")
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .task(id: ca.sha256Fingerprint) { await model.refreshMacCAInstalled() }
    }
}

private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Picker("Font Size:", selection: $settings.fontSize) {
                    ForEach(11...16, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                }
                .fixedSize()
                .help("상세 패널 본문·표 글꼴 크기")
                Picker("Tab Width:", selection: $settings.tabWidth) {
                    Text(verbatim: "2 Spaces").tag(2)
                    Text(verbatim: "4 Spaces").tag(4)
                }
                .pickerStyle(.segmented).fixedSize()
                .help("JSON Pretty·JSON 탭 들여쓰기 칸 수")
                Toggle("Use Monospaced Font", isOn: $settings.useMonospacedFont)
                    .help("목록 표를 고정폭 글꼴로")
                Toggle("Word Wrap", isOn: $settings.wrapLongLines)
                    .help("본문의 긴 줄을 창 폭에서 줄바꿈")
                Toggle("Show Invisibles", isOn: $settings.showInvisibles)
                    .help("본문 텍스트의 공백(·)·탭(→)·줄바꿈(¬) 표시")
                Toggle("Alternative Rows Background Colors", isOn: $settings.alternativeRowBackgrounds)
                    .help("목록 행에 번갈아 줄무늬")
            }
            Section {
                Picker("App Theme:", selection: $settings.appearance) {
                    Text(verbatim: "System").tag(Appearance.system)
                    Text(verbatim: "Light").tag(Appearance.light)
                    Text(verbatim: "Dark").tag(Appearance.dark)
                }
                .pickerStyle(.segmented).fixedSize()
                .help("앱 외관 — System은 macOS 설정을 따름")
                LabeledContent {
                    Button("Restore Defaults") { model.settings.restoreAppearanceDefaults() }
                        .help("이 탭(Appearance) 값만 기본으로 되돌리기")
                } label: {
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// §11 Advanced. Prog는 종료할 때 늘 이전 프록시로 되돌리므로 그 항목은 켜진 채 비활성으로 보인다.
private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var settings = model.settings
        Form {
            Section {
                Toggle("Restore to previous HTTP/HTTPS Proxy when Prog is closed", isOn: .constant(true))
                    .disabled(true)
                    .help("Prog는 종료할 때 늘 이전 시스템 프록시로 되돌립니다(끌 수 없음)")
                Toggle("Show Update Notification at Launch", isOn: $model.automaticUpdateChecks)
                    .help("새 버전을 자동으로 확인해 알리기(Sparkle 자동 확인)")
            }
            Section {
                Toggle("Use 24-Hour Time", isOn: $settings.use24HourTime)
                    .help("목록 Time 열을 24시간제로(끄면 AM/PM)")
                Toggle("Display Full Time Format", isOn: $settings.displayFullTimeFormat)
                    .help("목록 Time 열에 날짜와 시간대까지 보이기")
            }
            Section {
                Toggle("Show Alert when quitting the app", isOn: $settings.showQuitAlert)
                    .help("종료하기 전에 확인 알림 띄우기")
                Toggle("Show Resource Usage in Bottom Bar", isOn: $settings.showResourceUsage)
                    .help("하단 바에 메모리·처리 속도 보이기")
                Toggle("Hide Unnecessary Apple Requests from iOS Simulators", isOn: $settings.hideAppleSimulatorRequests)
                    .help("시뮬레이터가 보내는 apple.com·icloud.com 요청을 숨기기 — 하단 눈 토글로 볼 수 있음")
                Toggle("Stay On Top", isOn: $settings.stayOnTop)
                    .help("Prog 창을 항상 다른 앱 창 위에 두기")
                Toggle("Show Invisible Characters", isOn: $settings.showInvisibleCharacters)
                    .help("헤더 탭 값의 공백을 ·로 보이기 — 켜 있는 동안 글자 선택은 꺼지고, 우클릭 복사는 원래 값")
            }
        }
        .formStyle(.grouped)
    }
}

private struct SSLSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Toggle("SSL Proxying 사용", isOn: $settings.sslEnabled)
                .onChange(of: settings.sslEnabled) { _, _ in Task { await model.applySettingsToServer() } }
            Section {
                StringListEditor(items: $settings.sslPatterns, placeholder: "호스트 패턴") {
                    Task { await model.applySettingsToServer() }
                }
                HStack {
                    Button("가져오기…") { Task { await model.importSSLList() } }
                        .help("호스트 목록 파일(.txt) 또는 Proxyman SSL 목록에서 가져오기")
                    Button("내보내기…") { model.exportHostList(settings.sslPatterns, suggestedName: "ssl-proxying-list") }
                        .disabled(settings.sslPatterns.isEmpty)
                        .help("지금 목록을 호스트 목록 파일로 저장")
                }
            } header: {
                Text("호스트 패턴 (예: api.example.com, *.example.com)")
            } footer: {
                Text("한 줄에 패턴 하나. 팀 공용 목록은 파일로 주고받아 가져오세요.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct BypassSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                StringListEditor(items: $settings.bypassHosts, placeholder: "호스트") {}
            } header: {
                Text("시스템 프록시 Bypass 호스트")
            } footer: {
                Text("변경은 Mac 캡처를 다시 켤 때 적용")
            }
        }
        .formStyle(.grouped)
    }
}

/// §11 Tools. 옛 "Repeat 요청에 No-Cache"가 Use No-Caching on Repeated Requests(같은 키)다.
private struct ToolSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Toggle("Use No-Caching on Repeated Requests", isOn: $settings.toolSwitches.repeatNoCache)
                .help("Repeat으로 다시 보내는 요청에 캐시 무시 헤더 붙이기")
            LabeledContent("Request Timeout:") {
                HStack {
                    TextField("", value: Binding(get: { settings.requestTimeout }, set: { settings.requestTimeout = max($0, 0) }),
                              format: .number)
                        .labelsHidden().frame(width: 60).multilineTextAlignment(.trailing)
                    Text(verbatim: "seconds")
                }
            }
            .help("Compose·Repeat 요청 시간 제한(초) — 0이면 제한 없음")
            Toggle("Add --proxy flag into cURL command", isOn: $settings.curlProxyFlag)
                .help("cURL로 복사할 때 --proxy http://<IP>:<포트>를 붙여 Prog를 거치게")
            Toggle("Auto open the Export Directory after exporting", isOn: $settings.autoOpenExportDirectory)
                .help("내보낸 뒤 Finder에서 파일 보여 주기")
        }
        .formStyle(.grouped)
    }
}

/// 문자열 목록 편집: 추가(공백 제거·중복 무시)·삭제. 변경될 때마다 onChange를 부른다.
private struct StringListEditor: View {
    @Binding var items: [String]
    let placeholder: LocalizedStringKey
    let onChange: () -> Void
    @State private var draft = ""
    @State private var selection: String?

    var body: some View {
        List(items, id: \.self, selection: $selection) { Text($0) }
            .frame(minHeight: 100)
        HStack {
            TextField(placeholder, text: $draft).onSubmit(add)
            Button("추가", action: add)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("삭제") {
                items.removeAll { $0 == selection }
                selection = nil
                onChange()
            }
            .disabled(selection == nil)
        }
    }

    private func add() {
        let v = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !v.isEmpty, !items.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) else { return }
        items.append(v)
        onChange()
    }
}
