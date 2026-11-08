import EyeProxyCore

/// 캐시 검증·만료 헤더를 지우고 `no-cache`를 강제한다(§5.6). 이름 비교는 대소문자 무시.
public struct NoCachingInterceptor: RequestInterceptor, ResponseInterceptor {
    public init() {}

    private static func rewrite(_ headers: [HTTPHeader], remove: Set<String>, add: [HTTPHeader]) -> [HTTPHeader] {
        let drop = remove.union(add.map { $0.name.lowercased() })
        return headers.filter { !drop.contains($0.name.lowercased()) } + add
    }

    /// 요청 쪽 규칙. Repeat의 No-Cache 옵션(§5.8)도 이것을 쓴다.
    public static func noCache(_ request: FlowRequest) -> FlowRequest {
        var r = request
        r.headers = rewrite(r.headers, remove: ["if-modified-since", "if-none-match"],
                            add: [HTTPHeader(name: "Pragma", value: "no-cache"), HTTPHeader(name: "Cache-Control", value: "no-cache")])
        return r
    }

    public func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision {
        .continue(Self.noCache(request))
    }

    public func intercept(_ response: FlowResponse, for request: FlowRequest, context: FlowContext) async -> ResponseDecision {
        var r = response
        r.headers = Self.rewrite(r.headers, remove: ["expires", "last-modified", "etag"],
                                 add: [HTTPHeader(name: "Expires", value: "0"), HTTPHeader(name: "Cache-Control", value: "no-cache")])
        return .continue(r)
    }
}
