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

public struct InterceptorChain: Sendable {
    public var request: [any RequestInterceptor]
    public var response: [any ResponseInterceptor]

    public init(request: [any RequestInterceptor] = [], response: [any ResponseInterceptor] = []) {
        self.request = request
        self.response = response
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
