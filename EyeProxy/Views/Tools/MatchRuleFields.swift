import EyeProxyKit
import SwiftUI

/// 편집기 공통 Matching Rule 칸(스펙 §6.3). `Form` 안에 넣어 쓴다.
struct MatchRuleFields: View {
    @Binding var name: String
    @Binding var match: MatchRule

    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var testing = false

    static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    var body: some View {
        Group {
            TextField("Name", text: $name)
            VStack(alignment: .leading, spacing: 4) {
                TextField("URL", text: $match.url, prompt: Text(verbatim: "api.example.com/v1/*"))
                hostHint.font(.caption)
            }
            HStack(spacing: 8) {
                methodMenu
                Picker("Mode", selection: $match.mode) {
                    Text("Use Wildcard").tag(MatchMode.wildcard)
                    Text("Use Regex").tag(MatchMode.regex)
                }
                .labelsHidden()
                .fixedSize()
                if match.mode == .wildcard { Text("와일드카드 * 와 ? 지원").foregroundStyle(.secondary) }
                Spacer()
                Button("Test your Rule") { testing = true }.buttonStyle(.link)
            }
            Toggle("Include all subpaths of this URL", isOn: $match.includeSubpaths)
                .toggleStyle(.checkbox)
            Toggle("쿼리 무시 (쿼리가 달라도 같은 규칙으로 처리)", isOn: $match.ignoreQuery)
                .toggleStyle(.checkbox)
            if let error = match.validationError { Text(error).foregroundStyle(.red) }
            if match.ignoreQuery && match.hasQueryLikePattern {
                Text("쿼리 무시가 켜져 있어 패턴의 쿼리 부분과는 비교하지 않습니다").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $testing) {
            TestRuleSheet(match: match, firstSample: selectedFlowURL)
        }
    }

    @ViewBuilder private var hostHint: some View {
        if match.hostPattern != nil {
            Text("이 호스트는 자동으로 복호화됩니다").foregroundStyle(.secondary)
        } else if match.needsSSLListEntry {
            HStack(spacing: 4) {
                Text("SSL Proxying 목록에 호스트를 추가해야 동작합니다").foregroundStyle(.orange)
                // 경고는 호스트를 뽑을 수 없는 규칙에만 뜨므로 설정의 SSL Proxying 탭을 연다.
                Button("목록에 추가") {
                    model.settingsTab = .ssl
                    openSettings()
                }
                .buttonStyle(.link)
            }
        }
    }

    private var selectedMethods: [String] {
        if case .exact(let list) = match.methods { list.map { $0.uppercased() } } else { [] }
    }

    private var methodMenu: some View {
        Menu {
            Toggle("ANY", isOn: Binding(get: { match.methods == .any }, set: { if $0 { match.methods = .any } }))
            Divider()
            ForEach(Self.methods, id: \.self) { method in
                Toggle(method, isOn: Binding(get: { selectedMethods.contains(method) }, set: { on in
                    let next = on ? selectedMethods + [method] : selectedMethods.filter { $0 != method }
                    match.methods = next.isEmpty ? .any : .exact(next)
                }))
            }
        } label: {
            Text(verbatim: RuleText.method(match))
        }
        .fixedSize()
    }

    private var selectedFlowURL: String {
        model.selectedFlowID.flatMap { model.session.flow($0) }.map { MatchRule.urlString($0.request, includeQuery: true) } ?? ""
    }
}
