import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

public struct ProxyConfiguration: Sendable {
    public var bindHost: String
    public var port: Int
    public var sslPolicy: SSLProxyingPolicy
    /// 업스트림 TLS 신뢰 루트(DER). nil이면 시스템 신뢰.
    public var upstreamTrustRootsDER: [[UInt8]]?

    public init(bindHost: String = "0.0.0.0", port: Int = 9090, sslPolicy: SSLProxyingPolicy = .init(),
                upstreamTrustRootsDER: [[UInt8]]? = nil) {
        self.bindHost = bindHost
        self.port = port
        self.sslPolicy = sslPolicy
        self.upstreamTrustRootsDER = upstreamTrustRootsDER
    }
}

public enum ProxyServerError: Error, Equatable {
    case portInUse(Int)
    case notRunning
}

/// `exchange`의 결과: 클라이언트에 쓸 응답, 또는 응답 없이 연결을 끊기.
enum ExchangeOutcome: Sendable {
    case respond(FlowResponse)
    case drop
}

public actor ProxyServer {
    /// 여러 소비자 금지: 앱에서 하나만 구독.
    public nonisolated let events: AsyncStream<FlowEvent>
    private let eventSink: AsyncStream<FlowEvent>.Continuation
    private let configuration: ProxyConfiguration
    let certificateAuthority: CertificateAuthority
    private(set) var sslPolicy: SSLProxyingPolicy
    private(set) var interceptors: InterceptorChain
    private var running: (group: MultiThreadedEventLoopGroup, channel: Channel)?
    /// bind 대기 중인 start. 재진입한 start/stop은 이것을 기다린다.
    private var starting: Task<Int, Error>?
    /// MITM 리프 컨텍스트. 키는 `CertificateAuthority.normalizedHost`(`leaf(for:)`와 같은 정규화).
    /// ponytail: 무제한 캐시. 호스트 수천 개가 문제되면 LRU.
    private var leafContexts: [String: NIOSSLContext] = [:]

    public init(configuration: ProxyConfiguration, certificateAuthority: CertificateAuthority, interceptors: InterceptorChain) {
        (events, eventSink) = AsyncStream.makeStream()
        self.configuration = configuration
        self.certificateAuthority = certificateAuthority
        self.sslPolicy = configuration.sslPolicy
        self.interceptors = interceptors
    }

    /// 실제 바인드된 포트를 반환한다(설정이 0이면 OS 할당).
    public func start() async throws -> Int {
        if let running { return running.channel.localAddress?.port ?? configuration.port }
        if let starting { return try await starting.value }
        let task = Task { () async throws -> Int in
            defer { self.starting = nil }
            let bound = try await self.bind()
            self.running = bound
            return bound.channel.localAddress?.port ?? self.configuration.port
        }
        starting = task
        return try await task.value
    }

    private func bind() async throws -> (group: MultiThreadedEventLoopGroup, channel: Channel) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let upstream = UpstreamClient(group: group, trustRootsDER: configuration.upstreamTrustRootsDER)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [self] channel in
                channel.eventLoop.makeCompletedFuture {
                    let ops = channel.pipeline.syncOperations
                    try ops.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)), name: "http-decoder")
                    try ops.addHandler(ProxyConnectionHandler.makeResponseEncoder(), name: "http-encoder")
                    try ops.addHandler(ProxyConnectionHandler(server: self, upstream: upstream), name: "proxy")
                }
            }
        do {
            return (group, try await bootstrap.bind(host: configuration.bindHost, port: configuration.port).get())
        } catch {
            try? await group.shutdownGracefully()
            if let io = error as? IOError, io.errnoCode == EADDRINUSE { throw ProxyServerError.portInUse(configuration.port) }
            throw error
        }
    }

    public func stop() async {
        if let starting { _ = try? await starting.value }
        guard let running else { return }
        self.running = nil
        try? await running.channel.close()
        try? await running.group.shutdownGracefully()   // 열린 클라이언트 연결도 함께 닫힌다
    }

    public func update(sslPolicy: SSLProxyingPolicy) { self.sslPolicy = sslPolicy }
    public func update(interceptors: InterceptorChain) { self.interceptors = interceptors }

    /// CONNECT 대상 호스트용 서버 TLS 컨텍스트(ALPN http/1.1만). 호스트당 한 번 만든다.
    func leafContext(for rawHost: String) throws -> NIOSSLContext {
        let host = CertificateAuthority.normalizedHost(rawHost)
        if let cached = leafContexts[host] { return cached }
        let leaf = try certificateAuthority.leaf(for: host)
        var config = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(try NIOSSLCertificate(bytes: leaf.certificateDER, format: .der))],
            privateKey: .privateKey(try NIOSSLPrivateKey(bytes: leaf.privateKeyDER, format: .der)))
        config.applicationProtocols = ["http/1.1"]
        let context = try NIOSSLContext(configuration: config)
        leafContexts[host] = context
        return context
    }

    /// 이벤트루프(터널 등)에서 바로 이벤트를 낸다.
    nonisolated func emit(_ event: FlowEvent) { eventSink.yield(event) }

    /// 요청 하나의 수명: 이벤트 → 요청 인터셉터 → (업스트림) → 응답 인터셉터 → 이벤트. 실패는 502로 바꿔 돌려준다.
    /// 요청 체인의 `.respond`도 응답 체인을 거친다. 어느 체인이든 `.drop`이면 `.failed`를 내고 `.drop`을 돌려준다.
    /// 요청 체인이 요청을 바꿨으면 `.requestSent`를 낸다. `.passthrough`는 응답 체인·이후 이벤트 없이 그대로 보낸다.
    /// `note`가 있으면 흐름에 `.tool(note)` 주석을 단다(CONNECT 판정이 복호화를 강제한 연결).
    func exchange(_ request: FlowRequest, clientAddress: String, clientPort: Int? = nil, upstream: UpstreamClient, isDecrypted: Bool = false,
                  note: String? = nil) async -> ExchangeOutcome {
        let id = FlowID()
        let sink = eventSink
        let context = FlowContext(id: id, clientAddress: clientAddress, clientPort: clientPort) { sink.yield(.annotated(id: id, $0)) }
        eventSink.yield(.requestStarted(Flow(id: id, clientAddress: clientAddress, clientPort: clientPort, startedAt: Date(), request: request, isDecrypted: isDecrypted)))
        if let note { context.annotate(.tool(note)) }
        let chain = interceptors
        let response: FlowResponse, sent: FlowRequest
        let (decision, last) = await chain.runRequest(request, context: context)
        if case .passthrough = decision {} else if last != request { eventSink.yield(.requestSent(id: id, request: last)) }
        switch decision {
        case .passthrough(let outgoing):
            do {
                return .respond(try await upstream.send(outgoing, tls: outgoing.scheme == "https", clientAddress: clientAddress))
            } catch is LoopbackBlockedError {
                return .respond(FlowResponse(status: 403, reason: "Forbidden", headers: [], body: Data()))
            } catch {
                return .respond(Self.badGateway(String(describing: error)))
            }
        case .drop:
            return dropped(id)
        case .respond(let local):
            (response, sent) = (local, last)
        case .continue(let outgoing):
            do {
                response = try await upstream.send(outgoing, tls: outgoing.scheme == "https", clientAddress: clientAddress)
                sent = outgoing
            } catch let error as LoopbackBlockedError {
                eventSink.yield(.failed(id: id, error: error.description, completedAt: Date()))
                return .respond(FlowResponse(status: 403, reason: "Forbidden", headers: [], body: Data()))
            } catch {
                let message = Task.isCancelled ? "client disconnected"
                    : Self.upstreamTLSLabel(error).map { "\($0): \(error)" } ?? String(describing: error)
                eventSink.yield(.failed(id: id, error: message, completedAt: Date()))
                return .respond(Self.badGateway(message))
            }
        }
        switch await chain.runResponse(response, for: sent, context: context) {
        case .drop:
            return dropped(id)
        case .continue(let final):
            eventSink.yield(.responseReceived(id: id, response: final, completedAt: Date()))
            return .respond(final)
        }
    }

    static let droppedByRule = "규칙으로 연결 끊김"

    private static func badGateway(_ message: String) -> FlowResponse {
        FlowResponse(status: 502, reason: "Bad Gateway", headers: [.init(name: "Content-Type", value: "text/plain")],
                     body: Data("EyeProxy: upstream error: \(message)".utf8))
    }

    private func dropped(_ id: FlowID) -> ExchangeOutcome {
        eventSink.yield(.failed(id: id, error: Self.droppedByRule, completedAt: Date()))
        return .drop
    }

    /// 업스트림 TLS 오류 분류. 체인 검증 실패는 CERTIFICATE_VERIFY_FAILED 핸드셰이크 실패로, 호스트명 불일치는 NIOSSLExtraError로 온다.
    private static func upstreamTLSLabel(_ error: any Error) -> String? {
        if (error as? NIOSSLExtraError) == .failedToValidateHostname { return "업스트림 인증서 오류" }
        if case NIOSSLError.handshakeFailed(let underlying) = error, "\(underlying)".contains("CERTIFICATE_VERIFY_FAILED") { return "업스트림 인증서 오류" }
        if error is NIOSSLError || error is NIOSSLExtraError || error is BoringSSLError { return "업스트림 TLS 오류" }
        return nil
    }
}
