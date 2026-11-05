import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct BodyView: View {
    let data: Data
    let headers: [HTTPHeader]
    @State private var decoded: DecodedBody?

    private var encoding: String? {
        headers.first { $0.name.caseInsensitiveCompare("Content-Encoding") == .orderedSame }?.value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("원본 \(data.count) bytes") + Text(encoding.map { " · Content-Encoding: \($0)" } ?? ""))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
            Divider()
            if let decoded { content(decoded) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        // 디코드는 본문이 바뀔 때만 (세션 이벤트마다 다시 하지 않음), 메인 밖에서.
        .task(id: data.count) {
            let (b, h) = (data, headers)
            decoded = await Task.detached { BodyDecoder.decode(body: b, headers: h) }.value
        }
    }

    @ViewBuilder private func content(_ d: DecodedBody) -> some View {
        switch d {
        case .empty: Text("(없음)").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .json(let pretty): JSONBody(pretty: pretty)
        case .text(let s): MonoText(text: s)
        case .html(let s): HTMLBody(html: s)
        case .image(let data):
            if let img = NSImage(data: data), let rep = img.representations.first {
                VStack {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text("\(rep.pixelsWide) × \(rep.pixelsHigh) px").font(.caption).foregroundStyle(.secondary).padding(4)
                }
            } else { HexDump(data: data) }
        case .binary(let data): HexDump(data: data)
        }
    }
}

/// 큰 본문은 앞 2MB만 그린다.
struct MonoText: View {
    let text: String
    private static let limit = 2_000_000

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading) {
                Text(text.utf8.count > Self.limit ? String(text.prefix(Self.limit)) : text)
                if text.utf8.count > Self.limit { Text("… (2MB까지만 표시)").foregroundStyle(.secondary) }
            }
            .font(.system(.body, design: .monospaced)).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
}

private struct JSONBody: View {
    enum Mode { case pretty, tree }
    let pretty: String
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
            case .pretty: MonoText(text: pretty)
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
    @State private var source = false

    var body: some View {
        VStack(spacing: 0) {
            Toggle("소스", isOn: $source).toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            if source { MonoText(text: html) } else { HTMLPreview(html: html) }
        }
    }
}

private struct HexDump: View {
    let data: Data
    private static let limit = 64 * 1024

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(Self.dump(data.prefix(Self.limit)) + (data.count > Self.limit ? "\n… (\(data.count - Self.limit) bytes 더)" : ""))
                .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    static func dump(_ d: Data) -> String {
        let bytes = [UInt8](d)
        return stride(from: 0, to: bytes.count, by: 16).map { off in
            let row = bytes[off..<min(off + 16, bytes.count)]
            let hex = row.enumerated().map { String(format: "%02x", $1) + ($0 == 7 ? "  " : " ") }.joined()
            let ascii = String(row.map { $0 >= 0x20 && $0 < 0x7f ? Character(UnicodeScalar($0)) : "." })
            return String(format: "%08x  ", off) + hex.padding(toLength: 49, withPad: " ", startingAt: 0) + " |" + ascii + "|"
        }.joined(separator: "\n")
    }
}
