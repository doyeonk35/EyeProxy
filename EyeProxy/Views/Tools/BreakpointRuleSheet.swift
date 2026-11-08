import EyeProxyKit
import SwiftUI

/// Breakpoint 규칙 창(스펙 §5.1). 편집 시트 = Matching Rule + ☐ Request ☐ Response.
struct BreakpointRulesWindow: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ToolWindow(
            windowID: "tool-breakpoint-rules", title: "Breakpoint",
            description: "Modify the Request/Response on the fly. Support URL, Method, Status Code, Headers, and Body.",
            toolSwitch: \.breakpoint, file: .breakpoint, newRule: { BreakpointRule() },
            helpURL: URL(string: "https://docs.proxyman.com/advanced-features/breakpoint"),
            accessory: { Button("Templates…") { openWindow(id: "breakpoint-templates") } }
        ) { rule, onSave, onCancel in
            RuleSheet(rule: rule, file: .breakpoint, onSave: onSave, onCancel: onCancel) {
                HStack(spacing: 16) {
                    Toggle("Request", isOn: rule.onRequest)
                    Toggle("Response", isOn: rule.onResponse)
                }
                if !rule.wrappedValue.onRequest && !rule.wrappedValue.onResponse {
                    Text("Request·Response 중 하나는 켜야 멈춥니다").foregroundStyle(.orange)
                }
            }
        } columns: {
            ruleColumn("Method") { (r: BreakpointRule) in Text(verbatim: RuleText.method(r.match)) }
            ruleColumn("Matching Rule") { (r: BreakpointRule) in MatchingRuleCell(match: r.match) }
            ruleColumn("Request") { (r: BreakpointRule) in check(r.onRequest) }
            ruleColumn("Response") { (r: BreakpointRule) in check(r.onResponse) }
        }
    }

    private func check(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
    }
}
