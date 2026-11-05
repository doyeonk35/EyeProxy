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
    private let timeout: TimeAmount
    /// trustRootsDER가 nil이면 시스템 신뢰. 생성 실패는 tls 요청 때 에러로 드러낸다.
    private let tlsContext: Result<NIOSSLContext, any Error>

    init(group: EventLoopGroup, trustRootsDER: [[UInt8]]? = nil, timeout: TimeAmount = .seconds(30)) {
        self.group = group
        self.timeout = timeout
        self.tlsContext = Result {
            var config = TLSConfiguration.makeClientConfiguration()
            if let trustRootsDER {
                config.trustRoots = .certificates(try trustRootsDER.map { try NIOSSLCertificate(bytes: $0, format: .der) })
            }
            return try NIOSSLContext(configuration: config)
        }
    }

    /// 응답 완료 전 `timeout`이 지나거나 호출 Task가 취소되면 업스트림 연결을 닫고 throw 한다.
    func send(_ request: FlowRequest, tls: Bool) async throws -> FlowResponse {
        let sslContext = tls ? try tlsContext.get() : nil
        let loop = group.next()
        let promise = loop.makePromise(of: FlowResponse.self)
        let host = request.host
        let channel: Channel
        do {
            channel = try await ClientBootstrap(group: loop)
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
        let deadline = loop.scheduleTask(in: timeout) {
            promise.fail(UpstreamClientError(description: "upstream timed out"))
            channel.close(promise: nil)
        }
        promise.futureResult.whenComplete { _ in deadline.cancel() }

        let isDefaultPort = (request.scheme == "http" && request.port == 80) || (request.scheme == "https" && request.port == 443)
        let hostName = host.contains(":") ? "[\(host)]" : host
        var headers = HTTPHeaders([("Host", isDefaultPort ? hostName : "\(hostName):\(request.port)")]
            + request.headers.filter { !Self.rewrittenHeaders.contains($0.name.lowercased()) }.map { ($0.name, $0.value) })
        let hadBody = !request.body.isEmpty || request.header("Content-Length") != nil || request.header("Transfer-Encoding") != nil
        if hadBody { headers.add(name: "Content-Length", value: String(request.body.count)) }
        headers.add(name: "Connection", value: "close")
        let head = HTTPRequestHead(version: .http1_1, method: HTTPMethod(rawValue: request.method), uri: request.path, headers: headers)

        channel.write(HTTPClientRequestPart.head(head), promise: nil)
        if !request.body.isEmpty {
            channel.write(HTTPClientRequestPart.body(.byteBuffer(ByteBuffer(bytes: request.body))), promise: nil)
        }
        channel.writeAndFlush(HTTPClientRequestPart.end(nil), promise: nil)
        return try await withTaskCancellationHandler {
            try await promise.futureResult.get()
        } onCancel: {
            channel.close(promise: nil)
        }
    }

    /// Host는 (인터셉터가 바꿨을 수 있는) host/port로, 프레이밍은 버퍼링한 본문으로 다시 쓴다.
    private static let rewrittenHeaders: Set<String> = ["host", "content-length", "transfer-encoding", "connection", "keep-alive"]
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
