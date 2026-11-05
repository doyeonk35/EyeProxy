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

    func stop() async {
        try? await channel?.close()
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
            if !chunked { headers.replaceOrAdd(name: "Content-Length", value: String(response.body.count)) }
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
