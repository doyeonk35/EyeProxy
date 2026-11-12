import EyeProxyKit
import SwiftUI

/// File ▸ New Domain or App… ⇧⌘K·그룹 Edit…(스펙 §4.1): 도메인 패턴과 이 Mac 앱을 묶은 호스트 그룹을 만들거나 고친다.
struct HostGroupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(SessionTab.self) private var tab
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    let request: GroupSheetRequest
    @State private var name: String
    @State private var patternText: String
    @State private var apps: [String]
    @State private var search = ""
    @State private var saveToFavorites = true
    /// 고르기 목록. 시트를 열 때 이 탭 세션 전체로 한 번 만든다(사이드바 거르기와 무관).
    @State private var source: SidebarTree?

    init(request: GroupSheetRequest) {
        self.request = request
        _name = State(initialValue: request.draft.name)
        _patternText = State(initialValue: request.draft.hostPatterns.joined(separator: "\n"))
        _apps = State(initialValue: request.draft.apps)
    }

    private var parsed: HostList.Parsed { HostList.patterns(fromText: patternText) }

    private var group: HostGroup {
        HostGroup(id: request.draft.id, name: name.trimmingCharacters(in: .whitespaces), hostPatterns: parsed.patterns, apps: apps)
    }

    var body: some View {
        let parsed = parsed
        let placeholder = HostGroup(name: "", hostPatterns: parsed.patterns, apps: apps).displayName
        VStack(alignment: .leading, spacing: 10) {
            Text(request.isEditing ? "Edit Group" : "New Domain or App").font(.headline)
            TextField("이름", text: $name, prompt: Text(placeholder.isEmpty ? "이름" : placeholder))
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("도메인 패턴 (줄이나 쉼표로 나눔, *·? 사용)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("가져오기…") { Task { await importList() } }
                    .controlSize(.small)
                    .help("호스트 목록 파일의 패턴을 더하기")
            }
            TextEditor(text: $patternText)
                .font(.body.monospaced())
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            if parsed.rejected > 0 {
                Text("형식이 맞지 않는 항목 \(parsed.rejected)개는 버립니다").font(.caption).foregroundStyle(.red)
            }
            TextField("검색", text: $search, prompt: Text("이 탭의 도메인·앱 검색"))
                .textFieldStyle(.roundedBorder)
            HStack(alignment: .top) {
                List {
                    Section("Domains") {
                        ForEach(hosts, id: \.self) { host in
                            Toggle(host, isOn: hostBinding(host)).toggleStyle(.checkbox)
                        }
                    }
                }
                List {
                    Section("Apps") {
                        ForEach(appRows, id: \.key) { row in
                            Toggle(isOn: appBinding(row.key)) {
                                Label { Text(row.name) } icon: { AppIcon(path: row.path) }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .frame(height: 220)
            if !request.isEditing {
                Toggle("Favorites에 저장", isOn: $saveToFavorites)
                    .help("끄면 이 탭에서만 쓰고 Groups에 저장하지 않음")
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(request.isEditing ? "Save" : "Open", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(group.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            source = SidebarTree.build(flows: tab.session.flows, attribution: tab.processes.attribution, devices: [],
                                       pinned: [], runtimes: model.simulatorRuntimes)
        }
    }

    private func matchesSearch(_ s: String) -> Bool { search.isEmpty || s.localizedCaseInsensitiveContains(search) }

    private var hosts: [String] { (source?.domains ?? []).map(\.host).filter(matchesSearch) }

    /// 이 탭 세션의 앱("기타" 빼고) + 그룹에 있지만 이 세션에 없는 앱(풀 수 있게).
    private var appRows: [(key: String, name: String, path: String?)] {
        let session = (source?.apps ?? []).filter { $0.groupKey != FlowFilter.unknownProcessKey }
        let known = Set(session.map(\.groupKey))
        return (session.map { ($0.groupKey, $0.displayName, $0.path) } + apps.filter { !known.contains($0) }.map { ($0, $0, nil) })
            .filter { matchesSearch($0.1) || matchesSearch($0.0) }
    }

    private func hostBinding(_ host: String) -> Binding<Bool> {
        let key = HostList.normalize(host) ?? host.lowercased()
        return Binding(
            get: { parsed.patterns.contains(key) },
            set: { on in
                if on { append([key]) } else { patternText = parsed.patterns.filter { $0 != key }.joined(separator: "\n") }
            }
        )
    }

    private func appBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { apps.contains(key) },
            set: { on in if on { if !apps.contains(key) { apps.append(key) } } else { apps.removeAll { $0 == key } } }
        )
    }

    private func append(_ patterns: [String]) {
        guard !patterns.isEmpty else { return }
        let base = patternText.trimmingCharacters(in: .whitespacesAndNewlines)
        patternText = ((base.isEmpty ? [] : [base]) + patterns).joined(separator: "\n")
    }

    /// 가져오기…: 호스트 목록 파일의 패턴 중 아직 없는 것만 뒤에 붙인다. 오류 알림은 `pickHostList`가 낸다.
    private func importList() async {
        guard let list = await model.pickHostList() else { return }
        append(HostList.merge(list.patterns, into: parsed.patterns).added)
    }

    private func commit() {
        let g = group
        guard !g.isEmpty else { return }
        if request.isEditing {
            model.settings.saveGroup(g)
            model.replaceGroupSelection(g)
        } else {
            if saveToFavorites { model.settings.saveGroup(g) }
            openWindow(id: "main", value: model.newTabID(sharing: tab, selecting: .group(g)))
        }
        dismiss()
    }
}
