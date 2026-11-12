import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

/// 상세 머리(스펙 §7·§10): 왼쪽에 메서드 알약 위·상태 알약 아래, 오른쪽에 전체 URL을 여러 줄 모노 글꼴로
/// (스킴 회색·호스트 파랑·경로와 쿼리 초록). 복사·cURL 버튼은 그대로.
struct FlowHeaderBar: View {
    @Environment(SessionTab.self) private var tab
    let flow: Flow

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 4) {
                    MethodTag(method: flow.request.method)
                    statusPill
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 4) {
                    Text(urlText)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !flow.annotationLabels.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(flow.annotationLabels.enumerated()), id: \.offset) { _, label in
                                Text(label).modifier(Capsuled(color: .secondary, selected: false))
                            }
                        }
                    }
                }
                Button("복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(flow.request.url, forType: .string)
                }
                Button("cURL") { tab.copyCurl(flow.id) }
            }
            .buttonStyle(.accessoryBar)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
        }
    }

    /// `206 Partial Content`처럼 코드+사유, 응답 전이면 Active, 실패면 Failed.
    private var statusPill: some View {
        Group {
            if let r = flow.response {
                Text(verbatim: "\(r.status) \(r.reason)").modifier(Capsuled(color: FlowColors.status(flow), selected: false))
            } else if flow.error != nil {
                Text(verbatim: "Failed").modifier(Capsuled(color: FlowColors.state(.failed), selected: false))
            } else {
                Text(verbatim: "Active").modifier(Capsuled(color: FlowColors.state(.active), selected: false))
            }
        }
    }

    private static let hostColor = adaptive(0x2f6fe0, 0x6ea2ff)
    private static let pathColor = adaptive(0x1f9d55, 0x4cc38a)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let v = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
        })
    }

    private var urlText: AttributedString {
        let p = URLParts(flow.request)
        func part(_ s: String, _ color: Color, bold: Bool = false) -> AttributedString {
            var a = AttributedString(s)
            a.foregroundColor = color
            if bold { a.inlinePresentationIntent = .stronglyEmphasized }
            return a
        }
        return part(p.scheme, .secondary) + part(p.host, Self.hostColor, bold: true) + part(p.port, .secondary) + part(p.rest, Self.pathColor)
    }
}
