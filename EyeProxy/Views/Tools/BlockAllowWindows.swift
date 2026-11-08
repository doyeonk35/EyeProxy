import AppKit
import EyeProxyKit
import SwiftUI
import UniformTypeIdentifiers

struct BlockListWindow: View {
    var body: some View {
        ToolWindow(
            windowID: "tool-block", title: "Block List",
            description: "Block or Hide any Requests. Useful to block/hide unnecessary requests.",
            toolSwitch: \.blockList, file: .blockList, newRule: { BlockRule() },
            helpURL: URL(string: "https://docs.proxyman.com/advanced-features/block-list")
        ) { rule, onSave, onCancel in
            RuleSheet(rule: rule, file: .blockList, allowsEmptyURL: rule.wrappedValue.appPath != nil, onSave: onSave, onCancel: onCancel) {
                Picker("Action", selection: rule.action) {
                    ForEach([BlockAction.blockAndHide, .blockAndDisplay, .hideOnly], id: \.self) { Text(verbatim: $0.title).tag($0) }
                }
                .fixedSize()
                BlockAppField(appPath: rule.appPath)
            }
        } columns: {
            ruleColumn("Block Action") { (r: BlockRule) in Text(verbatim: r.action.title) }
            ruleColumn("Method") { (r: BlockRule) in Text(verbatim: RuleText.method(r.match)) }
            ruleColumn("Matching Rule") { (r: BlockRule) in
                if let app = r.appPath, r.match.url.isEmpty {
                    Text(verbatim: "App: \(BlockAppField.name(app))").lineLimit(1)
                } else {
                    MatchingRuleCell(match: r.match)
                }
            }
        }
    }
}

struct AllowListWindow: View {
    var body: some View {
        ToolWindow(
            windowID: "tool-allow", title: "Allow List",
            description: "Only allow certain Requests. Other requests are passed through without recording.",
            toolSwitch: \.allowList, file: .allowList, newRule: { AllowRule() },
            helpURL: URL(string: "https://docs.proxyman.com/advanced-features/allow-list")
        ) { rule, onSave, onCancel in
            RuleSheet(rule: rule, file: .allowList, onSave: onSave, onCancel: onCancel) { EmptyView() }
        } columns: {
            ruleColumn("Method") { (r: AllowRule) in Text(verbatim: RuleText.method(r.match)) }
            ruleColumn("Matching Rule") { (r: AllowRule) in MatchingRuleCell(match: r.match) }
        }
    }
}

extension BlockAction {
    var title: String {
        switch self {
        case .blockAndHide: "Block & Hide Request"
        case .blockAndDisplay: "Block & Display Requests"
        case .hideOnly: "Hide, but not Block"
        }
    }
}

/// `Block App [Select App…]`: 고른 앱 아이콘·이름과 지우기 버튼.
struct BlockAppField: View {
    @Binding var appPath: String?

    static func name(_ path: String) -> String {
        FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }

    var body: some View {
        LabeledContent("Block App") {
            HStack(spacing: 6) {
                if let appPath {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appPath)).resizable().frame(width: 18, height: 18)
                    Text(verbatim: Self.name(appPath)).lineLimit(1)
                    Button { self.appPath = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("앱 지우기")
                }
                Button("Select App…", action: choose)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url { appPath = url.path }
    }
}

/// Block/Allow/Breakpoint 규칙 시트: Name + MatchRuleFields + 도구별 칸, [Cancel] [Add|Save ⌘↩] (스펙 §6.3).
struct RuleSheet<Rule: ToolRule, Extra: View>: View {
    @Binding var rule: Rule
    let file: RuleFile<Rule>
    /// Block App이 있으면 URL 없이도 저장할 수 있다(앱의 모든 요청).
    var allowsEmptyURL = false
    let onSave: (Rule) -> Void
    let onCancel: () -> Void
    @ViewBuilder let extra: Extra

    @Environment(AppModel.self) private var model

    private var isNew: Bool { model.rules.tree(file).node(rule.id) == nil }
    private var isBlockOrAllow: Bool { Rule.self == BlockRule.self || Rule.self == AllowRule.self }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Matching Rule") {
                    MatchRuleFields(name: $rule.name, match: $rule.match, hostOnlyDecidedAtConnect: isBlockOrAllow)
                }
                Section { extra }
            }
            .formStyle(.grouped)
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { onSave(rule) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled((rule.match.url.isEmpty && !allowsEmptyURL) || rule.match.validationError != nil)
            }
            .padding()
        }
        .frame(width: 640)
    }
}
