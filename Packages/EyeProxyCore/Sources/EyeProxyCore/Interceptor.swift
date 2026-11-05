import Foundation

public struct FlowContext: Sendable {
    public let id: FlowID
    public let clientAddress: String
    public init(id: FlowID, clientAddress: String) {
        self.id = id
        self.clientAddress = clientAddress
    }
}

public enum RequestDecision: Sendable {
    case `continue`(FlowRequest)
    case respond(FlowResponse)
}

public protocol RequestInterceptor: Sendable {
    func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision
}

public protocol ResponseInterceptor: Sendable {
    func intercept(_ response: FlowResponse, for request: FlowRequest, context: FlowContext) async -> FlowResponse
}

public struct InterceptorChain: Sendable {
    public var request: [any RequestInterceptor]
    public var response: [any ResponseInterceptor]

    public init(request: [any RequestInterceptor] = [], response: [any ResponseInterceptor] = []) {
        self.request = request
        self.response = response
    }

    /// 순서대로 실행하고 첫 `.respond`에서 중단한다.
    public func runRequest(_ r: FlowRequest, context: FlowContext) async -> RequestDecision {
        var current = r
        for interceptor in request {
            switch await interceptor.intercept(current, context: context) {
            case .continue(let next): current = next
            case .respond(let res): return .respond(res)
            }
        }
        return .continue(current)
    }

    public func runResponse(_ r: FlowResponse, for req: FlowRequest, context: FlowContext) async -> FlowResponse {
        var current = r
        for interceptor in response {
            current = await interceptor.intercept(current, for: req, context: context)
        }
        return current
    }
}
