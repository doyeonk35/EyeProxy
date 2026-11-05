import Foundation
import NIOCore
import NIOHTTP1

/// 클라이언트 쪽 HTTP/1.1 상태 기계: head/body/end를 모아 `FlowRequest`로 만들고, 비동기 처리 결과를 이벤트루프에서 쓴다.
/// ponytail: 파이프라이닝 미지원(응답 순서 보장 없음). URLSession·브라우저는 파이프라이닝하지 않는다.
final class ProxyConnectionHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let server: ProxyServer
    private let upstream: UpstreamClient
    private var head: HTTPRequestHead?
    private var body = Data()

    init(server: ProxyServer, upstream: UpstreamClient) {
        self.server = server
        self.upstream = upstream
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
            case .CONNECT:   // Task 6에서 터널/MITM으로 교체
                write(Self.plain(501, "Not Implemented"), version: head.version, keepAlive: false, context: context)
            default:
                forward(head, body: body, context: context)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    private func forward(_ head: HTTPRequestHead, body: Data, context: ChannelHandlerContext) {
        let keepAlive = head.isKeepAlive
        guard let request = Self.flowRequest(from: head, body: body) else {
            write(Self.plain(400, "Bad Request"), version: head.version, keepAlive: false, context: context)
            return
        }
        let server = self.server, upstream = self.upstream
        let clientAddress = context.channel.remoteAddress?.ipAddress ?? "unknown"
        context.eventLoop.makeFutureWithTask {
            await server.exchange(request, clientAddress: clientAddress, upstream: upstream)
        }.assumeIsolated().whenSuccess { response in
            self.write(response, version: head.version, keepAlive: keepAlive, context: context)
        }
    }

    private func write(_ response: FlowResponse, version: HTTPVersion, keepAlive: Bool, context: ChannelHandlerContext) {
        var headers = HTTPHeaders(response.headers
            .filter { !Self.hopByHop.contains($0.name.lowercased()) }
            .map { ($0.name, $0.value) })
        headers.add(name: "Content-Length", value: String(response.body.count))
        if !keepAlive { headers.add(name: "Connection", value: "close") }
        let status = HTTPResponseStatus(statusCode: response.status, reasonPhrase: response.reason)
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: version, status: status, headers: headers))), promise: nil)
        if !response.body.isEmpty {
            context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(bytes: response.body)))), promise: nil)
        }
        let done = context.writeAndFlush(wrapOutboundOut(.end(nil)))
        if !keepAlive {
            done.assumeIsolated().whenComplete { _ in context.close(promise: nil) }
        }
    }

    /// 절대 URI(`http://host:port/path?q`)만 받는다. origin-form은 Task 7(TLS 원 서버)에서 처리.
    static func flowRequest(from head: HTTPRequestHead, body: Data) -> FlowRequest? {
        guard let url = URLComponents(string: head.uri), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        var path = url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath
        if let query = url.percentEncodedQuery { path += "?" + query }
        let headers = head.headers
            .filter { !strippedRequestHeaders.contains($0.name.lowercased()) }
            .map { HTTPHeader(name: $0.name, value: $0.value) }
        return FlowRequest(method: head.method.rawValue, scheme: scheme, host: host,
                           port: url.port ?? (scheme == "https" ? 443 : 80), path: path, headers: headers, body: body)
    }

    private static func plain(_ status: Int, _ reason: String) -> FlowResponse {
        FlowResponse(status: status, reason: reason, headers: [.init(name: "Content-Type", value: "text/plain")], body: Data(reason.utf8))
    }

    private static let strippedRequestHeaders: Set<String> = ["proxy-connection", "proxy-authorization"]
    /// 본문을 전부 버퍼링해 Content-Length를 새로 쓰므로 원래 프레이밍·연결 헤더는 버린다.
    private static let hopByHop: Set<String> = ["content-length", "transfer-encoding", "connection", "keep-alive"]
}
