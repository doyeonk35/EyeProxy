import EyeProxyCore

/// 캐시 검증·만료 헤더를 지우고 `no-cache`를 강제한다(§5.6). 이름 비교는 대소문자 무시.
public struct NoCachingInterceptor: RequestInterceptor, ResponseInterceptor {
    public init() {}

    private static func rewrite(_ headers: [HTTPHeader], remove: Set<String>, add: [HTTPHeader]) -> [HTTPHeader] {
        let drop = remove.union(add.map { $0.name.lowercased() })
        return headers.filter { !drop.contains($0.name.lowercased()) } + add
    }

    public func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision {
        var r = request
        r.headers = Self.rewrite(r.headers, remove: ["if-modified-since", "if-none-match"],
                                 add: [HTTPHeader(name: "Pragma", value: "no-cache"), HTTPHeader(name: "Cache-Control", value: "no-cache")])
        return .continue(r)
    }

    public func intercept(_ response: FlowResponse, for request: FlowRequest, context: FlowContext) async -> ResponseDecision {
        var r = response
        r.headers = Self.rewrite(r.headers, remove: ["expires", "last-modified", "etag"],
                                 add: [HTTPHeader(name: "Expires", value: "0"), HTTPHeader(name: "Cache-Control", value: "no-cache")])
        return .continue(r)
    }
}
