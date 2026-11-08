import EyeProxyKit
import SwiftUI

/// Network Conditions 창(스펙 §5.7). 규칙은 트리가 아닌 배열이라 `ToolWindow`와 같은 배치로 따로 그린다.
/// 한 번에 규칙 하나만 켜진다(`RuleStore.activateNetworkCondition`).
struct NetworkConditionsWindow: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()
    @State private var draft: NetworkConditionRule?
    @State private var confirmDelete = false

    private var rules: [NetworkConditionRule] { model.rules.networkConditions }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Enable Network Conditions Tool", isOn: Binding(
                    get: { model.settings.toolSwitches.networkConditions },
                    set: { model.settings.toolSwitches.networkConditions = $0 }))
                Text(verbatim: "Simulate Network Conditions with various Preset Profiles. Useful to test with slow networks.")
                Text(verbatim: "Only 1 Rule can be activated at once.").foregroundStyle(.orange)
            }
            .padding()
            table
                .overlay {
                    if rules.isEmpty { Text("Click \"+\" or ⌘N to add new entry").foregroundStyle(.secondary) }
                }
            Text("New: ⌘N  Edit: ⌘↩  Delete: ⌘⌫  Toggle: ␣")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            Divider()
            HStack(spacing: 8) {
                Button { draft = Self.newRule() } label: { Image(systemName: "plus") }
                    .keyboardShortcut("n")
                    .help("New (⌘N)")
                Button { confirmDelete = true } label: { Image(systemName: "minus") }
                    .keyboardShortcut(.delete)
                    .disabled(selection.isEmpty)
                    .help("Delete (⌘⌫)")
                if let url = URL(string: "https://docs.proxyman.com/advanced-features/network-conditions") { HelpLink(destination: url) }
                Spacer()
                Menu("More") {
                    Button("Import…") {}.disabled(true)
                    Button("Export…") {}.disabled(true)
                }
                .fixedSize()
            }
            .padding(8)
        }
        .frame(minWidth: 800, minHeight: 420)
        .background {
            Button("Edit") { edit(selection.first) }
                .keyboardShortcut(.return)
                .disabled(selection.count != 1)
                .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .sheet(item: $draft) { rule in
            NetworkConditionSheet(rule: Binding(get: { draft ?? rule }, set: { draft = $0 }),
                                  isNew: !rules.contains { $0.id == rule.id }, onSave: commit, onCancel: { draft = nil })
        }
        .confirmationDialog("선택한 규칙을 삭제할까요? 되돌릴 수 없습니다.", isPresented: $confirmDelete) {
            Button("삭제", role: .destructive) {
                model.rules.networkConditions.removeAll { selection.contains($0.id) }
                selection = []
            }
            Button("취소", role: .cancel) {}
        }
        .onAppear(perform: consumePendingRule)
        .onChange(of: model.pendingNewRule) { consumePendingRule() }
    }

    private var table: some View {
        Table(rules, selection: $selection) {
            TableColumn("Enabled") { (r: NetworkConditionRule) in
                Toggle("", isOn: Binding(get: { r.isEnabled }, set: { setEnabled(r.id, $0) }))
                    .labelsHidden()
                    .accessibilityLabel(Text(verbatim: r.name))
            }
            .width(56)
            TableColumn("Name") { (r: NetworkConditionRule) in Text(verbatim: r.name).lineLimit(1) }
                .width(min: 120, ideal: 180)
            TableColumn("Status") { (r: NetworkConditionRule) in
                if r.isEnabled {
                    let on = model.settings.toolSwitches.networkConditions
                    HStack(spacing: 4) {
                        Circle().fill(on ? Color.green : Color.secondary).frame(width: 8, height: 8)
                        Text(on ? "Active" : "도구 꺼짐").foregroundStyle(on ? .primary : .secondary)
                    }
                }
            }
            .width(min: 70, ideal: 100)
            TableColumn("Host") { (r: NetworkConditionRule) in
                Text(verbatim: r.isSystemWide ? "System-wide" : r.url).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 100, ideal: 160)
            TableColumn("Network Profile") { (r: NetworkConditionRule) in Text(verbatim: r.networkProfile.summary).lineLimit(1) }
                .width(min: 260, ideal: 420)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                Button("Edit") { edit(ids.first) }.disabled(ids.count != 1)
                Divider()
                Button("Delete") { selection = ids; confirmDelete = true }
            }
        } primaryAction: { ids in
            if ids.count == 1 { edit(ids.first) }
        }
        .onKeyPress(.space) {
            guard selection.count == 1, let id = selection.first, let r = rules.first(where: { $0.id == id }) else { return .ignored }
            setEnabled(id, !r.isEnabled)
            return .handled
        }
    }

    static func newRule(host: String = "") -> NetworkConditionRule {
        NetworkConditionRule(name: host.isEmpty ? "Untitled" : host, url: host, networkProfile: NetworkProfile.presets[1])
    }

    /// 켜면 나머지는 꺼진다.
    private func setEnabled(_ id: String, _ on: Bool) {
        if on {
            model.rules.activateNetworkCondition(id: id)
        } else {
            model.rules.networkConditions = rules.map { var r = $0; if r.id == id { r.isEnabled = false }; return r }
        }
    }

    private func edit(_ id: String?) {
        draft = rules.first { $0.id == id }
    }

    private func commit(_ rule: NetworkConditionRule) {
        if let i = rules.firstIndex(where: { $0.id == rule.id }) {
            model.rules.networkConditions[i] = rule
        } else {
            model.rules.networkConditions.append(rule)
        }
        if rule.isEnabled { model.rules.activateNetworkCondition(id: rule.id) }
        draft = nil
        selection = [rule.id]
    }

    /// 우클릭 ▸ Tools ▸ Network Conditions…: 그 요청의 호스트로 채운 새 규칙.
    private func consumePendingRule() {
        guard let pending = model.pendingNewRule, pending.windowID == "tool-network" else { return }
        model.pendingNewRule = nil
        draft = Self.newRule(host: model.session.flow(pending.flowID)?.request.host ?? pending.match.hostPattern ?? "")
    }
}

extension NetworkProfile {
    /// "Very Bad Network (Download: <1 mbps, Upload: <1 mbps)". 표기가 없으면 대역폭으로 만든다.
    var summary: String {
        let down = downloadBandwidthTitle.isEmpty ? Self.rateText(downloadBandwidth) : downloadBandwidthTitle
        let up = uploadBandwidthTitle.isEmpty ? Self.rateText(uploadBandwidth) : uploadBandwidthTitle
        return "\(name) (Download: \(down), Upload: \(up))"
    }

    /// B/s → "1.5 mbps"·"780 kbps". 0 이하는 제한 없음.
    static func rateText(_ bytesPerSecond: Int) -> String {
        guard bytesPerSecond > 0 else { return "unlimited" }
        let kbps = Double(bytesPerSecond) * 8 / 1000
        return kbps >= 1000 ? "\((kbps / 1000).formatted(.number.precision(.fractionLength(0...2)))) mbps"
            : "\(kbps.formatted(.number.precision(.fractionLength(0...1)))) kbps"
    }

    /// Custom Profile…: Mbps·ms·% 입력으로 만든 고정 대역폭 프로필. 음수는 0, 손실은 0–100으로 자른다.
    static func custom(name: String, downMbps: Double, upMbps: Double, delayMS: Int, lossPercent: Double) -> NetworkProfile {
        // 상한 100 Gbps: Int 변환이 넘치지 않게.
        func bytes(_ mbps: Double) -> Int { Int(min(max(mbps.isFinite ? mbps : 0, 0), 100_000) * 125_000) }
        let down = bytes(downMbps), up = bytes(upMbps)
        let loss = lossPercent.isFinite ? min(max(lossPercent, 0), 100) : 0
        return NetworkProfile(name: name, profileType: 1, downloadBandwidth: down, uploadBandwidth: up,
                              downloadBandwidthTitle: rateText(down), uploadBandwidthTitle: rateText(up),
                              delay: max(delayMS, 0), packageDrop: loss, isAllLostConnection: loss >= 100,
                              downloadMin: down, uploadMin: up)
    }
}

/// Network Conditions 편집 시트(스펙 §6.3): Name, ☐ Apply System-wide / Host, Network Profile ▾ + Custom Profile….
struct NetworkConditionSheet: View {
    @Binding var rule: NetworkConditionRule
    let isNew: Bool
    let onSave: (NetworkConditionRule) -> Void
    let onCancel: () -> Void

    @Environment(AppModel.self) private var model
    @State private var addingProfile = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $rule.name)
                Toggle("Apply System-wide", isOn: $rule.isSystemWide)
                TextField("Host", text: $rule.url, prompt: Text(verbatim: "api.example.com"))
                    .disabled(rule.isSystemWide)
                if !rule.isSystemWide {
                    Text("호스트에 와일드카드 * 를 쓸 수 있습니다 (예: *.example.com)").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Picker("Network Profile", selection: profileSelection) {
                        ForEach(NetworkProfile.presets.indices, id: \.self) { i in
                            Text(verbatim: NetworkProfile.presets[i].summary).tag("preset:\(i)")
                        }
                        let custom = model.rules.customNetworkProfiles
                        if !custom.isEmpty {
                            Divider()
                            ForEach(custom.indices, id: \.self) { i in Text(verbatim: custom[i].summary).tag("custom:\(i)") }
                        }
                        if profileTag == "current" {
                            Divider()
                            Text(verbatim: rule.networkProfile.summary).tag("current")
                        }
                    }
                    Button("Custom Profile…") { addingProfile = true }
                }
                Text(Self.detail(rule.networkProfile)).font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { onSave(rule) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(rule.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || (!rule.isSystemWide && rule.url.trimmingCharacters(in: .whitespaces).isEmpty))
            }
            .padding()
        }
        .frame(width: 640)
        .sheet(isPresented: $addingProfile) {
            CustomProfileSheet { profile in
                model.rules.customNetworkProfiles.append(profile)
                rule.networkProfile = profile
            }
        }
    }

    private var profileTag: String {
        if let i = NetworkProfile.presets.firstIndex(of: rule.networkProfile) { return "preset:\(i)" }
        if let i = model.rules.customNetworkProfiles.firstIndex(of: rule.networkProfile) { return "custom:\(i)" }
        return "current"   // 가져온 규칙 등 목록에 없는 프로필
    }

    private var profileSelection: Binding<String> {
        Binding(get: { profileTag }, set: { tag in
            let parts = tag.split(separator: ":")
            guard parts.count == 2, let i = Int(parts[1]) else { return }
            let list = parts[0] == "preset" ? NetworkProfile.presets : model.rules.customNetworkProfiles
            if list.indices.contains(i) { rule.networkProfile = list[i] }
        })
    }

    static func detail(_ p: NetworkProfile) -> String {
        if p.isAllLostConnection { return String(localized: "연결을 받기만 하고 응답하지 않습니다") }
        return String(localized: "지연 \(p.delay) ms · 손실 \(p.packageDrop.formatted()) %")
    }
}

/// Custom Profile…: ↓·↑ Mbps, 지연 ms, 손실 %, 이름.
struct CustomProfileSheet: View {
    let onSave: (NetworkProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    // 문자열로 받는다: 값 형식 칸은 포커스를 잃어야 반영돼 ⌘↩가 이전 값을 저장할 수 있다.
    @State private var down = "1"
    @State private var up = "1"
    @State private var delay = "100"
    @State private var loss = "0"

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("이름", text: $name, prompt: Text(verbatim: "My Network"))
                TextField("↓ Download (Mbps)", text: $down)
                TextField("↑ Upload (Mbps)", text: $up)
                TextField("지연 (ms)", text: $delay)
                TextField("손실 (%)", text: $loss)
                Text("0 Mbps는 대역폭 제한 없음, 손실 100%는 응답하지 않음입니다").font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    onSave(.custom(name: name.trimmingCharacters(in: .whitespaces), downMbps: number(down), upMbps: number(up),
                                     delayMS: Int(min(max(number(delay), 0), 600_000)), lossPercent: number(loss)))
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 420)
    }

    private func number(_ text: String) -> Double {
        let v = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
        return v.isFinite ? v : 0
    }
}
