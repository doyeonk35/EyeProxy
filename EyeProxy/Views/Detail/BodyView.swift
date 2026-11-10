import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct BodyView: View {
    let data: Data
    let headers: [HTTPHeader]
    @Environment(AppModel.self) private var model

    /// JSON 본문의 보기. 트리는 Treeview 탭, Content-Type과 상관없는 JSON 보기는 JSON 탭(JSONTabView).
    private enum Mode { case pretty, raw }

    /// 디코드 결과와 화면용 문자열(2MB 컷·hex 덤프·JSON 색)을 한 번만 만든다.
    private struct Loaded {
        let decoded: DecodedBody
        let display: NSAttributedString
        let truncated: Bool
        let raw: NSAttributedString?  // JSON Raw 모드
        let rawTruncated: Bool
        let image: NSImage?
    }

    /// 메인 밖에서 만드는 부분 (NSAttributedString은 Sendable이 아니라 토큰까지만).
    private struct Prepared: Sendable {
        let decoded: DecodedBody
        var display = ""
        var truncated = false
        var tokens: [JSONToken] = []
        var raw: String?
        var rawTruncated = false
    }

    @State private var loaded: Loaded?
    @State private var mode = Mode.pretty

    private var encoding: String? {
        headers.first { $0.name.caseInsensitiveCompare("Content-Encoding") == .orderedSame }?.value
    }

    private var summary: String {
        String(localized: "원본 \(ByteSize.format(data.count))") + (encoding.map { String(localized: " · Content-Encoding: \($0)") } ?? "")
    }

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if case .json? = loaded?.decoded {
                    Picker("", selection: $mode) {
                        Text("Pretty").tag(Mode.pretty)
                        Text("Raw").tag(Mode.raw)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Spacer()
                Toggle("줄바꿈", isOn: $settings.wrapLongLines).toggleStyle(.checkbox)
                Text(verbatim: summary).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            Divider()
            if let loaded { content(loaded) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        // 디코드는 본문이 바뀔 때만 (세션 이벤트마다 다시 하지 않음), 메인 밖에서.
        .task(id: data.count) {
            let (b, h) = (data, headers)
            let p = await Task.detached { Self.prepare(b, h) }.value
            var image: NSImage?
            if case .image(let img) = p.decoded { image = NSImage(data: img) }
            loaded = Loaded(
                decoded: p.decoded, display: Self.highlighted(p.display, p.tokens), truncated: p.truncated,
                raw: p.raw.map { CodeTextView.base($0) }, rawTruncated: p.rawTruncated, image: image)
        }
    }

    private nonisolated static let textLimit = 2_000_000
    private nonisolated static let hexLimit = 64 * 1024
    nonisolated static let highlightLimit = 256_000

    private nonisolated static func prepare(_ body: Data, _ headers: [HTTPHeader]) -> Prepared {
        let d = BodyDecoder.decode(body: body, headers: headers)
        var p = Prepared(decoded: d)
        switch d {
        case .empty: break
        case .json(let s, let raw):
            (p.display, p.truncated) = capped(s)
            if p.display.utf8.count <= highlightLimit { p.tokens = JSONHighlighter.tokens(p.display) }
            let (r, cut) = capped(raw)
            (p.raw, p.rawTruncated) = (r, cut)
        case .text(let s), .html(let s):
            (p.display, p.truncated) = capped(s)
        case .image(let x), .binary(let x):
            p.display = hex(x.prefix(hexLimit)) + (x.count > hexLimit ? "\n" + String(localized: "… (\(ByteSize.format(x.count - hexLimit)) 더)") : "")
        }
        return p
    }

    private static let tokenColors: [JSONToken.Kind: NSColor] = [
        .key: NSColor(named: "JSONKey") ?? .textColor,
        .string: NSColor(named: "JSONString") ?? .textColor,
        .number: NSColor(named: "JSONNumber") ?? .textColor,
        .keyword: NSColor(named: "JSONKeyword") ?? .textColor,
    ]

    static func highlighted(_ s: String, _ tokens: [JSONToken]) -> NSAttributedString {
        let a = CodeTextView.base(s)
        a.beginEditing()
        for t in tokens { a.addAttribute(.foregroundColor, value: tokenColors[t.kind] ?? NSColor.textColor, range: t.range) }
        a.endEditing()
        return a
    }

    /// UTF-8 바이트 기준 2MB로 자르되 줄 경계에서 끊는다.
    nonisolated static func capped(_ s: String) -> (String, Bool) {
        let u = s.utf8
        guard u.count > textLimit else { return (s, false) }
        var end = u.index(u.startIndex, offsetBy: textLimit)
        if let nl = u[..<end].lastIndex(of: 10) { end = nl }
        return (String(decoding: Array(u[..<end]), as: UTF8.self), true)
    }

    private nonisolated static func hex(_ d: Data) -> String {
        let bytes = [UInt8](d)
        return stride(from: 0, to: bytes.count, by: 16).map { off in
            let row = bytes[off..<min(off + 16, bytes.count)]
            let hex = row.enumerated().map { String(format: "%02x", $1) + ($0 == 7 ? "  " : " ") }.joined()
            let ascii = String(row.map { $0 >= 0x20 && $0 < 0x7f ? Character(UnicodeScalar($0)) : "." })
            return String(format: "%08x  ", off) + hex.padding(toLength: 49, withPad: " ", startingAt: 0) + " |" + ascii + "|"
        }.joined(separator: "\n")
    }

    @ViewBuilder private func content(_ l: Loaded) -> some View {
        switch l.decoded {
        case .empty: Text("(없음)").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .json:
            switch mode {
            case .pretty: CodeBody(text: l.display, truncated: l.truncated)
            case .raw: CodeBody(text: l.raw ?? l.display, truncated: l.rawTruncated)
            }
        case .text: CodeBody(text: l.display, truncated: l.truncated)
        case .html: HTMLBody(source: l.display, truncated: l.truncated)
        case .image:
            if let img = l.image, let rep = img.representations.first {
                VStack {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text("\(rep.pixelsWide) × \(rep.pixelsHigh) px").font(.caption).foregroundStyle(.secondary).padding(4)
                }
            } else { CodeBody(text: l.display, truncated: false) }
        case .binary: CodeBody(text: l.display, truncated: false)
        }
    }
}

/// `CodeTextView` + 2MB 컷 안내. 줄바꿈은 설정을 따른다.
struct CodeBody: View {
    let text: NSAttributedString
    let truncated: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CodeTextView(text: text, wrap: model.settings.wrapLongLines)
                .frame(maxWidth: .infinity, maxHeight: .infinity)  // NSScrollView의 fitting 크기(문서 높이)로 커지지 않게
            if truncated { Text("… (2MB까지만 표시)").foregroundStyle(.secondary).padding(6) }
        }
    }
}

private struct HTMLBody: View {
    let source: NSAttributedString
    let truncated: Bool
    @State private var showSource = false
    @State private var blocked = false

    var body: some View {
        VStack(spacing: 0) {
            Toggle("소스", isOn: $showSource).toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            if blocked { Text("미리보기를 안전하게 차단할 수 없어 소스만 표시합니다").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6) }
            if showSource || blocked { CodeBody(text: source, truncated: truncated) } else { HTMLPreview(html: source.string) { blocked = true } }
        }
    }
}
