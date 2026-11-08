import EyeProxyCore
import Foundation

/// Breakpoint 편집기 Raw 탭의 템플릿. EyeProxy 전용 형식(`breakpoint-templates.json`).
/// 요청 템플릿 = Method·URL·Headers, 응답 템플릿 = Status·Headers.
public struct BreakpointTemplate: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: BreakpointPhase
    public var method: String?
    public var url: String?
    public var status: Int?
    public var headers: [HTTPHeader]

    public init(id: String = String(UUID().uuidString.prefix(8)), name: String = "Untitled", kind: BreakpointPhase,
                method: String? = nil, url: String? = nil, status: Int? = nil, headers: [HTTPHeader] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.method = method
        self.url = url
        self.status = status
        self.headers = headers
    }

    /// 값이 있는 칸만 바꾸고 헤더는 통째로 바꾼다. 읽을 수 없는 URL은 무시한다.
    public func apply(to request: FlowRequest) -> FlowRequest {
        var r = request
        if let method, !method.isEmpty { r.method = method }
        if let url, let c = URLComponents(string: url), let host = c.host, !host.isEmpty {
            r.scheme = c.scheme?.lowercased() ?? r.scheme
            r.host = host
            r.port = c.port ?? (r.scheme == "http" ? 80 : 443)
            r.path = (c.percentEncodedPath.isEmpty ? "/" : c.percentEncodedPath) + (c.percentEncodedQuery.map { "?" + $0 } ?? "")
        }
        r.headers = headers
        return r
    }

    /// 상태가 바뀌면 reason은 비운다(전송 시 NIO가 표준 문구를 채운다).
    public func apply(to response: FlowResponse) -> FlowResponse {
        var r = response
        if let status, status != r.status {
            r.status = status
            r.reason = ""
        }
        r.headers = headers
        return r
    }
}
