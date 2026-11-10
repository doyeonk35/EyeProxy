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
                Group {
                    if model.macCAInstalled {
                        Label("이 Mac: 설치됨 · 신뢰함", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("이 Mac: 설치되지 않음", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .help("로그인 키체인에 이 CA가 있는지(Certificate 창과 같은 기준)")
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
                    .help("새 루트 CA 만들기 — 설치한 CA는 다시 설치")
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
    var body: some View {
        Form {
            Toggle("Restore to previous HTTP/HTTPS Proxy when Prog is closed", isOn: .constant(true))
                .disabled(true)
                .help("Prog는 종료할 때 늘 이전 시스템 프록시로 되돌립니다(끌 수 없음)")
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
            Section("호스트 패턴 (예: api.example.com, *.example.com)") {
                StringListEditor(items: $settings.sslPatterns, placeholder: "호스트 패턴") {
                    Task { await model.applySettingsToServer() }
                }
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

private struct ToolSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Toggle("Repeat 요청에 No-Cache 사용", isOn: $settings.toolSwitches.repeatNoCache)
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
