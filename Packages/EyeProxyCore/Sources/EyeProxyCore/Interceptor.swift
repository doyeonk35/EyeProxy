import Foundation

public struct FlowContext: Sendable {
    public let id: FlowID
    public let clientAddress: String
    public let clientPort: Int?
    private let annotateHandler: @Sendable (FlowAnnotation) -> Void

    public init(id: FlowID, clientAddress: String, clientPort: Int? = nil, annotate: @escaping @Sendable (FlowAnnotation) -> Void = { _ in }) {
        self.id = id
        self.clientAddress = clientAddress
        self.clientPort = clientPort
        self.annotateHandler = annotate
    }

    /// 이 흐름에 주석을 단다(`.annotated` 이벤트로 즉시 나간다).
    public func annotate(_ a: FlowAnnotation) { annotateHandler(a) }
}

public enum RequestDecision: Sendable {
    case `continue`(FlowRequest)
    case respond(FlowResponse)
    /// 응답 없이 클라이언트 연결을 끊는다.
    case drop
}

public enum ResponseDecision: Sendable {
    case `continue`(FlowResponse)
    case drop
}

public protocol RequestInterceptor: Sendable {
    func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision
}

public protocol ResponseInterceptor: Sendable {
    func intercept(_ response: FlowResponse, for request: FlowRequest, context: FlowContext) async -> ResponseDecision
}

public struct ConnectContext: Sendable {
    public let clientAddress: String
    public let clientPort: Int?

    public init(clientAddress: String, clientPort: Int?) {
        self.clientAddress = clientAddress
        self.clientPort = clientPort
    }
}

public enum ConnectAction: Sendable, Equatable {
    /// SSL Proxying 목록대로.
    case useDefault, decrypt, tunnel
    /// 응답 없이 클라이언트 연결을 끊는다.
    case drop
}

/// 터널 바이트 지연. 각 청크를 `latencyMS + 크기/속도`만큼 늦춰 순서대로 전달한다. 속도 nil = 무제한.
public struct TunnelShaping: Sendable, Equatable {
    public var latencyMS: Int
    public var downBytesPerSecond: Int?
    public var upBytesPerSecond: Int?
    /// 읽기만 하고 전달하지 않는다.
    public var blackhole: Bool

    public init(latencyMS: Int = 0, downBytesPerSecond: Int? = nil, upBytesPerSecond: Int? = nil, blackhole: Bool = false) {
        self.latencyMS = latencyMS
        self.downBytesPerSecond = downBytesPerSecond
        self.upBytesPerSecond = upBytesPerSecond
        self.blackhole = blackhole
    }
}

public struct ConnectVerdict: Sendable, Equatable {
    public var action: ConnectAction
    /// false면 이벤트를 전혀 내지 않는 터널(복호화 판정이어도).
    public var record: Bool
    /// 터널에만 적용된다.
    public var shaping: TunnelShaping?
    /// 복호화한 연결 안의 모든 흐름에 `.tool(note)` 주석.
    public var note: String?

    public init(action: ConnectAction = .useDefault, record: Bool = true, shaping: TunnelShaping? = nil, note: String? = nil) {
        self.action = action
        self.record = record
        self.shaping = shaping
        self.note = note
    }
}

public protocol ConnectInterceptor: Sendable {
    func intercept(host: String, port: Int, context: ConnectContext) async -> ConnectVerdict
}

public struct InterceptorChain: Sendable {
    public var request: [any RequestInterceptor]
    public var response: [any ResponseInterceptor]
    public var connect: [any ConnectInterceptor]

    public init(request: [any RequestInterceptor] = [], response: [any ResponseInterceptor] = [], connect: [any ConnectInterceptor] = []) {
        self.request = request
        self.response = response
        self.connect = connect
    }

    /// 모두 실행해 합친다: `action`은 처음 나온 non-`.useDefault`, `record`는 모두 AND, `shaping`·`note`는 처음 non-nil.
    public func runConnect(host: String, port: Int, context: ConnectContext) async -> ConnectVerdict {
        var merged = ConnectVerdict()
        for interceptor in connect {
            let v = await interceptor.intercept(host: host, port: port, context: context)
            if merged.action == .useDefault { merged.action = v.action }
            merged.record = merged.record && v.record
            merged.shaping = merged.shaping ?? v.shaping
            merged.note = merged.note ?? v.note
        }
        return merged
    }

    /// 순서대로 실행하고 첫 `.respond`·`.drop`에서 중단한다.
    /// `request`는 중단 시점까지 앞 단계들이 고친 요청이다(`.respond` 응답이 응답 체인에 갈 때 이것과 짝지어진다).
    public func runRequest(_ r: FlowRequest, context: FlowContext) async -> (decision: RequestDecision, request: FlowRequest) {
        var current = r
        for interceptor in request {
            switch await interceptor.intercept(current, context: context) {
            case .continue(let next): current = next
            case .respond(let res): return (.respond(res), current)
            case .drop: return (.drop, current)
            }
        }
        return (.continue(current), current)
    }

    /// 순서대로 실행하고 첫 `.drop`에서 중단한다.
    public func runResponse(_ r: FlowResponse, for req: FlowRequest, context: FlowContext) async -> ResponseDecision {
        var current = r
        for interceptor in response {
            switch await interceptor.intercept(current, for: req, context: context) {
            case .continue(let next): current = next
            case .drop: return .drop
            }
        }
        return .continue(current)
    }
}
