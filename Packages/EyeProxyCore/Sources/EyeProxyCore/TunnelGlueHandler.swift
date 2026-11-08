//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
//
// Ported from swift-nio-examples `connect-proxy/Sources/ConnectProxy/GlueHandler.swift` (renamed).
// 두 채널을 같은 EventLoop에 두고 바이트를 양방향으로 그대로 옮긴다. 백프레셔는 상대가 쓰기 불가면 read()를 미룬다.
// shaping이 있으면 읽은 청크와 닫기를 순서대로 늦춰 전달한다(EyeProxy 추가).

import NIOCore

final class TunnelGlueHandler {
    private var partner: TunnelGlueHandler?
    private var context: ChannelHandlerContext?
    private var pendingRead: Bool = false
    private let shaping: TunnelShaping?
    /// 이 핸들러가 읽는 방향의 속도.
    private let bytesPerSecond: Int?
    /// 직전 청크가 (속도 제한) 링크를 다 지난 시각. 전달은 그 뒤 `latencyMS`.
    private var linkFree = NIODeadline.uptimeNanoseconds(0)
    /// shaping으로 늦춰 아직 전달하지 않은 바이트. `maxPendingBytes`를 넘으면 read()를 미룬다(역압).
    private(set) var pendingBytes = 0
    static let maxPendingBytes = 1 << 20

    private init(shaping: TunnelShaping?, bytesPerSecond: Int?) {
        self.shaping = shaping
        self.bytesPerSecond = bytesPerSecond
    }
}

extension TunnelGlueHandler {
    /// first = 클라이언트 쪽(올림), second = 업스트림 쪽(내림).
    static func matchedPair(shaping: TunnelShaping? = nil) -> (TunnelGlueHandler, TunnelGlueHandler) {
        let first = TunnelGlueHandler(shaping: shaping, bytesPerSecond: shaping?.upBytesPerSecond)
        let second = TunnelGlueHandler(shaping: shaping, bytesPerSecond: shaping?.downBytesPerSecond)
        first.partner = second
        second.partner = first
        return (first, second)
    }
}

extension TunnelGlueHandler {
    private func partnerWrite(_ data: NIOAny) {
        self.context?.write(data, promise: nil)
    }

    private func partnerFlush() {
        self.context?.flush()
    }

    private func partnerWriteEOF() {
        self.context?.close(mode: .output, promise: nil)
    }

    private func partnerCloseFull() {
        self.context?.close(promise: nil)
    }

    private func partnerBecameWritable() {
        if self.pendingRead, self.pendingBytes <= Self.maxPendingBytes {
            self.pendingRead = false
            self.context?.read()
        }
    }

    private var partnerWritable: Bool {
        self.context?.channel.isWritable ?? false
    }

    /// shaping이 없으면 바로, 있으면 앞 청크 뒤에 `크기/속도`만큼 줄 서고 `latencyMS` 뒤에 실행한다(순서 유지).
    /// 상대는 지금 잡아 둔다(채널이 닫히면 handlerRemoved가 partner를 지운다).
    /// 늦춘 바이트가 `maxPendingBytes`를 넘으면 read()가 멈추고, 전달로 그 아래가 되면 미뤘던 read()를 다시 한다.
    private func deliver(_ bytes: Int, context: ChannelHandlerContext, _ action: @escaping (TunnelGlueHandler?) -> Void) {
        let partner = self.partner
        guard let shaping else { return action(partner) }
        var free = max(linkFree, .now())
        if let rate = bytesPerSecond, rate > 0 { free = free + .nanoseconds(Int64(bytes) * 1_000_000_000 / Int64(rate)) }
        linkFree = free
        pendingBytes += bytes
        context.eventLoop.assumeIsolated().scheduleTask(deadline: free + .milliseconds(Int64(shaping.latencyMS))) {
            action(partner)
            self.pendingBytes -= bytes
            if self.pendingRead, let context = self.context {
                self.pendingRead = false
                self.read(context: context)   // 아직 막히면 다시 pendingRead
            }
        }
    }
}

extension TunnelGlueHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer   // 양쪽 모두 원시 바이트. unwrap은 shaping 때만.
    typealias OutboundIn = NIOAny
    typealias OutboundOut = NIOAny

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        self.partner = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard let shaping else { self.partner?.partnerWrite(data); return }
        guard !shaping.blackhole else { return }
        deliver(unwrapInboundIn(data).readableBytes, context: context) { partner in
            partner?.partnerWrite(data)
            partner?.partnerFlush()
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        self.partner?.partnerFlush()
    }

    func channelInactive(context: ChannelHandlerContext) {
        deliver(0, context: context) { $0?.partnerCloseFull() }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event {
            // We have read EOF.
            deliver(0, context: context) { $0?.partnerWriteEOF() }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        deliver(0, context: context) { $0?.partnerCloseFull() }
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable {
            self.partner?.partnerBecameWritable()
        }
    }

    func read(context: ChannelHandlerContext) {
        if let partner = self.partner, partner.partnerWritable, self.pendingBytes <= Self.maxPendingBytes {
            context.read()
        } else {
            self.pendingRead = true
        }
    }
}
