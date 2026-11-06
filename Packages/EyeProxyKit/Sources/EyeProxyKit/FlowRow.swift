import EyeProxyCore
import Foundation

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
    }
}
