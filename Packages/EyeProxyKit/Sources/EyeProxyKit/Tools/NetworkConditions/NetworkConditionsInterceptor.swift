import EyeProxyCore
import Foundation

/// 켜진 규칙 하나의 프로필대로 요청 단위로 시간을 늦춘다(§5.7): 지연 + 크기/대역폭, 손실 확률로 1초 추가.
public struct NetworkConditionsInterceptor: RequestInterceptor, ResponseInterceptor, ConnectInterceptor {
    let rule: NetworkConditionRule
    let random: @Sendable () -> Double

    public init(rule: NetworkConditionRule, random: @escaping @Sendable () -> Double = { .random(in: 0..<1) }) {
        self.rule = rule
        self.random = random
    }

    private var profile: NetworkProfile { rule.networkProfile }

    private func targets(_ host: String) -> Bool {
        rule.isEnabled && (rule.isSystemWide || MatchRule(url: rule.url).hostGlobMatches(host))
    }

    /// `min + (max - min) * random()`. 상한 ≤ 0이면 무제한(nil).
    private func speed(max: Int, min: Int?) -> Int? {
        guard max > 0 else { return nil }
        let lo = Swift.min(Swift.max(min ?? max / 2, 0), max)
        return lo + Int(Double(max - lo) * random())
    }

    private func wait(bytes: Int, bandwidth: Int?) async -> Bool {
        var seconds = Double(Swift.max(profile.delay, 0)) / 1000
        if let b = bandwidth, b > 0 { seconds += Double(bytes) / Double(b) }
        if random() * 100 < Swift.min(Swift.max(profile.packageDrop, 0), 100) { seconds += 1 }
        do { try await Task.sleep(for: .seconds(seconds)); return true } catch { return false }
    }

    private func hang() async {
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)) }
    }

    public func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision {
        guard targets(request.host) else { return .continue(request) }
        if profile.isAllLostConnection { await hang(); return .drop }
        let up = speed(max: profile.uploadBandwidth, min: profile.uploadMin)
        return await wait(bytes: request.body.count, bandwidth: up) ? .continue(request) : .drop
    }

    public func intercept(_ response: FlowResponse, for request: FlowRequest, context: FlowContext) async -> ResponseDecision {
        guard targets(request.host) else { return .continue(response) }
        if profile.isAllLostConnection { await hang(); return .drop }
        let down = speed(max: profile.downloadBandwidth, min: profile.downloadMin)
        return await wait(bytes: response.body.count, bandwidth: down) ? .continue(response) : .drop
    }

    public func intercept(host: String, port: Int, context: ConnectContext) async -> ConnectVerdict {
        guard targets(host) else { return ConnectVerdict() }
        return ConnectVerdict(shaping: TunnelShaping(
            latencyMS: Swift.max(profile.delay, 0),
            downBytesPerSecond: speed(max: profile.downloadBandwidth, min: profile.downloadMin),
            upBytesPerSecond: speed(max: profile.uploadBandwidth, min: profile.uploadMin),
            blackhole: profile.isAllLostConnection))
    }
}
