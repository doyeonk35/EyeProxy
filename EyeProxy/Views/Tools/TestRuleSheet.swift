import EyeProxyKit
import SwiftUI

/// Test your Rule: 편집 중인 규칙을 복사해 샘플 URL 줄마다 Matched / Not Matched를 보인다. 메서드는 보지 않는다.
struct TestRuleSheet: View {
    @State private var match: MatchRule
    @State private var samples: String
    @Environment(\.dismiss) private var dismiss

    init(match: MatchRule, firstSample: String) {
        _match = State(initialValue: match)
        _samples = State(initialValue: firstSample.isEmpty ? "" : firstSample + "\n")
    }

    private var lines: [String] {
        samples.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Test your Rule").font(.headline)
            HStack {
                Picker("Mode", selection: $match.mode) {
                    Text("Use Wildcard").tag(MatchMode.wildcard)
                    Text("Use Regex").tag(MatchMode.regex)
                }
                .labelsHidden()
                .fixedSize()
                TextField("URL", text: $match.url, prompt: Text(verbatim: "api.example.com/v1/*"))
            }
            Toggle("Include all subpaths of this URL", isOn: $match.includeSubpaths)
            QueryFields(match: $match)
            if let error = match.validationError { Text(error).foregroundStyle(.red) }
            Text("샘플 URL (한 줄에 하나)").foregroundStyle(.secondary)
            TextEditor(text: $samples)
                .font(.system(.body, design: .monospaced))
                .frame(height: 110)
                .border(.separator)
            List(Array(lines.enumerated()), id: \.offset) { _, line in
                let matched = match.matches(sampleURL: line)
                HStack(spacing: 12) {
                    Text(matched ? "Matched" : "Not Matched")
                        .foregroundStyle(matched ? .green : .red)
                        .frame(width: 96, alignment: .leading)
                    Text(verbatim: line).lineLimit(1).truncationMode(.middle)
                }
            }
            .listStyle(.bordered)
            HStack {
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 640, height: match.queryMode == .selected || !match.queryConditions.isEmpty ? 640 : 480)
    }
}
