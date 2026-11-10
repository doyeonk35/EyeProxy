import EyeProxyCore
import Foundation

/// 목록 Status 열. 오류 → failed, 응답과 완료 시각이 있으면 completed, 그 전엔 active.
public enum FlowState: Int, Comparable, Sendable {
    case active, completed, failed
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// 테이블 정렬용 값 스냅샷. 파생 키는 init에서 한 번만 계산한다.
public struct FlowRow: Identifiable, Sendable {
    public let flow: Flow
    public let number: Int
    public var id: FlowID { flow.id }
    public let method: String
    public let url: String
    public let host: String
    public let startedAt: Date
    /// 응답 있음 = status, 오류 = -2, 대기 = -1
    public let status: Int
    /// 응답 바디 바이트, 없으면 -1
    public let size: Int
    /// (completedAt - startedAt) * 1000 반올림, 미완 -1
    public let durationMS: Int
    public let state: FlowState
    public let requestSize: Int
    /// 응답 바디 바이트, 응답 없으면 0
    public let responseSize: Int
    public let isSSL: Bool
    /// 요청·응답을 바꾼 도구(중복 없이 처음 나온 순서)
    public let editedMarks: [ToolMark]
    /// 정렬용: editedMarks의 raw를 ", "로 연결
    public let edited: String

    public init(flow: Flow, number: Int) {
        self.flow = flow
        self.number = number
        method = flow.request.method
        url = flow.request.url
        host = flow.request.host
        startedAt = flow.startedAt
        status = flow.response?.status ?? (flow.error == nil ? -1 : -2)
        size = flow.response?.body.count ?? -1
        durationMS = flow.completedAt.map { Int((($0.timeIntervalSince(flow.startedAt)) * 1000).rounded()) } ?? -1
        state = flow.error != nil ? .failed : (flow.response != nil && flow.completedAt != nil) ? .completed : .active
        requestSize = flow.request.body.count
        responseSize = flow.response?.body.count ?? 0
        isSSL = flow.isDecrypted
        var marks: [ToolMark] = []
        for m in flow.annotations.compactMap(ToolMark.mark) where !marks.contains(m) { marks.append(m) }
        editedMarks = marks
        edited = marks.map(\.rawValue).joined(separator: ", ")
    }

    /// 목록 Time 열(Advanced ▸ Use 24-Hour Time · Display Full Time Format). 로캘 무관:
    /// `14:03:05.123` / `02:03:05.123 PM`, 전체 형식이면 앞에 `2026-11-10 `, 뒤에 ` GMT+9`.
    public static func timeFormat(use24Hour: Bool, full: Bool, timeZone: TimeZone = .current) -> Date.VerbatimFormatStyle {
        // FormatString은 서로 끼워 넣을 수 없어 네 가지를 그대로 적는다.
        let format: Date.FormatString = switch (use24Hour, full) {
        case (true, false):
            "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))"
        case (false, false):
            "\(hour: .twoDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3)) \(dayPeriod: .standard(.abbreviated))"
        case (true, true):
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3)) \(timeZone: .localizedGMT(.short))"
        case (false, true):
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3)) \(dayPeriod: .standard(.abbreviated)) \(timeZone: .localizedGMT(.short))"
        }
        return Date.VerbatimFormatStyle(format: format, timeZone: timeZone, calendar: Calendar(identifier: .gregorian))
    }

    /// 목록 Duration 열(Proxyman 형식): "266 ms" / "59.26 s" / "2.01 min", 미완(-1) "-".
    public static func durationText(ms: Int) -> String {
        if ms < 0 { return "-" }
        if ms < 1000 { return "\(ms) ms" }
        if ms < 60_000 { return String(format: "%.2f s", Double(ms) / 1000) }
        return String(format: "%.2f min", Double(ms) / 60_000)
    }
}

extension Flow {
    /// 상세 헤더에 보일 도구 주석. 숨김·미기록 표시는 뺀다.
    public var annotationLabels: [String] {
        annotations.compactMap {
            switch $0 {
            case .tool(let label): label
            case .originalURL(let url): "원래 URL: \(url)"
            case .sentURL(let url): "실제 전송 URL: \(url)"
            case .hidden, .unrecorded: nil
            }
        }
    }
}
