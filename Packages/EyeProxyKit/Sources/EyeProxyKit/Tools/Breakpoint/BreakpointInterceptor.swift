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
        case .executeRequest(var edited):
            // 목적지만 고치고 Host 헤더는 그대로 뒀으면 새 목적지에 맞춘다(사용자가 고친 Host 헤더는 둔다).
            if (edited.scheme, edited.host, edited.port) != (request.scheme, request.host, request.port),
               edited.header("Host") == request.header("Host") { edited.syncHostHeader() }
            context.annotate(ToolMark.annotation(.breakpoint, detail: "편집됨"))
            return .continue(edited)
        case .drop:
            context.annotate(ToolMark.annotation(.breakpoint, detail: "연결 끊김"))
            return .drop
        case .abort(let status):
            context.annotate(ToolMark.annotation(.breakpoint, detail: "중단 \(status)"))
            // 만든 응답도 응답 체인을 지나므로, 응답 단계에서 멈출 규칙이 있을 때만 건너뛰기 표시를 남긴다.
            if self.rule(for: request, phase: .response) != nil { await center.markAborted(context.id) }
            return .respond(Self.abortResponse(status))
        }
    }

    public func intercept(_ response: FlowResponse, for request: FlowRequest, context: FlowContext) async -> ResponseDecision {
        guard let rule = rule(for: request, phase: .response), await !center.consumeAborted(context.id) else { return .continue(response) }
        let item = PausedItem(flowID: context.id, phase: .response, ruleName: rule.name, request: request, response: response)
        switch await center.pause(item) {
        case .continueOriginal, .executeRequest: return .continue(response)
        case .executeResponse(let edited):
            context.annotate(ToolMark.annotation(.breakpoint, detail: "편집됨"))
            return .continue(edited)
        case .drop:
            context.annotate(ToolMark.annotation(.breakpoint, detail: "연결 끊김"))
            return .drop
        case .abort(let status):
            context.annotate(ToolMark.annotation(.breakpoint, detail: "중단 \(status)"))
            return .continue(Self.abortResponse(status))
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
