import Foundation
import Testing
import NIOCore
import NIOPosix
import NIOHTTP1
@testable import EyeProxyCore

@Suite(.timeLimit(.minutes(1)))
struct ProxyServerHTTPTests {
    private func makeServer(_ interceptors: InterceptorChain = .init()) throws -> ProxyServer {
        ProxyServer(configuration: .init(bindHost: "127.0.0.1", port: 0), certificateAuthority: try .generate(), interceptors: interceptors)
    }

    @Test func forwardsPlainHTTPAndEmitsEvents() async throws {
        let origin = TestOrigin { req in FlowResponse(status: 200, reason: "OK", headers: [.init(name: "X-Echo-Path", value: req.path)], body: Data("hello".utf8)) }
        let originPort = try await origin.start()
        defer { await origin.stop() }
        let server = ProxyServer(configuration: .init(port: 0), certificateAuthority: try .generate(), interceptors: .init())
        let port = try await server.start()
        defer { await server.stop() }
        var iterator = server.events.makeAsyncIterator()
        let (status, headers, body) = try await fetchViaProxy("http://127.0.0.1:\(originPort)/a?b=1", proxyPort: port)
        #expect(status == 200); #expect(headers["X-Echo-Path"] == "/a?b=1"); #expect(body == Data("hello".utf8))
        guard case .requestStarted(let flow) = await iterator.next() else { Issue.record("no requestStarted"); return }
        #expect(flow.request.host == "127.0.0.1" && flow.request.port == originPort && flow.request.scheme == "http")
        #expect(flow.clientAddress == "127.0.0.1")
        guard case .responseReceived(let id, let res, _) = await iterator.next() else { Issue.record("no responseReceived"); return }
        #expect(id == flow.id && res.status == 200 && res.body == Data("hello".utf8))
    }

    @Test func forwardsPOSTBody() async throws {
        let origin = TestOrigin { req in
            FlowResponse(status: 200, reason: "OK", headers: [.init(name: "X-Method", value: req.method)], body: req.body)
        }
        let originPort = try await origin.start()
        defer { await origin.stop() }
        let server = try makeServer()
        let port = try await server.start()
        defer { await server.stop() }
        let payload = Data((0..<2048).map { UInt8($0 % 251) })
        let (status, headers, body) = try await fetchViaProxy("http://127.0.0.1:\(originPort)/upload", proxyPort: port,
                                                              method: "POST", body: payload)
        #expect(status == 200); #expect(headers["X-Method"] == "POST"); #expect(body == payload)
    }

    @Test func chunkedResponseIsBuffered() async throws {
        let origin = TestOrigin { _ in
            FlowResponse(status: 200, reason: "OK", headers: [.init(name: "Transfer-Encoding", value: "chunked")], body: Data("aaabbbccc".utf8))
        }
        let originPort = try await origin.start()
        defer { await origin.stop() }
        let server = try makeServer()
        let port = try await server.start()
        defer { await server.stop() }
        var iterator = server.events.makeAsyncIterator()
        let (status, _, body) = try await fetchViaProxy("http://127.0.0.1:\(originPort)/chunks", proxyPort: port)
        #expect(status == 200); #expect(body == Data("aaabbbccc".utf8))
        _ = await iterator.next()
        guard case .responseReceived(_, let res, _) = await iterator.next() else { Issue.record("no responseReceived"); return }
        #expect(res.body == Data("aaabbbccc".utf8))
    }

    @Test func headResponseKeepsOriginContentLength() async throws {
        let origin = TestOrigin { req in
            FlowResponse(status: 200, reason: "OK", headers: [.init(name: "Content-Length", value: "123"), .init(name: "X-Method", value: req.method)],
                         body: Data())
        }
        let originPort = try await origin.start()
        defer { await origin.stop() }
        let server = try makeServer()
        let port = try await server.start()
        defer { await server.stop() }
        let (status, headers, body) = try await fetchViaProxy("http://127.0.0.1:\(originPort)/h", proxyPort: port, method: "HEAD")
        #expect(status == 200); #expect(headers["Content-Length"] == "123"); #expect(headers["X-Method"] == "HEAD"); #expect(body.isEmpty)
    }

    @Test func requestInterceptorCanRespondWithoutUpstream() async throws {
        let (hits, hitsContinuation) = AsyncStream<Void>.makeStream()
        let origin = TestOrigin { _ in hitsContinuation.yield(); return FlowResponse(status: 200, reason: "OK", headers: [], body: Data()) }
        let originPort = try await origin.start()
        defer { await origin.stop() }
        let server = try makeServer(.init(request: [ShortCircuit()]))
        let port = try await server.start()
        defer { await server.stop() }
        var iterator = server.events.makeAsyncIterator()
        let (status, _, _) = try await fetchViaProxy("http://127.0.0.1:\(originPort)/x", proxyPort: port)
        #expect(status == 418)
        hitsContinuation.finish()   // 응답을 받은 뒤이므로 그 전에 원 서버가 불렸다면 이미 yield 됐다
        var count = 0
        for await _ in hits { count += 1 }
        #expect(count == 0)
        guard case .requestStarted(let flow) = await iterator.next() else { Issue.record("no requestStarted"); return }
        guard case .responseReceived(let id, let res, _) = await iterator.next() else { Issue.record("no responseReceived"); return }
        #expect(id == flow.id && res.status == 418)
    }

    @Test func upstreamFailureYields502AndFailedEvent() async throws {
        let closed = TestOrigin { _ in FlowResponse(status: 200, reason: "OK", headers: [], body: Data()) }
        let closedPort = try await closed.start()
        await closed.stop()
        let server = try makeServer()
        let port = try await server.start()
        defer { await server.stop() }
        var iterator = server.events.makeAsyncIterator()
        let (status, _, _) = try await fetchViaProxy("http://127.0.0.1:\(closedPort)/", proxyPort: port)
        #expect(status == 502)
        guard case .requestStarted(let flow) = await iterator.next() else { Issue.record("no requestStarted"); return }
        guard case .failed(let id, let error, _) = await iterator.next() else { Issue.record("no failed"); return }
        #expect(id == flow.id && !error.isEmpty)
    }

    @Test func upstreamTimeoutClosesConnectionAndThrows() async throws {
        let origin = HangingOrigin()
        let originPort = try await origin.start()
        defer { await origin.stop() }
        let client = UpstreamClient(group: MultiThreadedEventLoopGroup.singleton, timeout: .milliseconds(200))
        await #expect(throws: (any Error).self) { try await client.send(.get("http://127.0.0.1:\(originPort)/"), tls: false) }
        var closes = origin.closed.makeAsyncIterator()
        #expect(await closes.next() != nil)
    }

    @Test func clientDisconnectCancelsUpstreamExchange() async throws {
        let origin = HangingOrigin()
        let originPort = try await origin.start()
        defer { await origin.stop() }
        let server = try makeServer()
        let port = try await server.start()
        defer { await server.stop() }
        var events = server.events.makeAsyncIterator()
        let client = try await rawConnect(port: port, sending: "GET http://127.0.0.1:\(originPort)/ HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        guard case .requestStarted(let flow) = await events.next() else { Issue.record("no requestStarted"); return }
        try await client.close()
        guard case .failed(let id, let error, _) = await events.next() else { Issue.record("no failed"); return }
        #expect(id == flow.id && error == "client disconnected")
        var closes = origin.closed.makeAsyncIterator()
        #expect(await closes.next() != nil)   // 업스트림 연결도 닫혔다(30초 타임아웃 전에)
    }

    @Test func concurrentStartsShareOneBind() async throws {
        let server = try makeServer()
        async let first = server.start()
        async let second = server.start()
        let (a, b) = try await (first, second)
        #expect(a == b)
        await server.stop()
        let again = try await server.start()   // stop 후 재시작 가능
        #expect(again > 0)
        await server.stop()
    }

    @Test func flowRequestParsesAbsoluteURIAndStripsProxyHeaders() throws {
        func head(_ uri: String, _ headers: HTTPHeaders = [:]) -> HTTPRequestHead {
            HTTPRequestHead(version: .http1_1, method: .GET, uri: uri, headers: headers)
        }
        let r = try #require(ProxyConnectionHandler.flowRequest(
            from: head("http://example.com/p?q=1", ["Host": "example.com", "Proxy-Connection": "keep-alive",
                                                   "Proxy-Authorization": "Basic eA==", "Accept": "*/*"]), body: Data()))
        #expect(r.scheme == "http" && r.host == "example.com" && r.port == 80 && r.path == "/p?q=1")
        #expect(r.header("Proxy-Connection") == nil && r.header("Proxy-Authorization") == nil)
        #expect(r.header("Accept") == "*/*" && r.header("Host") == "example.com")
        #expect(ProxyConnectionHandler.flowRequest(from: head("https://example.com"), body: Data())?.port == 443)
        #expect(ProxyConnectionHandler.flowRequest(from: head("https://example.com"), body: Data())?.path == "/")
        let v6 = try #require(ProxyConnectionHandler.flowRequest(from: head("http://[::1]:8080/x"), body: Data()))
        #expect(v6.host == "::1" && v6.port == 8080)
        #expect(ProxyConnectionHandler.flowRequest(from: head("/relative"), body: Data()) == nil)
    }

    @Test func portInUseThrows() async throws {
        let a = ProxyServer(configuration: .init(bindHost: "127.0.0.1", port: 0), certificateAuthority: try .generate(), interceptors: .init())
        let port = try await a.start()
        defer { await a.stop() }
        let b = ProxyServer(configuration: .init(bindHost: "127.0.0.1", port: port), certificateAuthority: try .generate(), interceptors: .init())
        await #expect(throws: ProxyServerError.portInUse(port)) { try await b.start() }
    }
}
