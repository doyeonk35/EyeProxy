import EyeProxyCore
import Foundation

/// 체인을 만들 때 쓰는 모든 도구 규칙의 스냅샷.
public struct RuleSet: Sendable {
    public var mapLocal: RuleTree<MapLocalRule>
    public var mapRemote: RuleTree<MapRemoteRule>
    public var breakpoint: RuleTree<BreakpointRule>
    public var block: RuleTree<BlockRule>
    public var allow: RuleTree<AllowRule>
    public var networkConditions: [NetworkConditionRule]

    public init(mapLocal: RuleTree<MapLocalRule> = .init(), mapRemote: RuleTree<MapRemoteRule> = .init(),
                breakpoint: RuleTree<BreakpointRule> = .init(), block: RuleTree<BlockRule> = .init(),
                allow: RuleTree<AllowRule> = .init(), networkConditions: [NetworkConditionRule] = []) {
        self.mapLocal = mapLocal
        self.mapRemote = mapRemote
        self.breakpoint = breakpoint
        self.block = block
        self.allow = allow
        self.networkConditions = networkConditions
    }
}

extension RuleStore {
    public var ruleSet: RuleSet {
        RuleSet(mapLocal: tree(.mapLocal), mapRemote: tree(.mapRemote), breakpoint: tree(.breakpoint),
                block: tree(.blockList), allow: tree(.allowList), networkConditions: networkConditions)
    }
}

/// 스위치·규칙으로 인터셉터 체인을 조립한다(스펙 §4.5 순서).
public enum ToolPipeline {
    /// `sslPolicy`: 현재 SSL Proxying 설정. 바뀌면 체인을 다시 만들어야 한다(자동 복호화가 이것을 본다).
    public static func chain(rules: RuleSet, switches: ToolSwitches, sslPolicy: SSLProxyingPolicy, breakpoints: BreakpointCenter,
                             appPath: @escaping AppPathLookup, base: [any RequestInterceptor]) -> InterceptorChain {
        let allow = switches.allowList ? AllowInterceptor(rules: rules.allow) : nil
        let block = switches.blockList ? BlockInterceptor(rules: rules.block, appPath: appPath) : nil
        let noCaching = switches.noCaching ? NoCachingInterceptor() : nil
        let mapRemote = switches.mapRemote ? MapRemoteInterceptor(rules: rules.mapRemote) : nil
        let mapLocal = switches.mapLocal ? MapLocalInterceptor(rules: rules.mapLocal) : nil
        let breakpoint = switches.breakpoint ? BreakpointInterceptor(rules: rules.breakpoint, center: breakpoints) : nil
        let network = switches.networkConditions
            ? rules.networkConditions.first(where: \.isEnabled).map { NetworkConditionsInterceptor(rule: $0) } : nil
        let autoDecrypt = AutoDecryptInterceptor(hosts: autoDecryptHosts(rules: rules, switches: switches), sslPolicy: sslPolicy)

        let request: [(any RequestInterceptor)?] = [allow, block, noCaching, mapRemote, mapLocal, breakpoint, network]
        let response: [(any ResponseInterceptor)?] = [noCaching, breakpoint, network]
        let connect: [(any ConnectInterceptor)?] = [allow, block, autoDecrypt, network]
        return InterceptorChain(request: base + request.compactMap { $0 }, response: response.compactMap { $0 },
                                connect: connect.compactMap { $0 })
    }

    /// 켜진 도구의 켜진 규칙이 가리키는 호스트(§4.4). Block·Allow는 CONNECT에서 판정할 수 없는(경로 등이 있는) 규칙만.
    public static func autoDecryptHosts(rules: RuleSet, switches: ToolSwitches) -> [(pattern: String, ruleName: String)] {
        func hosts<R: ToolRule>(_ on: Bool, _ tree: RuleTree<R>, pathOnly: Bool = false) -> [(pattern: String, ruleName: String)] {
            guard on else { return [] }
            return tree.enabledRules.compactMap { r in
                guard let host = r.match.hostPattern, !pathOnly || r.match.connectHostPattern == nil else { return nil }
                return (host, r.name)
            }
        }
        return hosts(switches.breakpoint, rules.breakpoint) + hosts(switches.mapLocal, rules.mapLocal)
            + hosts(switches.mapRemote, rules.mapRemote) + hosts(switches.blockList, rules.block, pathOnly: true)
            + hosts(switches.allowList, rules.allow, pathOnly: true)
    }

    /// 규칙 호스트면 SSL Proxying 목록에 없어도 복호화한다. SSL Proxying이 꺼져 있으면 아무것도 하지 않고,
    /// 목록이 이미 복호화하는 호스트는 목록에 맡긴다(메모 없음).
    public struct AutoDecryptInterceptor: ConnectInterceptor {
        let hosts: [(pattern: String, ruleName: String)]
        let sslPolicy: SSLProxyingPolicy

        public init(hosts: [(pattern: String, ruleName: String)], sslPolicy: SSLProxyingPolicy) {
            self.hosts = hosts
            self.sslPolicy = sslPolicy
        }

        public func intercept(host: String, port: Int, context: ConnectContext) async -> ConnectVerdict {
            guard sslPolicy.isEnabled, !sslPolicy.shouldDecrypt(host: host),
                  let hit = hosts.first(where: { MatchRule(url: $0.pattern).hostGlobMatches(host) }) else { return ConnectVerdict() }
            return ConnectVerdict(action: .decrypt, note: "자동 복호화(규칙: \(hit.ruleName))")
        }
    }
}
