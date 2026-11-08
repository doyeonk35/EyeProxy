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

    @Test func noTimeoutStillCompletes() async throws {
        let origin = TestOrigin { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data("ok".utf8)) }
        let originPort = try await origin.start()
        let ca = try CertificateAuthority.generate()
        let server = ProxyServer(configuration: .init(bindHost: "127.0.0.1", port: 0), certificateAuthority: ca, interceptors: .init())
        let port = try await server.start()
        let request = FlowRequest(method: "GET", scheme: "http", host: "127.0.0.1", port: originPort, path: "/", headers: [], body: Data())
        let response = try await ComposeClient(proxyPort: port, trustRootDER: ca.certificateDER).send(request, timeout: nil)
        #expect(response.status == 200 && response.body == Data("ok".utf8))
        await server.stop()
        await origin.stop()
    }

    /// 복호화(MITM)되는 HTTPS: EyeProxy 루트를 신뢰하면 통과, 다른 루트면 거부(§5.8 신뢰 경로).
    /// URLSession은 루프백 https에는 프록시를 쓰지 않으므로(실측) 루프백이 아닌 이름으로 보내고 프록시 안에서 원 서버로 돌린다.
    @Test(arguments: [true, false]) func httpsThroughDecryptingProxy(trustsProxyRoot: Bool) async throws {
        let ca = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try ca.leaf(for: "localhost")) { r in FlowResponse(status: 200, reason: "OK", headers: [], body: Data("tls \(r.path)".utf8)) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(bindHost: "127.0.0.1", port: 0, sslPolicy: .init(patterns: []), upstreamTrustRootsDER: [ca.certificateDER]),
                                 certificateAuthority: ca,
                                 interceptors: .init(request: [RouteTo(port: originPort)], connect: [AlwaysDecrypt()]))
        let port = try await server.start()
        var events = server.events.makeAsyncIterator()
        let root = trustsProxyRoot ? ca.certificateDER : try CertificateAuthority.generate().certificateDER
        let request = FlowRequest(method: "GET", scheme: "https", host: "compose.example.test", port: 443, path: "/s", headers: [], body: Data())
        let client = ComposeClient(proxyPort: port, trustRootDER: root)
        if trustsProxyRoot {
            let response = try await client.send(request, timeout: 10)
            #expect(response.status == 200 && response.body == Data("tls /s".utf8))
            // 프록시를 거쳐(복호화되어) 기록됐다.
            guard case .requestStarted(let flow) = await events.next() else { Issue.record("no requestStarted"); return }
            #expect(flow.isDecrypted && flow.request.host == "compose.example.test" && flow.request.path == "/s")
        } else {
            // 신뢰 평가 실패 → cancelAuthenticationChallenge → URLError.cancelled(다른 실패와 구분).
            let error = await #expect(throws: URLError.self) { try await client.send(request, timeout: 10) }
            #expect(error?.code == .cancelled)
        }
        await server.stop()
        await origin.stop()
    }
}

/// 프록시 안에서 원 서버(localhost:port)로 돌린다(Map Remote와 같은 방식).
private struct RouteTo: RequestInterceptor {
    let port: Int
    func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision {
        var r = request
        (r.host, r.port) = ("localhost", port)
        return .continue(r)
    }
}

private struct AlwaysDecrypt: ConnectInterceptor {
    func intercept(host: String, port: Int, context: ConnectContext) async -> ConnectVerdict { ConnectVerdict(action: .decrypt) }
}
