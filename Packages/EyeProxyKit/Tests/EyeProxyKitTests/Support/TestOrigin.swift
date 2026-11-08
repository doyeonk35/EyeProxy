import EyeProxyCore
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import Synchronization

// EyeProxyCoreTests/Support/TestOrigin.swift의 HTTP 부분만 옮긴 것(TLS·chunked 없음).

/// 로컬 HTTP 서버. 127.0.0.1의 OS 할당 포트에 뜬다.
final class TestOrigin {
    private let handler: @Sendable (FlowRequest) -> FlowResponse
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?

    init(handler: @Sendable @escaping (FlowRequest) -> FlowResponse) { self.handler = handler }

    func start() async throws -> Int {
        let handler = self.handler
        let channel = try await ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline()
                    try channel.pipeline.syncOperations.addHandler(OriginHandler(handler: handler))
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        self.channel = channel
        return channel.localAddress!.port!
    }

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

    private let handler: @Sendable (FlowRequest) -> FlowResponse
    private var head: HTTPRequestHead?
    private var body = Data()

    init(handler: @Sendable @escaping (FlowRequest) -> FlowResponse) { self.handler = handler }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let h): head = h; body = Data()
        case .body(let b): body.append(contentsOf: b.readableBytesView)
        case .end:
            guard let head else { return }
            let host = head.headers["Host"].first ?? "127.0.0.1"
            let response = handler(FlowRequest(
                method: head.method.rawValue, scheme: "http", host: String(host.split(separator: ":").first ?? ""),
                port: context.channel.localAddress?.port ?? 0, path: head.uri,
                headers: head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }, body: body))
            var headers = HTTPHeaders(response.headers.map { ($0.name, $0.value) })
            headers.replaceOrAdd(name: "Content-Length", value: String(response.body.count))
            let status = HTTPResponseStatus(statusCode: response.status, reasonPhrase: response.reason)
            context.write(wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: status, headers: headers))), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(bytes: response.body)))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            self.head = nil
        }
    }
}

final class Counter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func bump() { count.withLock { $0 += 1 } }
}

/// 프록시에 원시 바이트를 보내는 TCP 연결(응답은 읽지 않는다). 닫기는 호출자가.
func rawConnect(port: Int, sending text: String) async throws -> Channel {
    let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton).connect(host: "127.0.0.1", port: port).get()
    try await channel.writeAndFlush(ByteBuffer(string: text))
    return channel
}

/// 평문 HTTP 프록시(proxyHost:proxyPort)를 거친 GET.
func fetch(_ url: String, proxyHost: String, proxyPort: Int) async throws -> (Int, Data) {
    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [
        kCFNetworkProxiesHTTPEnable: 1, kCFNetworkProxiesHTTPProxy: proxyHost, kCFNetworkProxiesHTTPPort: proxyPort,
    ]
    let session = URLSession(configuration: config)
    defer { session.finishTasksAndInvalidate() }
    let (data, response) = try await session.data(from: URL(string: url)!)
    return ((response as! HTTPURLResponse).statusCode, data)
}
