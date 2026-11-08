import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

@Suite(.timeLimit(.minutes(1)))
struct ComposeClientTests {
    @Test func composeGoesThroughProxy() async throws {
        let origin = TestOrigin { r in FlowResponse(status: 200, reason: "OK", headers: [.init(name: "X-Origin", value: "1")],
                                                    body: Data("\(r.method) \(r.path) \(String(decoding: r.body, as: UTF8.self))".utf8)) }
        let originPort = try await origin.start()
        let ca = try CertificateAuthority.generate()
        let server = ProxyServer(configuration: .init(bindHost: "127.0.0.1", port: 0), certificateAuthority: ca, interceptors: .init())
        let port = try await server.start()
        var events = server.events.makeAsyncIterator()
        let request = FlowRequest(method: "POST", scheme: "http", host: "127.0.0.1", port: originPort, path: "/x?y=1",
                                  headers: [.init(name: "Content-Type", value: "text/plain")], body: Data("hi".utf8))
        let response = try await ComposeClient(proxyPort: port, trustRootDER: ca.certificateDER).send(request, timeout: 10)
        #expect(response.status == 200 && response.header("X-Origin") == "1" && response.body == Data("POST /x?y=1 hi".utf8))
        guard case .requestStarted(let flow) = await events.next() else { Issue.record("no requestStarted"); return }
        #expect(flow.request.path == "/x?y=1" && flow.request.method == "POST")
        // 사용자가 넣지 않은 캐시 헤더를 URLSession이 붙이면 Repeat No-Cache 스위치가 의미 없어진다.
        #expect(flow.request.header("Cache-Control") == nil && flow.request.header("Pragma") == nil)
        await server.stop()
        await origin.stop()
    }

    @Test func repeatNoCacheRewritesRequestHeaders() {
        let r = FlowRequest(method: "GET", scheme: "http", host: "a", port: 80, path: "/",
                            headers: [.init(name: "If-None-Match", value: "x"), .init(name: "Accept", value: "*/*")], body: Data())
        #expect(NoCachingInterceptor.noCache(r).headers == [.init(name: "Accept", value: "*/*"), .init(name: "Pragma", value: "no-cache"),
                                                           .init(name: "Cache-Control", value: "no-cache")])
    }
}
