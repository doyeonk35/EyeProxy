import EyeProxyCore
import EyeProxyKit
import SwiftUI

/// 상세 상단의 접히는 요약(스펙 §7 Summary). 응답이 없거나 실패한 흐름도 보이도록 패널 탭이 아니라 머리글 아래에 둔다.
struct SummaryView: View {
    @Environment(AppModel.self) private var model
    let flow: Flow
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            DisclosureGroup("요약", isExpanded: $expanded) {
                KeyValueTable(rows: rows, emptyTitle: "").frame(height: 220)
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            Divider()
        }
    }

    private var rows: [HTTPHeader] {
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
        let highlight = model.session.highlights[flow.id].map { h in
            [h.color?.rawValue.capitalized, h.strikethrough ? "취소선" : nil].compactMap { $0 }.joined(separator: " · ")
        }
        let pairs: [(String, String)] = [
            ("URL", request.url),
            ("메서드", request.method),
            ("상태", status),
            ("클라이언트", client),
            ("시작 시각", flow.startedAt.formatted(Self.timeFormat)),
            ("소요 시간", FlowRow.durationText(ms: row.durationMS)),
            ("요청 크기", ByteSize.format(row.requestSize)),
            ("응답 크기", flow.response == nil ? "-" : ByteSize.format(row.responseSize)),
            ("SSL", row.isSSL ? "복호화함" : "아니요"),
            ("적용된 도구", row.edited.isEmpty ? "-" : row.edited),
            ("원래 URL", mapped ? original ?? request.url : "-"),
            ("실제 전송 URL", mapped ? sent ?? request.url : "-"),
            ("코멘트", model.session.comments[flow.id] ?? "-"),
            ("Highlight", highlight ?? "-"),
        ]
        return pairs.map { HTTPHeader(name: $0.0, value: $0.1) }
    }

    /// 목록 Client 열과 같은 출처: 프로세스 귀속 → 기기 이름 → 주소.
    private var client: String {
        if let identity = model.processes.attribution[flow.id] { return identity.displayName(runtimes: model.simulatorRuntimes) }
        return model.devices.devices.first { $0.address == flow.clientAddress }?.displayName ?? flow.clientAddress
    }

    private static let timeFormat = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
        timeZone: .current, calendar: .current)
}
