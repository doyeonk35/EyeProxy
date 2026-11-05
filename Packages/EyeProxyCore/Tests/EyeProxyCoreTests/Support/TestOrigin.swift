import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL
@testable import EyeProxyCore

/// NIO로 띄우는 로컬 HTTP(S) 서버. handler가 (FlowRequest) -> FlowResponse. port 0 바인드 후 실제 포트 반환.
/// 응답 헤더에 `Transfer-Encoding: chunked`가 있으면 본문을 3조각으로 나눠 chunked로 보낸다.
final class TestOrigin {
    private let tls: LeafCertificate?
    private let handler: @Sendable (FlowRequest) -> FlowResponse
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?

    init(tls: LeafCertificate? = nil, handler: @Sendable @escaping (FlowRequest) -> FlowResponse) {
        self.tls = tls
        self.handler = handler
    }

    func start() async throws -> Int {
        let sslContext = try tls.map { leaf in
            try NIOSSLContext(configuration: .makeServerConfiguration(
                certificateChain: [.certificate(NIOSSLCertificate(bytes: leaf.certificateDER, format: .der))],
                privateKey: .privateKey(NIOSSLPrivateKey(bytes: leaf.privateKeyDER, format: .der))))
        }
        let handler = self.handler
        let isHTTPS = tls != nil
        let channel = try await ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    if let sslContext {
                        try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: sslContext))
                    }
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline()
                    try channel.pipeline.syncOperations.addHandler(OriginHandler(isHTTPS: isHTTPS, handler: handler))
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        self.channel = channel
        return channel.localAddress!.port!
    }

    /// 멱등. (이미 종료된 group에 shutdownGracefully를 다시 부르면 영원히 돌아오지 않는다.)
    func stop() async {
        guard let channel else { return }
        self.channel = nil
        try? await channel.close()
        try? await group.shutdownGracefully()
    }
}

private final class OriginHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let isHTTPS: Bool
    private let handler: @Sendable (FlowRequest) -> FlowResponse
    private var head: HTTPRequestHead?
    private var body = Data()

    init(isHTTPS: Bool, handler: @Sendable @escaping (FlowRequest) -> FlowResponse) {
        self.isHTTPS = isHTTPS
        self.handler = handler
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let h): head = h; body = Data()
        case .body(let b): body.append(contentsOf: b.readableBytesView)
        case .end:
            guard let head else { return }
            let hostHeader = head.headers["Host"].first ?? "127.0.0.1"
            let request = FlowRequest(
                method: head.method.rawValue, scheme: isHTTPS ? "https" : "http",
                host: String(hostHeader.split(separator: ":").first ?? ""),
                port: context.channel.localAddress?.port ?? 0, path: head.uri,
                headers: head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }, body: body)
            let response = handler(request)
            var headers = HTTPHeaders(response.headers.map { ($0.name, $0.value) })
            let chunked = response.header("Transfer-Encoding")?.lowercased() == "chunked"
            if !chunked && response.header("Content-Length") == nil {
                headers.add(name: "Content-Length", value: String(response.body.count))
            }
            let status = HTTPResponseStatus(statusCode: response.status, reasonPhrase: response.reason)
            context.write(wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: status, headers: headers))), promise: nil)
            let bytes = [UInt8](response.body)
            let pieces = chunked ? 3 : 1
            let size = (bytes.count + pieces - 1) / max(pieces, 1)
            for start in stride(from: 0, to: bytes.count, by: max(size, 1)) {
                let slice = bytes[start..<min(start + size, bytes.count)]
                context.writeAndFlush(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(bytes: slice)))), promise: nil)
            }
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            self.head = nil
        }
    }
}

/// 연결을 받고 아무 응답도 하지 않는 서버. 받은 연결이 닫힐 때마다 `closed`에 알린다.
final class HangingOrigin {
    let closed: AsyncStream<Void>
    private let closedSink: AsyncStream<Void>.Continuation
    private var channel: Channel?

    init() { (closed, closedSink) = AsyncStream.makeStream() }

    func start() async throws -> Int {
        let sink = closedSink
        let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { child in
                child.closeFuture.whenComplete { _ in sink.yield() }
                return child.eventLoop.makeSucceededVoidFuture()
            }
            .bind(host: "127.0.0.1", port: 0).get()
        self.channel = channel
        return channel.localAddress!.port!
    }

    func stop() async { try? await channel?.close() }
}

/// 프록시에 원시 바이트를 보내는 TCP 연결(응답은 읽지 않는다). 닫기는 호출자가.
func rawConnect(port: Int, sending text: String) async throws -> Channel {
    let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton).connect(host: "127.0.0.1", port: port).get()
    try await channel.writeAndFlush(ByteBuffer(string: text))
    return channel
}

/// trustRootDER가 있으면 그 CA만 신뢰한다(Task 6/7 MITM 테스트용).
private final class TrustDelegate: NSObject, URLSessionDelegate, Sendable {
    let rootDER: [UInt8]?
    init(rootDER: [UInt8]?) { self.rootDER = rootDER }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let rootDER, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        guard let root = SecCertificateCreateWithData(nil, Data(rootDER) as CFData) else { return (.cancelAuthenticationChallenge, nil) }
        SecTrustSetAnchorCertificates(trust, [root] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        guard SecTrustEvaluateWithError(trust, nil) else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}

/// 프록시를 통해 요청을 보내는 간단한 클라이언트(URLSession + connectionProxyDictionary). 응답(status, headers, body)을 반환.
func fetchViaProxy(_ url: String, proxyPort: Int, method: String = "GET", body: Data? = nil,
                   headers: [String: String] = [:], trustRootDER: [UInt8]? = nil) async throws -> (Int, [String: String], Data) {
    if url.hasPrefix("https:") {
        return try await fetchViaCONNECT(URL(string: url)!, proxyPort: proxyPort, method: method, body: body, headers: headers, trustRootDER: trustRootDER)
    }
    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [
        kCFNetworkProxiesHTTPEnable: 1, kCFNetworkProxiesHTTPProxy: "127.0.0.1", kCFNetworkProxiesHTTPPort: proxyPort,
        kCFNetworkProxiesHTTPSEnable: 1, kCFNetworkProxiesHTTPSProxy: "127.0.0.1", kCFNetworkProxiesHTTPSPort: proxyPort,
    ]
    let session = URLSession(configuration: config, delegate: TrustDelegate(rootDER: trustRootDER), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    var request = URLRequest(url: URL(string: url)!)
    request.httpMethod = method
    request.httpBody = body
    for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
    let (data, response) = try await session.data(for: request)
    let http = response as! HTTPURLResponse
    var out: [String: String] = [:]
    for (k, v) in http.allHeaderFields { out["\(k)"] = "\(v)" }
    return (http.statusCode, out, data)
}

struct ConnectRefused: Error { let status: String }

/// URLSession(Network.framework)은 루프백 목적지의 https에 프록시를 쓰지 않고 직접 붙는다(실측: CONNECT가 안 온다).
/// 그래서 https는 NIO로 직접 `CONNECT` → 200 확인 → 같은 연결 위에서 TLS(trustRootDER만 신뢰, nil이면 시스템 신뢰; 전체 검증, SNI=host) → HTTP/1.1 요청.
/// CONNECT가 200이 아니면 `ConnectRefused`를 던진다.
private func fetchViaCONNECT(_ url: URL, proxyPort: Int, method: String, body: Data?, headers: [String: String],
                             trustRootDER: [UInt8]?) async throws -> (Int, [String: String], Data) {
    let host = url.host!, port = url.port ?? 443
    var tls = TLSConfiguration.makeClientConfiguration()
    if let trustRootDER { tls.trustRoots = .certificates([try NIOSSLCertificate(bytes: trustRootDER, format: .der)]) }
    let sslContext = try NIOSSLContext(configuration: tls)
    var path = url.path.isEmpty ? "/" : url.path
    if let query = url.query { path += "?" + query }
    var requestHeaders = HTTPHeaders([("Host", "\(host):\(port)"), ("Connection", "close")] + headers.map { ($0.key, $0.value) })
    if let body { requestHeaders.add(name: "Content-Length", value: String(body.count)) }
    let request = HTTPRequestHead(version: .http1_1, method: HTTPMethod(rawValue: method), uri: path, headers: requestHeaders)
    let loop = MultiThreadedEventLoopGroup.singleton.next()
    let promise = loop.makePromise(of: (Int, [String: String], Data).self)
    // 조용한 프록시가 테스트를 멈추지 않도록 자체 데드라인. (완료된 promise를 다시 fail 해도 무시된다.)
    let deadline = loop.scheduleTask(in: .seconds(10)) { promise.fail(ConnectRefused(status: "timed out")) }
    defer { deadline.cancel() }
    let channel: Channel
    do {
        channel = try await ClientBootstrap(group: loop)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(ConnectThenRequest(
                        authority: "\(host):\(port)", sslContext: sslContext, request: request, body: body, promise: promise))
                }
            }
            .connect(host: "127.0.0.1", port: proxyPort).get()
    } catch {
        promise.fail(error)   // 안 그러면 NIO의 leaking-promise 검사가 테스트 프로세스를 죽인다
        throw error
    }
    defer { channel.close(promise: nil) }
    return try await promise.futureResult.get()
}

private final class ConnectThenRequest: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer

    private let authority: String
    private let sslContext: NIOSSLContext
    private let request: HTTPRequestHead
    private let body: Data?
    private let promise: EventLoopPromise<(Int, [String: String], Data)>
    private var received = ByteBuffer()

    init(authority: String, sslContext: NIOSSLContext, request: HTTPRequestHead, body: Data?,
         promise: EventLoopPromise<(Int, [String: String], Data)>) {
        self.authority = authority
        self.sslContext = sslContext
        self.request = request
        self.body = body
        self.promise = promise
    }

    func channelActive(context: ChannelHandlerContext) {
        context.writeAndFlush(NIOAny(ByteBuffer(string: "CONNECT \(authority) HTTP/1.1\r\nHost: \(authority)\r\n\r\n")), promise: nil)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var bytes = unwrapInboundIn(data)
        received.writeBuffer(&bytes)
        let text = String(buffer: received)
        guard let end = text.range(of: "\r\n\r\n") else { return }
        let statusLine = String(text[..<end.lowerBound].prefix { $0 != "\r" })
        guard statusLine.split(separator: " ").dropFirst().first == "200" else {
            promise.fail(ConnectRefused(status: statusLine))
            context.close(promise: nil)
            return
        }
        do {
            let ops = context.pipeline.syncOperations
            let ssl = try NIOSSLClientHandler(context: sslContext, serverHostname: String(authority.split(separator: ":").first!))
            try ops.addHandler(ssl, position: .first)
            try ops.addHTTPClientHandlers(position: .after(ssl))
            try ops.addHandler(ResponseCollector(promise: promise))
            let channel = context.channel
            channel.write(HTTPClientRequestPart.head(request), promise: nil)
            if let body { channel.write(HTTPClientRequestPart.body(.byteBuffer(ByteBuffer(bytes: body))), promise: nil) }
            channel.writeAndFlush(HTTPClientRequestPart.end(nil), promise: nil)
            ops.removeHandler(context: context, promise: nil)
        } catch {
            promise.fail(error)
            context.close(promise: nil)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        promise.fail(ConnectRefused(status: "closed before CONNECT response"))
        context.fireChannelInactive()
    }
}

private final class ResponseCollector: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let promise: EventLoopPromise<(Int, [String: String], Data)>
    private var head: HTTPResponseHead?
    private var body = Data()

    init(promise: EventLoopPromise<(Int, [String: String], Data)>) { self.promise = promise }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let h): head = h
        case .body(let b): body.append(contentsOf: b.readableBytesView)
        case .end:
            guard let head else { return }
            var headers: [String: String] = [:]
            for (name, value) in head.headers { headers[name] = value }
            promise.succeed((Int(head.status.code), headers, body))
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        promise.fail(ConnectRefused(status: "closed before response completed"))
        context.fireChannelInactive()
    }
}
