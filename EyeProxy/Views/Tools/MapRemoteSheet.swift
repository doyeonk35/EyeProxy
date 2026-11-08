import EyeProxyKit
import SwiftUI

struct MapRemoteWindow: View {
    var body: some View {
        ToolWindow(
            windowID: "tool-map-remote", title: "Map Remote",
            description: "Map Requests to different Host, Path, Port. Useful to map from Localhost ↔ Production.",
            toolSwitch: \.mapRemote, file: .mapRemote, newRule: { MapRemoteRule() },
            helpURL: URL(string: "https://docs.proxyman.com/advanced-features/map-remote"),
            note: "localhost 요청이 안 보이면 /etc/hosts에 도메인 별칭을 설정하세요",
            // Proxyman처럼 Include all subpaths 기본 켜짐.
            prefill: { rule, _ in rule.match.includeSubpaths = true }
        ) { rule, onSave, onCancel in
            MapRemoteSheet(rule: rule, onSave: onSave, onCancel: onCancel)
        } columns: {
            ruleColumn("Method") { (r: MapRemoteRule) in Text(verbatim: RuleText.method(r.match)) }
            ruleColumn("Matching Rule") { (r: MapRemoteRule) in MatchingRuleCell(match: r.match) }
            ruleColumn("To") { (r: MapRemoteRule) in Text(verbatim: r.mapTo.display).lineLimit(1).truncationMode(.middle) }
        }
    }
}

extension MapTarget {
    /// 표의 To 열. 빈 칸은 빼고 URL 모양으로.
    var display: String {
        var s = scheme.map { $0 + "://" } ?? ""
        s += host ?? "*"
        if let port { s += ":\(port)" }
        if let path { s += path.hasPrefix("/") ? path : "/" + path }
        if let query { s += "?" + query }
        return s
    }
}

/// Map Remote 편집 시트(스펙 §6.3).
struct MapRemoteSheet: View {
    @Binding var rule: MapRemoteRule
    let onSave: (MapRemoteRule) -> Void
    let onCancel: () -> Void

    @Environment(AppModel.self) private var model

    private var isNew: Bool { model.rules.tree(.mapRemote).node(rule.id) == nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Matching Rule") { MatchRuleFields(name: $rule.name, match: $rule.match) }
                Section("Map To") {
                    Picker("Protocol", selection: $rule.mapTo.scheme) {
                        Text("—").tag(String?.none)
                        Text(verbatim: "http").tag(String?.some("http"))
                        Text(verbatim: "https").tag(String?.some("https"))
                    }
                    .fixedSize()
                    TextField("Host", text: field(\.host), prompt: Text(verbatim: "example.com"))
                        .onChange(of: rule.mapTo.host) { old, new in autoParse(old: old, new: new) }
                    TextField("Port", text: Binding(
                        get: { rule.mapTo.port.map(String.init) ?? "" },
                        set: { text in
                            let digits = text.filter(\.isASCII).filter(\.isNumber)
                            if digits.isEmpty { rule.mapTo.port = nil } else if let p = Int(digits), (1...65535).contains(p) { rule.mapTo.port = p }
                        }), prompt: Text(verbatim: "443"))
                    TextField("Path", text: field(\.path), prompt: Text(verbatim: "v2/api"))
                    TextField("Query", text: field(\.query), prompt: Text(verbatim: "id=123"))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("빈 칸은 일치한 요청의 원래 값을 그대로 씁니다. 와일드카드·정규식은 쓸 수 없습니다.")
                        Text("Hint: Host 칸에 URL을 붙여 넣으면 Host·Port·Path·Query로 자동으로 나눕니다.")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Section("Advanced Settings") {
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Preserve the Original URL after matching with Map Remote", isOn: $rule.preserveOriginalURL)
                        Text("끄면 요청 URL이 Map Remote의 새 URL로 바뀌어 보입니다. 켜면 목록에는 원래 URL을 보이고 실제 전송만 바꿉니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Preserve Host Header", isOn: $rule.preserveHostHeader)
                        Text("켜면 요청의 Host 헤더를 바꾸지 않습니다.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { onSave(rule) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(rule.match.url.isEmpty || rule.match.validationError != nil)
            }
            .padding()
        }
        .frame(width: 837, height: 669)
    }

    /// nil ↔ "" 칸.
    private func field(_ key: WritableKeyPath<MapTarget, String?>) -> Binding<String> {
        Binding(get: { rule.mapTo[keyPath: key] ?? "" }, set: { rule.mapTo[keyPath: key] = $0.isEmpty ? nil : $0 })
    }

    /// 한 번에 여러 글자가 들어오면(붙여넣기) URL로 보고 칸을 채운다. 한 글자씩 입력할 때는 건드리지 않는다.
    private func autoParse(old: String?, new: String?) {
        guard let new, new.count - (old?.count ?? 0) > 1 else { return }
        let t = MapTarget.parse(pastedURL: new)
        guard t.scheme != nil || t.port != nil || t.path != nil || t.query != nil, let host = t.host else { return }
        // 다섯 칸을 모두 붙여 넣은 URL로 바꾼다(URL에 없는 부분은 비운다). 이전 port·path가 남으면 엉뚱한 곳으로 간다.
        rule.mapTo = MapTarget(scheme: t.scheme.flatMap { ["http", "https"].contains($0) ? $0 : nil },
                               host: host, port: t.port, path: t.path, query: t.query)
    }
}
