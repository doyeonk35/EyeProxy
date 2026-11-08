import AppKit
import EyeProxyKit
import SwiftUI

/// Map Local 응답 메시지 편집기: 저장 상태 점 + 줄번호·문법색이 있는 `CodeTextView` 편집 모드.
/// 색은 입력이 멈추고 약 300ms 뒤에 다시 입힌다(본문 JSON 색은 256KB 이하일 때만).
struct HTTPMessageEditor: View {
    @Binding var message: String
    let isSaved: Bool

    @Environment(AppModel.self) private var model
    @State private var colored = NSAttributedString()
    @State private var recolor: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(isSaved ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(isSaved ? "HTTP 메시지 형식(저장됨)" : "HTTP 메시지 형식(수정됨)")
                if !Self.hasStatusLine(message) {
                    Text("첫 줄은 상태줄이어야 합니다 (예: HTTP/1.1 200 OK)").foregroundStyle(.red)
                }
            }
            .font(.callout)
            CodeTextView(text: colored, wrap: model.settings.wrapLongLines, isEditable: true) { text in
                message = text
                scheduleRecolor(text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(.separator)
        }
        .onAppear { colored = Self.highlighted(message) }
        // 바깥(불러오기·파일 변환)에서 바뀐 메시지. 입력으로 바뀐 것은 이미 같은 문자열이라 건너뛴다.
        .onChange(of: message) { _, new in
            if new != colored.string, recolor == nil { colored = Self.highlighted(new) }
        }
        .onDisappear { recolor?.cancel() }
    }

    private func scheduleRecolor(_ text: String) {
        recolor?.cancel()
        recolor = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            recolor = nil
            colored = Self.highlighted(message)
        }
    }

    static func hasStatusLine(_ message: String) -> Bool {
        let first = message.prefix { $0 != "\n" && $0 != "\r" }.split(separator: " ", maxSplits: 2)
        return first.count >= 2 && first[0].uppercased().hasPrefix("HTTP/") && Int(first[1]) != nil
    }

    private static let jsonLimit = 256_000
    private static let statusColor = NSColor.systemPurple
    private static let tokenColors: [JSONToken.Kind: NSColor] = [
        .key: NSColor(named: "JSONKey") ?? .textColor,
        .string: NSColor(named: "JSONString") ?? .textColor,
        .number: NSColor(named: "JSONNumber") ?? .textColor,
        .keyword: NSColor(named: "JSONKeyword") ?? .textColor,
    ]

    /// 상태줄·헤더 이름 색, 본문이 JSON이면 JSON 색.
    static func highlighted(_ message: String) -> NSAttributedString {
        let a = CodeTextView.base(message)
        let ns = message as NSString
        let sep = [ns.range(of: "\r\n\r\n"), ns.range(of: "\n\n")].filter { $0.location != NSNotFound }.min { $0.location < $1.location }
        let headEnd = sep?.location ?? ns.length
        a.beginEditing()
        var first = true
        ns.enumerateSubstrings(in: NSRange(location: 0, length: headEnd), options: .byLines) { line, range, _, _ in
            guard let line else { return }
            if first {
                first = false
                a.addAttribute(.foregroundColor, value: statusColor, range: range)
            } else if let colon = line.firstIndex(of: ":") {
                a.addAttribute(.foregroundColor, value: tokenColors[.key] ?? NSColor.textColor,
                               range: NSRange(location: range.location, length: line[..<colon].utf16.count))
            }
        }
        if let sep {
            let start = sep.location + sep.length
            let body = ns.substring(from: start)
            if !body.isEmpty, body.utf8.count <= jsonLimit,
               (try? JSONSerialization.jsonObject(with: Data(body.utf8), options: .fragmentsAllowed)) != nil {
                for t in JSONHighlighter.tokens(body) {
                    a.addAttribute(.foregroundColor, value: tokenColors[t.kind] ?? NSColor.textColor,
                                   range: NSRange(location: start + t.range.location, length: t.range.length))
                }
            }
        }
        a.endEditing()
        return a
    }
}
