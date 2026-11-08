import Foundation
import Testing
import NIOSSL
@testable import EyeProxyCore

private struct MarkResponse: ResponseInterceptor {
    func intercept(_ response: FlowResponse, for request: FlowRequest, context: FlowContext) async -> ResponseDecision {
        var r = response
        r.headers.append(.init(name: "X-Modified", value: "1"))
        return .continue(r)
    }
}

/// 다른 이벤트(터널 종료 등)는 건너뛰고 다음 requestStarted를 꺼낸다.
private func nextStarted(_ it: inout AsyncStream<FlowEvent>.Iterator) async -> Flow? {
    while let event = await it.next() {
        if case .requestStarted(let flow) = event { return flow }
    }
    return nil
}

@Suite(.timeLimit(.minutes(1)))
struct ProxyServerMITMTests {
    @Test func httpsInSSLListIsDecryptedAndFlowHasBody() async throws {
        let ca = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try ca.leaf(for: "localhost")) { req in FlowResponse(status: 201, reason: "Created", headers: [.init(name: "Content-Type", value: "application/json")], body: Data(#"{"ok":true}"#.utf8)) }
        let originPort = try await origin.start()
        // 적응: 원 서버 리프는 프록시 CA가 발급했으므로 업스트림 신뢰 루트로 그 CA를 준다(시스템 신뢰로는 검증 불가).
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: ["localhost"]), upstreamTrustRootsDER: [ca.certificateDER]), certificateAuthority: ca, interceptors: .init())
        let port = try await server.start()
        var it = server.events.makeAsyncIterator()
        let (status, _, body) = try await fetchViaProxy("https://localhost:\(originPort)/v1?x=1", proxyPort: port, method: "POST", body: Data("req".utf8), trustRootDER: ca.certificateDER)
        #expect(status == 201 && body == Data(#"{"ok":true}"#.utf8))
        guard case .requestStarted(let flow) = await it.next() else { Issue.record("x"); return }
        #expect(flow.isDecrypted && !flow.isTunnel && flow.request.scheme == "https" && flow.request.path == "/v1?x=1" && flow.request.body == Data("req".utf8))
        guard case .responseReceived(_, let res, _) = await it.next() else { Issue.record("y"); return }
        #expect(res.status == 201 && res.body == Data(#"{"ok":true}"#.utf8))
        await server.stop(); await origin.stop()
    }

    @Test func responseInterceptorRunsOnDecryptedTraffic() async throws {
        let ca = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try ca.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data("hi".utf8)) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: ["localhost"]), upstreamTrustRootsDER: [ca.certificateDER]),
                                 certificateAuthority: ca, interceptors: .init(response: [MarkResponse()]))
        let port = try await server.start()
        let (status, headers, body) = try await fetchViaProxy("https://localhost:\(originPort)/", proxyPort: port, trustRootDER: ca.certificateDER)
        #expect(status == 200 && body == Data("hi".utf8) && headers["X-Modified"] == "1")
        await server.stop(); await origin.stop()
    }

    @Test func clientRejectingCertificateLogsTrustHint() async throws {
        let ca = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try ca.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data()) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: ["localhost"])), certificateAuthority: ca, interceptors: .init())
        let port = try await server.start()
        var it = server.events.makeAsyncIterator()
        // 적응: URLSession 대신 NIO 헬퍼. trustRootDER nil = 시스템 신뢰만 → 프록시가 위조한 리프를 거부한다.
        await #expect(throws: (any Error).self) {
            _ = try await fetchViaProxy("https://localhost:\(originPort)/", proxyPort: port, trustRootDER: nil)
        }
        var log: ConnectionLogEntry?
        while let event = await it.next() {
            if case .connectionLog(let entry) = event { log = entry; break }
        }
        #expect(log?.message.contains("(certificate_unknown)") == true)   // NIO 클라이언트가 보내는 alert 이름이 추출된다
        #expect(log?.host == "localhost" && log?.port == originPort && log?.message.contains("신뢰") == true)
        await server.stop(); await origin.stop()
    }

    @Test func sslPolicyUpdateTakesEffectForNewConnections() async throws {
        let ca = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try ca.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data("x".utf8)) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: []), upstreamTrustRootsDER: [ca.certificateDER]), certificateAuthority: ca, interceptors: .init())
        let port = try await server.start()
        var it = server.events.makeAsyncIterator()
        _ = try await fetchViaProxy("https://localhost:\(originPort)/", proxyPort: port, trustRootDER: ca.certificateDER)
        #expect(await nextStarted(&it)?.isTunnel == true)
        await server.update(sslPolicy: .init(patterns: ["localhost"]))
        _ = try await fetchViaProxy("https://localhost:\(originPort)/", proxyPort: port, trustRootDER: ca.certificateDER)
        #expect(await nextStarted(&it)?.isDecrypted == true)
        await server.stop(); await origin.stop()
    }

    @Test func tlsFailureMessageHintsTrustOnlyForCertificateAlerts() {
        // BoringSSLError의 임의 오류 텍스트는 공개 API로 만들 수 없어 문자열 판정(trustHint)과 합성 가능한 오류(eofDuringHandshake)로 나눠 본다.
        let hint = ProxyConnectionHandler.trustHint("error:10000416:SSL routines:OPENSSL_internal:SSLV3_ALERT_CERTIFICATE_UNKNOWN")
        #expect(hint?.contains("신뢰") == true && hint?.contains("(certificate_unknown)") == true)
        #expect(ProxyConnectionHandler.trustHint("error:10000418:SSL routines:OPENSSL_internal:TLSV1_ALERT_UNKNOWN_CA")?.contains("(unknown_ca)") == true)
        #expect(ProxyConnectionHandler.trustHint("error:1000009c:SSL routines:OPENSSL_internal:HTTP_REQUEST") == nil)
        #expect(ProxyConnectionHandler.trustHint("error:10000410:SSL routines:OPENSSL_internal:SSLV3_ALERT_HANDSHAKE_FAILURE") == nil)
        let raw = ProxyConnectionHandler.tlsFailureMessage(NIOSSLError.handshakeFailed(.sslError([.eofDuringHandshake])))
        #expect(raw?.contains("EOF during handshake") == true && raw?.contains("신뢰") == false)
        #expect(ProxyConnectionHandler.tlsFailureMessage(NIOSSLError.uncleanShutdown) == nil)
    }

    @Test func upstreamCertificateFailureYields502() async throws {
        let ca = try CertificateAuthority.generate()
        let other = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try other.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data()) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: ["localhost"]), upstreamTrustRootsDER: [ca.certificateDER]), certificateAuthority: ca, interceptors: .init())
        let port = try await server.start()
        var it = server.events.makeAsyncIterator()
        let (status, _, _) = try await fetchViaProxy("https://localhost:\(originPort)/", proxyPort: port, trustRootDER: ca.certificateDER)
        #expect(status == 502)
        _ = await it.next()
        guard case .failed(_, let error, _) = await it.next() else { Issue.record("no failed"); return }
        #expect(error.hasPrefix("업스트림 인증서 오류: "))
        await server.stop(); await origin.stop()
    }

    @Test func connectDecryptForcesMITMWithEmptySSLList() async throws {
        let ca = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try ca.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data("d".utf8)) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: []), upstreamTrustRootsDER: [ca.certificateDER]),
                                 certificateAuthority: ca, interceptors: .init(connect: [FixedVerdict(verdict: .init(action: .decrypt, note: "규칙: R"))]))
        let port = try await server.start()
        var it = server.events.makeAsyncIterator()
        let (status, _, body) = try await fetchViaProxy("https://localhost:\(originPort)/p", proxyPort: port, trustRootDER: ca.certificateDER)
        #expect(status == 200 && body == Data("d".utf8))
        guard case .requestStarted(let flow) = await it.next() else { Issue.record("no requestStarted"); return }
        #expect(flow.isDecrypted && flow.request.path == "/p")
        guard case .annotated(let id, let annotation) = await it.next() else { Issue.record("no annotated"); return }
        #expect(id == flow.id && annotation == .tool("규칙: R"))
        await server.stop(); await origin.stop()
    }
}
