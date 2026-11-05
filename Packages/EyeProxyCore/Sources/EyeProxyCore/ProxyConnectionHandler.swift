import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

/// 클라이언트 쪽 HTTP/1.1 상태 기계: head/body/end를 모아 `FlowRequest`로 만들고, 비동기 처리 결과를 이벤트루프에서 쓴다.
/// ponytail: 파이프라이닝 미지원(응답 순서 보장 없음). URLSession·브라우저는 파이프라이닝하지 않는다.
final class ProxyConnectionHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let server: ProxyServer
    private let upstream: UpstreamClient
    private var head: HTTPRequestHead?
    private var body = Data()
    /// 클라이언트가 끊기면 취소해 업스트림 연결도 닫는다.
    private var inFlight: Task<Void, Never>?
    /// MITM으로 TLS를 끝낸 연결이면 원 서버. 요청은 origin-form(`GET /path`)으로 온다.
    private let tlsOrigin: (host: String, port: Int)?

    init(server: ProxyServer, upstream: UpstreamClient, tlsOrigin: (host: String, port: Int)? = nil) {
        self.server = server
        self.upstream = upstream
        self.tlsOrigin = tlsOrigin
    }

    /// 프레이밍은 `write`가 전부 정한다(HEAD/204/304의 원 Content-Length 보존).
    static func makeResponseEncoder() -> HTTPResponseEncoder {
        var config = HTTPResponseEncoder.Configuration()
        config.automaticallySetFramingHeaders = false
        return HTTPResponseEncoder(configuration: config)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let h):
            head = h
            body = Data()
        case .body(let b):
            body.append(contentsOf: b.readableBytesView)
        case .end:
            guard let head else { return }
            self.head = nil
            switch head.method {
            case .CONNECT where tlsOrigin != nil:   // 복호화된 연결 안에서 CONNECT를 다시 중첩하지 않는다
                write(Self.plain(405, "Method Not Allowed"), to: head, keepAlive: false, context: context)
            case .CONNECT:
                connect(head, context: context)
            default:
                forward(head, body: body, context: context)
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        inFlight?.cancel()
        inFlight = nil
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let tlsOrigin, let message = Self.tlsFailureMessage(error) {
            server.emit(.connectionLog(ConnectionLogEntry(id: UUID(), date: Date(), clientAddress: context.channel.remoteAddress?.ipAddress ?? "unknown",
                                                          host: tlsOrigin.host, port: tlsOrigin.port, message: message)))
        }
        context.close(promise: nil)
    }

    /// 클라이언트 쪽 TLS 실패를 로그 문구로. 인증서 alert면 신뢰 안내, 그 외 TLS 오류는 원문.
    /// TLS가 아닌 오류와 close_notify 없는 종료는 nil(로그 안 함).
    static func tlsFailureMessage(_ error: any Error) -> String? {
        switch error {
        case NIOSSLError.uncleanShutdown:
            return nil
        case NIOSSLError.handshakeFailed(let underlying):
            return trustHint(String(describing: underlying)) ?? String(describing: error)
        case is NIOSSLError, is BoringSSLError:
            return String(describing: error)
        default:
            return nil
        }
    }

    /// 기기가 CA를 믿지 않아 보낸 인증서 alert일 때만 안내 문구. 예: "...OPENSSL_internal:TLSV1_ALERT_UNKNOWN_CA" → "unknown_ca"
    static func trustHint(_ boringSSLText: String) -> String? {
        guard let alert = boringSSLText.firstMatch(of: /(?:SSLV3|TLSV1)_ALERT_([A-Z_]+)/).map({ $0.1.lowercased() }),
              certificateAlerts.contains(alert) else { return nil }
        return "기기가 EyeProxy 인증서를 신뢰하지 않습니다 (\(alert)). 기기의 인증서 신뢰 설정을 확인하세요."
    }

    private static let certificateAlerts: Set<String> = [
        "unknown_ca", "bad_certificate", "certificate_unknown", "unsupported_certificate", "certificate_expired", "certificate_revoked",
    ]

    private func forward(_ head: HTTPRequestHead, body: Data, context: ChannelHandlerContext) {
        let keepAlive = head.isKeepAlive
        guard let request = Self.flowRequest(from: head, body: body, tlsOrigin: tlsOrigin) else {
            write(Self.plain(400, "Bad Request"), to: head, keepAlive: false, context: context)
            return
        }
        let server = self.server, upstream = self.upstream
        let clientAddress = context.channel.remoteAddress?.ipAddress ?? "unknown"
        let promise = context.eventLoop.makePromise(of: FlowResponse.self)
        let isDecrypted = tlsOrigin != nil
        inFlight = Task { promise.succeed(await server.exchange(request, clientAddress: clientAddress, upstream: upstream, isDecrypted: isDecrypted)) }
        promise.futureResult.assumeIsolated().whenSuccess { response in
            self.inFlight = nil
            self.write(response, to: head, keepAlive: keepAlive, context: context)
        }
    }

    /// CONNECT 시점의 현재 SSL Proxying 정책으로 MITM 여부를 정한다.
    private func connect(_ head: HTTPRequestHead, context: ChannelHandlerContext) {
        guard let (host, port) = Self.authority(head.uri) else {
            write(Self.plain(400, "Bad Request"), to: head, keepAlive: false, context: context)
            return
        }
        let server = self.server
        // nil = 터널, 컨텍스트 = MITM
        let decision = context.eventLoop.makePromise(of: NIOSSLContext?.self)
        decision.completeWithTask {
            guard await server.sslPolicy.shouldDecrypt(host: host) else { return nil }
            return try await server.leafContext(for: host)
        }
        decision.futureResult.assumeIsolated().whenComplete { result in
            switch result {
            case .success(nil):
                self.tunnel(head, host: host, port: port, context: context)
            case .success(let sslContext?):
                self.intercept(head, host: host, port: port, sslContext: sslContext, context: context)
            case .failure(let error):   // 리프 발급 실패
                server.emit(.connectionLog(ConnectionLogEntry(id: UUID(), date: Date(), clientAddress: context.channel.remoteAddress?.ipAddress ?? "unknown",
                                                              host: host, port: port, message: String(describing: error))))
                self.write(Self.plain(502, "Bad Gateway"), to: head, keepAlive: false, context: context)
            }
        }
    }

    /// MITM: 200 → [decoder, encoder, proxy]를 [TLS, decoder, encoder, proxy(tlsOrigin)]로 바꾼다.
    /// TLS 핸들러를 옛 디코더 바로 뒤에 먼저 꽂아, 디코더 제거 때 넘어오는 이미 읽힌 바이트(ClientHello)가 TLS로 가게 한다.
    private func intercept(_ head: HTTPRequestHead, host: String, port: Int, sslContext: NIOSSLContext, context: ChannelHandlerContext) {
        guard context.channel.isActive else { return }
        let status = HTTPResponseStatus.custom(code: 200, reasonPhrase: "Connection Established")
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: status))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)

        let ops = context.pipeline.syncOperations
        let channel = context.channel
        let tls = NIOSSLServerHandler(context: sslContext)
        let next = ProxyConnectionHandler(server: server, upstream: upstream, tlsOrigin: (host, port))
        do {
            try ops.addHandler(tls, position: .after(ops.context(name: "http-decoder").handler))
        } catch {
            context.close(promise: nil)
            return
        }
        ops.removeHandler(name: "http-encoder", promise: nil)
        // 디코더 제거는 다음 틱에 끝난다(그 전에 남은 바이트를 TLS로 넘긴다). 같은 이름은 그 뒤에야 다시 쓸 수 있다.
        ops.removeHandler(name: "http-decoder").assumeIsolated().whenComplete { removal in
            do {
                try removal.get()
                let ops = channel.pipeline.syncOperations
                let decoder = ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
                let encoder = Self.makeResponseEncoder()
                try ops.addHandler(decoder, name: "http-decoder", position: .after(tls))
                try ops.addHandler(encoder, name: "http-encoder", position: .after(decoder))
                ops.removeHandler(context: context, promise: nil)   // 기본 제거는 동기라 "proxy" 이름이 바로 빈다
                try ops.addHandler(next, name: "proxy", position: .after(encoder))
                channel.pipeline.fireChannelReadComplete()   // TLS가 넘겨받은 바이트에 대한 응답을 flush
            } catch {
                channel.close(promise: nil)
            }
        }
    }

    /// 패스스루: 업스트림 TCP 연결 → 200 → HTTP 핸들러 제거 → 양쪽에 GlueHandler. 바이트는 보지 않는다.
    /// ponytail: half-close 미지원(한쪽 EOF면 양쪽 다 닫는다). 필요하면 allowRemoteHalfClosure를 양쪽에 켠다.
    private func tunnel(_ head: HTTPRequestHead, host: String, port: Int, context: ChannelHandlerContext) {
        let server = self.server
        let id = FlowID()
        let request = FlowRequest(method: "CONNECT", scheme: "https", host: host, port: port, path: "", headers: [], body: Data())
        server.emit(.requestStarted(Flow(id: id, clientAddress: context.channel.remoteAddress?.ipAddress ?? "unknown",
                                         startedAt: Date(), request: request, isTunnel: true)))
        ClientBootstrap(group: context.eventLoop).connect(host: host, port: port).assumeIsolated().whenComplete { result in
            let peer: Channel
            switch result {
            case .failure(let error):
                server.emit(.failed(id: id, error: String(describing: error), completedAt: Date()))
                self.write(FlowResponse(status: 502, reason: "Bad Gateway", headers: [], body: Data()), to: head, keepAlive: false, context: context)
                return
            case .success(let channel):
                peer = channel
            }
            guard context.channel.isActive else {
                peer.close(promise: nil)
                server.emit(.failed(id: id, error: "client disconnected", completedAt: Date()))
                return
            }
            // 200 CONNECT 응답에는 Content-Length/Transfer-Encoding을 넣지 않는다(RFC 9110 §9.3.6).
            let status = HTTPResponseStatus.custom(code: 200, reasonPhrase: "Connection Established")
            context.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: status))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)

            let ops = context.pipeline.syncOperations
            let channel = context.channel
            // 디코더 제거는 다음 틱에 끝나며, 이미 읽힌 바이트(.forwardBytes)는 그때 GlueHandler로 간다. 그 뒤 flush를 위해 readComplete.
            ops.removeHandler(name: "http-decoder").whenComplete { removal in
                if case .failure = removal { channel.close(promise: nil) } else { channel.pipeline.fireChannelReadComplete() }
            }
            ops.removeHandler(name: "http-encoder", promise: nil)
            let (local, remote) = TunnelGlueHandler.matchedPair()
            do {
                try ops.addHandler(local)
                try peer.pipeline.syncOperations.addHandler(remote)
            } catch {
                peer.close(promise: nil)
                context.close(promise: nil)
                return
            }
            channel.closeFuture.whenComplete { _ in
                server.emit(.responseReceived(id: id, response: FlowResponse(status: 200, reason: "Connection Established", headers: [], body: Data()),
                                              completedAt: Date()))
            }
            ops.removeHandler(context: context, promise: nil)
        }
    }

    /// CONNECT authority-form(`host:port`, `[::1]:443`). 포트 필수.
    static func authority(_ uri: String) -> (String, Int)? {
        guard let url = URLComponents(string: "//" + uri), var host = url.host, !host.isEmpty, let port = url.port else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return (host, port)
    }

    /// 인코더 자동 프레이밍은 꺼져 있다. HEAD·1xx·204·304는 본문 없이 원 Content-Length를 그대로 두고,
    /// 나머지는 버퍼링한 본문 길이로 Content-Length를 새로 쓴다.
    private func write(_ response: FlowResponse, to request: HTTPRequestHead, keepAlive: Bool, context: ChannelHandlerContext) {
        let status = HTTPResponseStatus(statusCode: response.status, reasonPhrase: response.reason)
        let hasBody = request.method != .HEAD && status.mayHaveResponseBody
        var headers = HTTPHeaders(response.headers
            .filter { h in
                let name = h.name.lowercased()
                return !Self.hopByHop.contains(name) && !(hasBody && name == "content-length")
            }
            .map { ($0.name, $0.value) })
        if hasBody { headers.add(name: "Content-Length", value: String(response.body.count)) }
        if !keepAlive { headers.add(name: "Connection", value: "close") }
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: request.version, status: status, headers: headers))), promise: nil)
        if hasBody && !response.body.isEmpty {
            context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(bytes: response.body)))), promise: nil)
        }
        let done = context.writeAndFlush(wrapOutboundOut(.end(nil)))
        if !keepAlive {
            done.assumeIsolated().whenComplete { _ in context.close(promise: nil) }
        }
    }

    /// 평문 프록시 요청은 절대 URI(`http://host:port/path?q`), MITM 연결(tlsOrigin)은 origin-form(`/path?q`)만 받는다.
    static func flowRequest(from head: HTTPRequestHead, body: Data, tlsOrigin: (host: String, port: Int)? = nil) -> FlowRequest? {
        let headers = head.headers
            .filter { !strippedRequestHeaders.contains($0.name.lowercased()) }
            .map { HTTPHeader(name: $0.name, value: $0.value) }
        if let tlsOrigin {
            guard head.uri.hasPrefix("/") else { return nil }
            return FlowRequest(method: head.method.rawValue, scheme: "https", host: tlsOrigin.host, port: tlsOrigin.port,
                               path: head.uri, headers: headers, body: body)
        }
        guard let url = URLComponents(string: head.uri), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", var host = url.host, !host.isEmpty else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }   // IPv6 리터럴
        var path = url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath
        if let query = url.percentEncodedQuery { path += "?" + query }
        return FlowRequest(method: head.method.rawValue, scheme: scheme, host: host,
                           port: url.port ?? (scheme == "https" ? 443 : 80), path: path, headers: headers, body: body)
    }

    private static func plain(_ status: Int, _ reason: String) -> FlowResponse {
        FlowResponse(status: status, reason: reason, headers: [.init(name: "Content-Type", value: "text/plain")], body: Data(reason.utf8))
    }

    private static let strippedRequestHeaders: Set<String> = ["proxy-connection", "proxy-authorization"]
    /// 본문은 버퍼링돼 있으므로 원래 전송·연결 헤더는 버린다(content-length는 write에서 따로 처리).
    private static let hopByHop: Set<String> = ["transfer-encoding", "connection", "keep-alive"]
}
