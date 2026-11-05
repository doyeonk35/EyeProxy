import EyeProxyKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("일반", systemImage: "gearshape") }
            SSLSettings().tabItem { Label("SSL Proxying", systemImage: "lock") }
            BypassSettings().tabItem { Label("Bypass", systemImage: "arrow.uturn.right") }
        }
        .frame(width: 480, height: 360)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    private var runningPort: Int? { if case .running(let p) = model.serverState { p } else { nil } }
    private var parsed: Int? { Int(draft).flatMap { (1024...65535).contains($0) ? $0 : nil } }

    var body: some View {
        Form {
            TextField("포트", text: $draft)
                .onSubmit(commit)
                .onChange(of: draft) { _, _ in commit() }
            if !draft.isEmpty, parsed == nil {
                Text("1024–65535 사이의 숫자를 입력하세요").foregroundStyle(.red)
            }
            if model.settings.port != runningPort {
                LabeledContent {
                    Button("재시작") { Task { await model.restartServer() } }
                } label: {
                    Text("재시작 후 적용").foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { draft = String(model.settings.port) }
    }

    private func commit() {
        if let p = parsed, p != model.settings.port { model.settings.port = p }
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
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("삭제") {
                items.removeAll { $0 == selection }
                selection = nil
                onChange()
            }
            .disabled(selection == nil)
        }
    }

    private func add() {
        let v = draft.trimmingCharacters(in: .whitespaces)
        draft = ""
        guard !v.isEmpty, !items.contains(v) else { return }
        items.append(v)
        onChange()
    }
}
