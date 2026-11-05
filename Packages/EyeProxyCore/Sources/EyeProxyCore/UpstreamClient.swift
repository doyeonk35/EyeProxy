import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

struct UpstreamClientError: Error, CustomStringConvertible {
    let description: String
}

/// LAN 클라이언트가 프록시를 통해 Mac의 루프백 서비스에 닿으려 할 때.
struct LoopbackBlockedError: Error, CustomStringConvertible {
    var description: String { "LAN 클라이언트의 루프백 접근 차단" }
}

/// 루프백이 아닌 클라이언트가 루프백 주소(127.0.0.0/8, ::1)에 연결된 업스트림을 쓰려 하면 차단.
/// 연결된 peer 주소로 판단하므로 127.0.0.1로 풀리는 DNS 이름도 막힌다. 주소를 모르면 루프백이 아닌 것으로 본다.
func shouldBlockUpstream(clientAddress: String?, peerAddress: String?) -> Bool {
    func isLoopback(_ ip: String?) -> Bool {
        guard let ip = ip?.lowercased() else { return false }
        return ip.hasPrefix("127.") || ip == "::1" || ip.hasPrefix("::ffff:127.")
    }
    return !isLoopback(clientAddress) && isLoopback(peerAddress)
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

    /// 업스트림에서 `timeout` 동안 아무것도 오지 않거나(유휴) 호출 Task가 취소되면 업스트림 연결을 닫고 throw 한다.
    /// 루프백 peer는 `clientAddress`도 루프백일 때만 허용한다(`LoopbackBlockedError`).
    func send(_ request: FlowRequest, tls: Bool, clientAddress: String) async throws -> FlowResponse {
        let sslContext = tls ? try tlsContext.get() : nil
        let loop = group.next()
        let promise = loop.makePromise(of: FlowResponse.self)
        let host = request.host
        let timeout = self.timeout
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
                        try ops.addHandler(ResponseCollector(promise: promise, idleTimeout: timeout))
                    }
                }
                .connect(host: host, port: request.port).get()
        } catch {
            promise.fail(error)
            throw error
        }
        if shouldBlockUpstream(clientAddress: clientAddress, peerAddress: channel.remoteAddress?.ipAddress) {
            promise.fail(LoopbackBlockedError())
            channel.close(promise: nil)
            throw LoopbackBlockedError()
        }
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
    private let idleTimeout: TimeAmount
    private var deadline: Scheduled<Void>?

    init(promise: EventLoopPromise<FlowResponse>, idleTimeout: TimeAmount) {
        self.promise = promise
        self.idleTimeout = idleTimeout
    }

    func channelActive(context: ChannelHandlerContext) {
        armDeadline(context: context)
        context.fireChannelActive()
    }

    /// ponytail: 30초 유휴 제한(마지막 수신 기준, 총 시간 제한 없음). 느린 대용량 응답도 바이트가 오는 한 끊지 않는다.
    private func armDeadline(context: ChannelHandlerContext) {
        deadline?.cancel()
        deadline = context.eventLoop.assumeIsolated().scheduleTask(in: idleTimeout) {
            self.complete(.failure(UpstreamClientError(description: "upstream timed out")))
            context.close(promise: nil)
        }
    }

    /// 완료 경로는 모두 여기로: 데드라인 취소 후 promise를 한 번만 완료한다.
    private func complete(_ result: Result<FlowResponse, any Error>) {
        deadline?.cancel()
        deadline = nil
        promise?.completeWith(result)
        promise = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard promise != nil else { return }
        armDeadline(context: context)
        switch unwrapInboundIn(data) {
        case .head(let h): head = h
        case .body(let b): body.append(contentsOf: b.readableBytesView)
        case .end:
            guard let head else { return }
            complete(.success(FlowResponse(status: Int(head.status.code), reason: head.status.reasonPhrase,
                                           headers: head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }, body: body)))
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        complete(.failure(error))
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        complete(.failure(UpstreamClientError(description: "upstream closed before response completed")))
        context.fireChannelInactive()
    }
}
