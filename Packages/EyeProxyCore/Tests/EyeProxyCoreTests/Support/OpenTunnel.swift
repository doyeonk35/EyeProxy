import Foundation
import NIOCore
import NIOPosix

/// 프록시에 `CONNECT target`을 보내고 200을 받은 뒤 그 연결을 열어 둔 채 돌려준다(기기가 터널을 오래 쓰는 상황).
func openTunnel(proxyPort: Int, target: String) async throws -> Channel {
    let loop = MultiThreadedEventLoopGroup.singleton.next()
    let established = loop.makePromise(of: Void.self)
    let deadline = loop.scheduleTask(in: .seconds(10)) { established.fail(ConnectRefused(status: "timed out")) }
    defer { deadline.cancel() }
    let channel = try await ClientBootstrap(group: loop)
        .channelInitializer { channel in
            channel.eventLoop.makeCompletedFuture {
                try channel.pipeline.syncOperations.addHandler(AwaitConnectEstablished(promise: established))
            }
        }
        .connect(host: "127.0.0.1", port: proxyPort).get()
    var request = channel.allocator.buffer(capacity: 128)
    request.writeString("CONNECT \(target) HTTP/1.1\r\nHost: \(target)\r\n\r\n")
    try await channel.writeAndFlush(request)
    try await established.futureResult.get()
    return channel
}

/// 응답에 `200`이 보이면 promise를 이룬다. 그 뒤 바이트는 버린다.
private final class AwaitConnectEstablished: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let promise: EventLoopPromise<Void>
    private var seen = ""
    init(promise: EventLoopPromise<Void>) { self.promise = promise }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        seen += buffer.readString(length: buffer.readableBytes) ?? ""
        if seen.contains(" 200 ") { promise.succeed(()) }
    }

    func channelInactive(context: ChannelHandlerContext) {
        promise.fail(ConnectRefused(status: "closed before CONNECT response"))
        context.fireChannelInactive()
    }
}

/// 채널이 `seconds` 안에 닫히면 true. (closeFuture.get()은 취소되지 않아 기다리다 멈출 수 있으므로 상태를 짧게 확인한다.)
func waitUntilClosed(_ channel: Channel, seconds: Double = 5) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while channel.isActive, Date() < end { try? await Task.sleep(for: .milliseconds(50)) }
    return !channel.isActive
}
