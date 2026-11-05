import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1

public struct ProxyConfiguration: Sendable {
    public var bindHost: String
    public var port: Int
    public var sslPolicy: SSLProxyingPolicy

    public init(bindHost: String = "0.0.0.0", port: Int = 9090, sslPolicy: SSLProxyingPolicy = .init()) {
        self.bindHost = bindHost
        self.port = port
        self.sslPolicy = sslPolicy
    }
}

public enum ProxyServerError: Error, Equatable {
    case portInUse(Int)
    case notRunning
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
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let upstream = UpstreamClient(group: group)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [self] channel in
                channel.eventLoop.makeCompletedFuture {
                    let ops = channel.pipeline.syncOperations
                    try ops.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)), name: "http-decoder")
                    try ops.addHandler(HTTPResponseEncoder(), name: "http-encoder")
                    try ops.addHandler(ProxyConnectionHandler(server: self, upstream: upstream), name: "proxy")
                }
            }
        do {
            let channel = try await bootstrap.bind(host: configuration.bindHost, port: configuration.port).get()
            running = (group, channel)
            return channel.localAddress?.port ?? configuration.port
        } catch {
            try? await group.shutdownGracefully()
            if let io = error as? IOError, io.errnoCode == EADDRINUSE { throw ProxyServerError.portInUse(configuration.port) }
            throw error
        }
    }

    public func stop() async {
        guard let running else { return }
        self.running = nil
        try? await running.channel.close()
        try? await running.group.shutdownGracefully()   // 열린 클라이언트 연결도 함께 닫힌다
    }

    public func update(sslPolicy: SSLProxyingPolicy) { self.sslPolicy = sslPolicy }
    public func update(interceptors: InterceptorChain) { self.interceptors = interceptors }

    /// 요청 하나의 수명: 이벤트 → 요청 인터셉터 → 업스트림 → 응답 인터셉터 → 이벤트. 실패는 502로 바꿔 돌려준다.
    func exchange(_ request: FlowRequest, clientAddress: String, upstream: UpstreamClient) async -> FlowResponse {
        let id = FlowID()
        let context = FlowContext(id: id, clientAddress: clientAddress)
        eventSink.yield(.requestStarted(Flow(id: id, clientAddress: clientAddress, startedAt: Date(), request: request)))
        let chain = interceptors
        switch await chain.runRequest(request, context: context) {
        case .respond(let response):
            eventSink.yield(.responseReceived(id: id, response: response, completedAt: Date()))
            return response
        case .continue(let outgoing):
            do {
                let raw = try await upstream.send(outgoing, tls: outgoing.scheme == "https")
                let response = await chain.runResponse(raw, for: outgoing, context: context)
                eventSink.yield(.responseReceived(id: id, response: response, completedAt: Date()))
                return response
            } catch {
                let message = String(describing: error)
                eventSink.yield(.failed(id: id, error: message, completedAt: Date()))
                return FlowResponse(status: 502, reason: "Bad Gateway", headers: [.init(name: "Content-Type", value: "text/plain")],
                                    body: Data("EyeProxy: upstream error: \(message)".utf8))
            }
        }
    }
}
