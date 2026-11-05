import Foundation
import Testing
@testable import EyeProxyCore

struct AddHeader: RequestInterceptor { let v: String
    func intercept(_ r: FlowRequest, context: FlowContext) async -> RequestDecision { var r = r; r.headers.append(.init(name: "X-T", value: v)); return .continue(r) } }
struct ShortCircuit: RequestInterceptor {
    func intercept(_ r: FlowRequest, context: FlowContext) async -> RequestDecision { .respond(FlowResponse(status: 418, reason: "teapot", headers: [], body: Data())) } }

@Test func requestInterceptorsRunInOrderAndStopAtRespond() async {
    let chain = InterceptorChain(request: [AddHeader(v: "1"), ShortCircuit(), AddHeader(v: "2")])
    let ctx = FlowContext(id: FlowID(), clientAddress: "127.0.0.1")
    guard case .respond(let res) = await chain.runRequest(.get("http://a/x"), context: ctx) else { Issue.record("expected respond"); return }
    #expect(res.status == 418)
}
@Test func requestURLOmitsDefaultPort() {
    #expect(FlowRequest(method: "GET", scheme: "https", host: "a", port: 443, path: "/p?q=1", headers: [], body: Data()).url == "https://a/p?q=1")
    #expect(FlowRequest(method: "GET", scheme: "http", host: "a", port: 8080, path: "/", headers: [], body: Data()).url == "http://a:8080/")
}
@Test func headerLookupIsCaseInsensitive() {
    #expect(FlowRequest.get("http://a/").with(headers: [.init(name: "Content-Type", value: "x")]).header("content-type") == "x")
}
