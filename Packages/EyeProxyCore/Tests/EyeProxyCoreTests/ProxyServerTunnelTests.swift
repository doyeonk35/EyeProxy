import Foundation
import Testing
@testable import EyeProxyCore

@Suite(.timeLimit(.minutes(1)))
struct ProxyServerTunnelTests {
    @Test func httpsNotInSSLListIsTunneledUnchanged() async throws {
        let ca = try CertificateAuthority.generate()
        let origin = TestOrigin(tls: try ca.leaf(for: "localhost")) { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data("secret".utf8)) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0, sslPolicy: .init(patterns: [])), certificateAuthority: ca, interceptors: .init())
        let port = try await server.start()
        var it = server.events.makeAsyncIterator()
        let (status, _, body) = try await fetchViaProxy("https://localhost:\(originPort)/x", proxyPort: port, trustRootDER: ca.certificateDER)
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
}
