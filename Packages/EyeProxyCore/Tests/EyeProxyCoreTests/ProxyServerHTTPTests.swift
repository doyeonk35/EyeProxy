import Foundation
import Testing
@testable import EyeProxyCore

@Suite(.timeLimit(.minutes(1)))
struct ProxyServerHTTPTests {
    @Test func forwardsPlainHTTPAndEmitsEvents() async throws {
        let origin = TestOrigin { req in FlowResponse(status: 200, reason: "OK", headers: [.init(name: "X-Echo-Path", value: req.path)], body: Data("hello".utf8)) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0), certificateAuthority: try .generate(), interceptors: .init())
        let port = try await server.start()
        var iterator = server.events.makeAsyncIterator()
        let (status, headers, body) = try await fetchViaProxy("http://127.0.0.1:\(originPort)/a?b=1", proxyPort: port)
        #expect(status == 200); #expect(headers["X-Echo-Path"] == "/a?b=1"); #expect(body == Data("hello".utf8))
        guard case .requestStarted(let flow) = await iterator.next() else { Issue.record("no requestStarted"); return }
        #expect(flow.request.host == "127.0.0.1" && flow.request.port == originPort && flow.request.scheme == "http")
        #expect(flow.clientAddress == "127.0.0.1")
        guard case .responseReceived(let id, let res, _) = await iterator.next() else { Issue.record("no responseReceived"); return }
        #expect(id == flow.id && res.status == 200 && res.body == Data("hello".utf8))
        await server.stop(); await origin.stop()
    }

    @Test func forwardsPOSTBody() async throws {
        let origin = TestOrigin { req in
            FlowResponse(status: 200, reason: "OK", headers: [.init(name: "X-Method", value: req.method)], body: req.body)
        }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0), certificateAuthority: try .generate(), interceptors: .init())
        let port = try await server.start()
        let payload = Data((0..<2048).map { UInt8($0 % 251) })
        let (status, headers, body) = try await fetchViaProxy("http://127.0.0.1:\(originPort)/upload", proxyPort: port,
                                                              method: "POST", body: payload)
        #expect(status == 200); #expect(headers["X-Method"] == "POST"); #expect(body == payload)
        await server.stop(); await origin.stop()
    }

    @Test func chunkedResponseIsBuffered() async throws {
        let origin = TestOrigin { _ in
            FlowResponse(status: 200, reason: "OK", headers: [.init(name: "Transfer-Encoding", value: "chunked")], body: Data("aaabbbccc".utf8))
        }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0), certificateAuthority: try .generate(), interceptors: .init())
        let port = try await server.start()
        var iterator = server.events.makeAsyncIterator()
        let (status, _, body) = try await fetchViaProxy("http://127.0.0.1:\(originPort)/chunks", proxyPort: port)
        #expect(status == 200); #expect(body == Data("aaabbbccc".utf8))
        _ = await iterator.next()
        guard case .responseReceived(_, let res, _) = await iterator.next() else { Issue.record("no responseReceived"); return }
        #expect(res.body == Data("aaabbbccc".utf8))
        await server.stop(); await origin.stop()
    }

    @Test func requestInterceptorCanRespondWithoutUpstream() async throws {
        let (hits, hitsContinuation) = AsyncStream<Void>.makeStream()
        let origin = TestOrigin { _ in hitsContinuation.yield(); return FlowResponse(status: 200, reason: "OK", headers: [], body: Data()) }
        let originPort = try await origin.start()
        let server = ProxyServer(configuration: .init(port: 0), certificateAuthority: try .generate(),
                                 interceptors: .init(request: [ShortCircuit()]))
        let port = try await server.start()
        var iterator = server.events.makeAsyncIterator()
        let (status, _, _) = try await fetchViaProxy("http://127.0.0.1:\(originPort)/x", proxyPort: port)
        #expect(status == 418)
        guard case .requestStarted(let flow) = await iterator.next() else { Issue.record("no requestStarted"); return }
        guard case .responseReceived(let id, let res, _) = await iterator.next() else { Issue.record("no responseReceived"); return }
        #expect(id == flow.id && res.status == 418)
        await server.stop(); await origin.stop()
        hitsContinuation.finish()
        var count = 0
        for await _ in hits { count += 1 }
        #expect(count == 0)
    }

    @Test func upstreamFailureYields502AndFailedEvent() async throws {
        let closed = TestOrigin { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data()) }
        let closedPort = try await closed.start()
        await closed.stop()
        let server = ProxyServer(configuration: .init(port: 0), certificateAuthority: try .generate(), interceptors: .init())
        let port = try await server.start()
        var iterator = server.events.makeAsyncIterator()
        let (status, _, _) = try await fetchViaProxy("http://127.0.0.1:\(closedPort)/", proxyPort: port)
        #expect(status == 502)
        guard case .requestStarted(let flow) = await iterator.next() else { Issue.record("no requestStarted"); return }
        guard case .failed(let id, let error, _) = await iterator.next() else { Issue.record("no failed"); return }
        #expect(id == flow.id && !error.isEmpty)
        await server.stop()
    }

    @Test func portInUseThrows() async throws {
        let a = ProxyServer(configuration: .init(bindHost: "127.0.0.1", port: 0), certificateAuthority: try .generate(), interceptors: .init())
        let port = try await a.start()
        let b = ProxyServer(configuration: .init(bindHost: "127.0.0.1", port: port), certificateAuthority: try .generate(), interceptors: .init())
        await #expect(throws: ProxyServerError.portInUse(port)) { try await b.start() }
        await a.stop()
    }
}
