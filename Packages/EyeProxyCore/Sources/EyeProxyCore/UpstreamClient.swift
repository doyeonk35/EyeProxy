import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

struct UpstreamClientError: Error, CustomStringConvertible {
    let description: String
}

/// 1요청-1연결(`Connection: close`). 응답 본문은 전부 메모리에 버퍼링한다.
/// ponytail: 연결 재사용·스트리밍 없음. 수백 MB 응답이나 처리량이 문제되면 P2에서 풀링/스트리밍.
final class UpstreamClient: Sendable {
    private let group: EventLoopGroup
    /// 기본 시스템 신뢰. 생성 실패는 tls 요청 때 에러로 드러낸다.
    private let tlsContext: NIOSSLContext?

    init(group: EventLoopGroup) {
        self.group = group
        self.tlsContext = try? NIOSSLContext(configuration: .makeClientConfiguration())
    }

    func send(_ request: FlowRequest, tls: Bool) async throws -> FlowResponse {
        let sslContext: NIOSSLContext?
        if tls {
            guard let tlsContext else { throw UpstreamClientError(description: "TLS context unavailable") }
            sslContext = tlsContext
        } else {
            sslContext = nil
        }
        let promise = group.next().makePromise(of: FlowResponse.self)
        let host = request.host
        let channel: Channel
        do {
            channel = try await ClientBootstrap(group: group)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        let ops = channel.pipeline.syncOperations
                        if let sslContext {
                            // SNI에는 IP를 넣을 수 없다.
                            let isIP = (try? SocketAddress(ipAddress: host, port: 0)) != nil
                            try ops.addHandler(NIOSSLClientHandler(context: sslContext, serverHostname: isIP ? nil : host))
                        }
                        try ops.addHTTPClientHandlers()
                        try ops.addHandler(ResponseCollector(promise: promise))
                    }
                }
                .connect(host: host, port: request.port).get()
        } catch {
            promise.fail(error)
            throw error
        }

        var headers = HTTPHeaders(request.headers
            .filter { !Self.framingHeaders.contains($0.name.lowercased()) }
            .map { ($0.name, $0.value) })
        let hadBody = !request.body.isEmpty || request.header("Content-Length") != nil || request.header("Transfer-Encoding") != nil
        if hadBody { headers.add(name: "Content-Length", value: String(request.body.count)) }
        if !headers.contains(name: "Host") { headers.add(name: "Host", value: "\(host):\(request.port)") }
        headers.add(name: "Connection", value: "close")
        let head = HTTPRequestHead(version: .http1_1, method: HTTPMethod(rawValue: request.method), uri: request.path, headers: headers)

        channel.write(HTTPClientRequestPart.head(head), promise: nil)
        if !request.body.isEmpty {
            channel.write(HTTPClientRequestPart.body(.byteBuffer(ByteBuffer(bytes: request.body))), promise: nil)
        }
        channel.writeAndFlush(HTTPClientRequestPart.end(nil), promise: nil)
        return try await promise.futureResult.get()
    }

    /// 버퍼링한 본문으로 길이를 다시 정하므로 원래 프레이밍·연결 헤더는 버린다.
    private static let framingHeaders: Set<String> = ["content-length", "transfer-encoding", "connection", "keep-alive"]
}

private final class ResponseCollector: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart

    private var promise: EventLoopPromise<FlowResponse>?
    private var head: HTTPResponseHead?
    private var body = Data()

    init(promise: EventLoopPromise<FlowResponse>) { self.promise = promise }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let h): head = h
        case .body(let b): body.append(contentsOf: b.readableBytesView)
        case .end:
            guard let head else { return }
            promise?.succeed(FlowResponse(status: Int(head.status.code), reason: head.status.reasonPhrase,
                                          headers: head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }, body: body))
            promise = nil
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise?.fail(error)
        promise = nil
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        promise?.fail(UpstreamClientError(description: "upstream closed before response completed"))
        promise = nil
        context.fireChannelInactive()
    }
}
