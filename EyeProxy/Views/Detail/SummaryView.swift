import EyeProxyCore
import EyeProxyKit
import SwiftUI

/// 요청 패널 Summary 탭의 행(스펙 §7). 응답이 없거나 실패한 흐름도 요청 패널은 늘 있으니 그 탭에 둔다.
@MainActor enum SummaryView {
    static func rows(_ flow: Flow, tab: SessionTab) -> [HTTPHeader] {
        let row = FlowRow(flow: flow, number: 0)  // 목록 열과 같은 파생 값(소요 시간·크기·SSL·Edited)
        let request = flow.request
        let status = flow.response.map { "\($0.status) \($0.reason)" } ?? flow.error.map { "오류: \($0)" } ?? "응답 대기 중"
        // Map Remote: 원래 URL은 주석(아니면 표시 URL), 실제 전송 URL은 주석(아니면 표시 URL). 둘 다 없으면 적용 안 됨.
        var original: String?, sent: String?
        for a in flow.annotations {
            if case .originalURL(let u) = a { original = u }
            if case .sentURL(let u) = a { sent = u }
        }
        let mapped = original != nil || sent != nil
        let highlight = tab.session.highlights[flow.id].map { h in
            [h.color?.rawValue.capitalized, h.strikethrough ? "취소선" : nil].compactMap { $0 }.joined(separator: " · ")
        }
        let pairs: [(String, String)] = [
            ("URL", request.url),
            ("메서드", request.method),
            ("상태", status),
            ("클라이언트", tab.clientName(for: flow).isEmpty ? "-" : tab.clientName(for: flow)),
            ("시작 시각", flow.startedAt.formatted(Self.timeFormat)),
            ("소요 시간", FlowRow.durationText(ms: row.durationMS)),
            ("요청 크기", ByteSize.format(row.requestSize)),
            ("응답 크기", flow.response == nil ? "-" : ByteSize.format(row.responseSize)),
            ("SSL", row.isSSL ? "복호화함" : request.scheme == "http" && !flow.isTunnel ? "평문 HTTP" : "복호화 안 함"),
            ("적용된 도구", row.edited.isEmpty ? "-" : row.edited),
            ("원래 URL", mapped ? original ?? request.url : "-"),
            ("실제 전송 URL", mapped ? sent ?? request.url : "-"),
            ("코멘트", tab.session.comments[flow.id] ?? "-"),
            ("Highlight", highlight ?? "-"),
        ]
        return pairs.map { HTTPHeader(name: $0.0, value: $0.1) }
    }

    private static let timeFormat = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
        timeZone: .current, calendar: .current)
}
