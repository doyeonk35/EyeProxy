import Foundation
import Testing
@testable import EyeProxyCore

struct FixedVerdict: ConnectInterceptor {
    let verdict: ConnectVerdict
    func intercept(host: String, port: Int, context: ConnectContext) async -> ConnectVerdict { verdict }
}

@Suite(.timeLimit(.minutes(1)))
struct ProxyServerTunnelTests {
    @Test func httpsNotInSSLListIsTunneledUnchanged() async throws {
        let ca = try CertificateAuthority.generate()
        // 원 서버는 별도 CA. 클라이언트는 그 CA만 믿으므로 프록시(ca)가 위조할 수 없다 → TLS 성공 = 진짜 패스스루.
        let originCA = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try originCA.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data("secret".utf8)) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: [])), certificateAuthority: ca, interceptors: .init())
        let port = try await server.start()
        var it = server.events.makeAsyncIterator()
        let (status, _, body) = try await fetchViaProxy("https://localhost:\(originPort)/x", proxyPort: port, trustRootDER: originCA.certificateDER)
        #expect(status == 200 && body == Data("secret".utf8))
        guard case .requestStarted(let flow) = await it.next() else { Issue.record("x"); return }
        #expect(flow.isTunnel && flow.request.method == "CONNECT" && flow.request.host == "localhost" && flow.request.port == originPort)
        #expect(flow.request.body.isEmpty)   // 내용은 못 본다
        await server.stop(); await origin.stop()
    }

    @Test func tunnelToUnreachableHostReturns502() async throws {
        let ca = try CertificateAuthority.generate()
        let closed = TestOrigin(tls: try ca.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data()) }
        let closedPort = try await closed.start()
        await closed.stop()
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: [])), certificateAuthority: ca, interceptors: .init())
        let port = try await server.start()
        var it = server.events.makeAsyncIterator()
        await #expect(throws: (any Error).self) {
            _ = try await fetchViaProxy("https://localhost:\(closedPort)/x", proxyPort: port, trustRootDER: ca.certificateDER)
        }
        guard case .requestStarted(let flow) = await it.next() else { Issue.record("no requestStarted"); return }
        #expect(flow.isTunnel)
        guard case .failed(let id, let error, _) = await it.next() else { Issue.record("no failed"); return }
        #expect(id == flow.id && !error.isEmpty)
        await server.stop()
    }

    @Test func tunnelCloseEmitsResponseReceived() async throws {
        let ca = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try ca.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data("secret".utf8)) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(bindHost: "127.0.0.1", port: 0), certificateAuthority: ca, interceptors: .init())
        let port = try await server.start()
        var it = server.events.makeAsyncIterator()
        _ = try await fetchViaProxy("https://localhost:\(originPort)/x", proxyPort: port, trustRootDER: ca.certificateDER)
        guard case .requestStarted(let flow) = await it.next() else { Issue.record("no requestStarted"); return }
        // 클라이언트(fetch 헬퍼)가 연결을 닫으면 터널 항목이 200 Connection Established로 끝난다.
        guard case .responseReceived(let id, let res, _) = await it.next() else { Issue.record("no responseReceived"); return }
        #expect(id == flow.id && res.status == 200 && res.reason == "Connection Established" && res.body.isEmpty)
        await server.stop(); await origin.stop()
    }

    @Test func connectDropClosesWithoutTunnel() async throws {
        let ca = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try ca.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data()) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: [])), certificateAuthority: ca,
                                 interceptors: .init(connect: [FixedVerdict(verdict: .init(action: .drop))]))
        let port = try await server.start()
        var it = server.events.makeAsyncIterator()
        // 200도 다른 상태 줄도 없이 닫힌다.
        await #expect {
            _ = try await fetchViaProxy("https://localhost:\(originPort)/x", proxyPort: port, trustRootDER: ca.certificateDER)
        } throws: { ($0 as? ConnectRefused)?.status == "closed before CONNECT response" }
        guard case .requestStarted(let flow) = await it.next() else { Issue.record("no requestStarted"); return }
        #expect(flow.request.method == "CONNECT" && flow.request.port == originPort)
        guard case .failed(let id, let error, _) = await it.next() else { Issue.record("no failed"); return }
        #expect(id == flow.id && error == "규칙으로 연결 끊김")
        await server.stop(); await origin.stop()
    }

    @Test func unrecordedTunnelEmitsNoEvents() async throws {
        let ca = try CertificateAuthority.generate()
        let originCA = try CertificateAuthority.generate()   // 성공 = 패스스루(SSL 목록에 있어도 복호화 안 함)
        let origin = TestOrigin(tls: try originCA.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data("s".utf8)) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: ["localhost"])), certificateAuthority: ca,
                                 interceptors: .init(connect: [FixedVerdict(verdict: .init(record: false))]))
        let port = try await server.start()
        let (status, _, body) = try await fetchViaProxy("https://localhost:\(originPort)/x", proxyPort: port, trustRootDER: originCA.certificateDER)
        #expect(status == 200 && body == Data("s".utf8))
        let events = server.events
        let first = await withTaskGroup(of: FlowEvent?.self) { group in
            group.addTask { var it = events.makeAsyncIterator(); return await it.next() }
            group.addTask { try? await Task.sleep(for: .seconds(1)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        #expect(first == nil)
        await server.stop(); await origin.stop()
    }

    @Test func shapingDelaysTunnel() async throws {
        let ca = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try ca.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data("slow".utf8)) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: [])), certificateAuthority: ca,
                                 interceptors: .init(connect: [FixedVerdict(verdict: .init(shaping: .init(latencyMS: 300)))]))
        let port = try await server.start()
        let clock = ContinuousClock()
        let start = clock.now
        // 원 서버가 응답 직후 닫아도(Connection: close) 늦춘 바이트가 닫기보다 먼저 간다.
        let (status, _, body) = try await fetchViaProxy("https://localhost:\(originPort)/x", proxyPort: port, trustRootDER: ca.certificateDER)
        #expect(status == 200 && body == Data("slow".utf8))
        #expect(clock.now - start >= .milliseconds(300))
        await server.stop(); await origin.stop()
    }

    @Test func runConnectMergesVerdicts() async {
        let chain = InterceptorChain(connect: [
            FixedVerdict(verdict: .init(record: false)),
            FixedVerdict(verdict: .init(action: .decrypt, shaping: .init(latencyMS: 1), note: "a")),
            FixedVerdict(verdict: .init(action: .drop, shaping: .init(latencyMS: 2), note: "b")),
        ])
        let v = await chain.runConnect(host: "a.example", port: 443, context: .init(clientAddress: "127.0.0.1", clientPort: nil))
        #expect(v == ConnectVerdict(action: .decrypt, record: false, shaping: .init(latencyMS: 1), note: "a"))
        #expect(await InterceptorChain().runConnect(host: "a", port: 1, context: .init(clientAddress: "x", clientPort: nil)) == ConnectVerdict())
    }
}
