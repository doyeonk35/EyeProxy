import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct BodyView: View {
    let data: Data
    let headers: [HTTPHeader]

    /// 디코드 결과와 화면용 문자열(2MB 컷·hex 덤프)을 한 번만 만든다.
    private struct Loaded {
        let decoded: DecodedBody
        let display: String
        let truncated: Bool
        let image: NSImage?
    }
    @State private var loaded: Loaded?

    private var encoding: String? {
        headers.first { $0.name.caseInsensitiveCompare("Content-Encoding") == .orderedSame }?.value
    }

    private var summary: String {
        String(localized: "원본 \(data.count) bytes") + (encoding.map { String(localized: " · Content-Encoding: \($0)") } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: summary).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
            Divider()
            if let loaded { content(loaded) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        // 디코드는 본문이 바뀔 때만 (세션 이벤트마다 다시 하지 않음), 메인 밖에서.
        .task(id: data.count) {
            let (b, h) = (data, headers)
            let (d, display, truncated) = await Task.detached { Self.prepare(b, h) }.value
            var image: NSImage?
            if case .image(let img) = d { image = NSImage(data: img) }
            loaded = Loaded(decoded: d, display: display, truncated: truncated, image: image)
        }
    }

    private nonisolated static let textLimit = 2_000_000
    private nonisolated static let hexLimit = 64 * 1024

    private nonisolated static func prepare(_ body: Data, _ headers: [HTTPHeader]) -> (DecodedBody, String, Bool) {
        let d = BodyDecoder.decode(body: body, headers: headers)
        switch d {
        case .empty: return (d, "", false)
        case .json(let s, _), .text(let s), .html(let s):
            let (t, cut) = capped(s)
            return (d, t, cut)
        case .image(let x), .binary(let x):
            return (d, hex(x.prefix(hexLimit)) + (x.count > hexLimit ? "\n" + String(localized: "… (\(x.count - hexLimit) bytes 더)") : ""), false)
        }
    }

    /// UTF-8 바이트 기준 2MB로 자르되 줄 경계에서 끊는다.
    private nonisolated static func capped(_ s: String) -> (String, Bool) {
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
        case .json(let pretty, _): JSONBody(pretty: pretty, display: l.display, truncated: l.truncated)
        case .text: MonoText(text: l.display, truncated: l.truncated)
        case .html: HTMLBody(html: l.display, truncated: l.truncated)
        case .image:
            if let img = l.image, let rep = img.representations.first {
                VStack {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text("\(rep.pixelsWide) × \(rep.pixelsHigh) px").font(.caption).foregroundStyle(.secondary).padding(4)
                }
            } else { MonoText(text: l.display, truncated: false) }
        case .binary: MonoText(text: l.display, truncated: false)
        }
    }
}

/// 256KB 이하는 SwiftUI Text, 그 이상은 NSTextView(읽기 전용·선택 가능)로 그린다.
struct MonoText: View {
    let text: String
    let truncated: Bool
    private static let swiftUILimit = 256_000

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if text.utf8.count > Self.swiftUILimit {
                LargeText(text: text)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            if truncated { Text("… (2MB까지만 표시)").foregroundStyle(.secondary).padding(6) }
        }
    }
}

private struct LargeText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.string = text
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

private struct JSONBody: View {
    enum Mode { case pretty, tree }
    let pretty: String
    let display: String
    let truncated: Bool
    @State private var mode = Mode.pretty
    @State private var tree: [JSONNode]?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("Pretty").tag(Mode.pretty)
                Text("Tree").tag(Mode.tree)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().padding(6)
            switch mode {
            case .pretty: MonoText(text: display, truncated: truncated)
            case .tree:
                if let tree { JSONTreeView(nodes: tree) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
        .task(id: mode) {
            guard mode == .tree, tree == nil else { return }
            let p = pretty
            tree = await Task.detached { JSONNode.parse(p) }.value
        }
    }
}

private struct HTMLBody: View {
    let html: String
    let truncated: Bool
    @State private var source = false
    @State private var blocked = false

    var body: some View {
        VStack(spacing: 0) {
            Toggle("소스", isOn: $source).toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            if blocked { Text("미리보기를 안전하게 차단할 수 없어 소스만 표시합니다").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6) }
            if source || blocked { MonoText(text: html, truncated: truncated) } else { HTMLPreview(html: html) { blocked = true } }
        }
    }
}
