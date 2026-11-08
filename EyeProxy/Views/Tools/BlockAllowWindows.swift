import EyeProxyKit
import SwiftUI

struct BlockListWindow: View {
    var body: some View {
        ToolWindow(
            windowID: "tool-block", title: "Block List",
            description: "Block or Hide any Requests. Useful to block/hide unnecessary requests.",
            toolSwitch: \.blockList, file: .blockList, newRule: { BlockRule() },
            helpURL: URL(string: "https://docs.proxyman.com/advanced-features/block-list")
        ) { rule, onSave, onCancel in
            RuleSheet(rule: rule, onSave: onSave, onCancel: onCancel) {
                Picker("Action", selection: rule.action) {
                    ForEach([BlockAction.blockAndHide, .blockAndDisplay, .hideOnly], id: \.self) { Text(verbatim: $0.title).tag($0) }
                }
            }
        } columns: {
            ruleColumn("Block Action") { (r: BlockRule) in Text(verbatim: r.action.title) }
            ruleColumn("Method") { (r: BlockRule) in Text(verbatim: RuleText.method(r.match)) }
            ruleColumn("Matching Rule") { (r: BlockRule) in MatchingRuleCell(match: r.match) }
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
            RuleSheet(rule: rule, onSave: onSave, onCancel: onCancel) { EmptyView() }
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

/// ponytail: Block/Allow 임시 편집 시트(Name + MatchRuleFields + 도구별 칸). Task 16이 Block App 등을 붙여 대체한다.
struct RuleSheet<Rule: ToolRule, Extra: View>: View {
    @Binding var rule: Rule
    let onSave: (Rule) -> Void
    let onCancel: () -> Void
    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Matching Rule") { MatchRuleFields(name: $rule.name, match: $rule.match) }
                Section { extra }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(rule) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rule.match.url.isEmpty || rule.match.validationError != nil)
            }
            .padding()
        }
        .frame(width: 600)
    }
}
