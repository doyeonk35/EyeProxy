import EyeProxyCore
import Foundation

/// 일치하는 요청/응답을 멈추고 `BreakpointCenter`의 결정을 따른다.
public struct BreakpointInterceptor: RequestInterceptor, ResponseInterceptor {
    let rules: RuleTree<BreakpointRule>
    let center: BreakpointCenter

    public init(rules: RuleTree<BreakpointRule>, center: BreakpointCenter) {
        self.rules = rules
        self.center = center
    }

    public func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision {
        guard let rule = rule(for: request, phase: .request) else { return .continue(request) }
        let item = PausedItem(flowID: context.id, phase: .request, ruleName: rule.name, request: request)
        switch await center.pause(item) {
        case .continueOriginal, .executeResponse: return .continue(request)
        case .executeRequest(let edited):
            context.annotate(ToolMark.annotation(.breakpoint, detail: "편집됨"))
            return .continue(edited)
        case .drop: return .drop
        case .abort(let status): return .respond(Self.abortResponse(status))
        }
    }

    public func intercept(_ response: FlowResponse, for request: FlowRequest, context: FlowContext) async -> ResponseDecision {
        guard let rule = rule(for: request, phase: .response) else { return .continue(response) }
        let item = PausedItem(flowID: context.id, phase: .response, ruleName: rule.name, request: request, response: response)
        switch await center.pause(item) {
        case .continueOriginal, .executeRequest: return .continue(response)
        case .executeResponse(let edited):
            context.annotate(ToolMark.annotation(.breakpoint, detail: "편집됨"))
            return .continue(edited)
        case .drop: return .drop
        case .abort(let status): return .continue(Self.abortResponse(status))
        }
    }

    /// 그 단계가 켜진 첫 일치 규칙. 다른 단계 전용 규칙이 위에 있어도 가리지 않는다.
    private func rule(for request: FlowRequest, phase: BreakpointPhase) -> BreakpointRule? {
        rules.enabledRules.first { (phase == .request ? $0.onRequest : $0.onResponse) && $0.match.matches(request) }
    }

    static func abortResponse(_ status: Int) -> FlowResponse {
        FlowResponse(status: status, reason: status == 429 ? "Too Many Requests" : "Service Unavailable",
                     headers: [HTTPHeader(name: "Content-Length", value: "0")], body: Data())
    }
}
