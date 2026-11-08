import EyeProxyCore
import Foundation

/// 도구 규칙(Map Local/Remote, Breakpoint, Block/Allow)이 따르는 공통 모양.
/// 각 규칙은 Proxyman 노드의 `_0` 페이로드를 `ProxymanKey`로 직접 코딩한다.
public protocol ToolRule: Codable, Equatable, Sendable, Identifiable where ID == String {
    var id: String { get set }
    var name: String { get set }
    var isEnabled: Bool { get set }
    var match: MatchRule { get set }
}

/// 아무 문자열이나 받는 코딩 키. `"url"`처럼 문자열 리터럴로 쓴다.
public struct ProxymanKey: CodingKey, ExpressibleByStringLiteral, Sendable {
    public let stringValue: String
    public var intValue: Int? { nil }
    public init(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { nil }
    public init(stringLiteral value: String) { stringValue = value }
}

/// Proxyman 폴더 노드(모양은 확인 안 됨, 가정).
public struct RuleFolder<Rule: ToolRule>: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var children: [RuleNode<Rule>]

    public init(id: String, name: String, isEnabled: Bool = true, children: [RuleNode<Rule>] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.children = children
    }
}

/// `{"nodeType":{"node":{"_0":규칙}}}` 또는 `{"nodeType":{"folder":{"_0":폴더}}}`.
public indirect enum RuleNode<Rule: ToolRule>: Codable, Equatable, Sendable, Identifiable {
    case rule(Rule)
    case folder(RuleFolder<Rule>)

    public var id: String {
        switch self {
        case .rule(let r): r.id
        case .folder(let f): f.id
        }
    }

    public init(from decoder: Decoder) throws {
        let type = try decoder.container(keyedBy: ProxymanKey.self).nestedContainer(keyedBy: ProxymanKey.self, forKey: "nodeType")
        if type.contains("node") {
            self = .rule(try type.nestedContainer(keyedBy: ProxymanKey.self, forKey: "node").decode(Rule.self, forKey: "_0"))
        } else if type.contains("folder") {
            self = .folder(try type.nestedContainer(keyedBy: ProxymanKey.self, forKey: "folder").decode(RuleFolder<Rule>.self, forKey: "_0"))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: type.codingPath, debugDescription: "알 수 없는 노드 종류"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ProxymanKey.self)
        var type = c.nestedContainer(keyedBy: ProxymanKey.self, forKey: "nodeType")
        switch self {
        case .rule(let r):
            var payload = type.nestedContainer(keyedBy: ProxymanKey.self, forKey: "node")
            try payload.encode(r, forKey: "_0")
        case .folder(let f):
            var payload = type.nestedContainer(keyedBy: ProxymanKey.self, forKey: "folder")
            try payload.encode(f, forKey: "_0")
        }
    }
}

/// 도구 하나의 규칙 트리. 디스크 형식은 `{"nodes":[…]}`.
public struct RuleTree<Rule: ToolRule>: Codable, Equatable, Sendable {
    public var nodes: [RuleNode<Rule>]

    public init(nodes: [RuleNode<Rule>] = []) { self.nodes = nodes }

    /// 깊이 우선으로 펼친 켜진 규칙. 꺼진 폴더 하위는 뺀다.
    public var enabledRules: [Rule] {
        func walk(_ nodes: [RuleNode<Rule>]) -> [Rule] {
            nodes.flatMap { node -> [Rule] in
                switch node {
                case .rule(let r): r.isEnabled ? [r] : []
                case .folder(let f): f.isEnabled ? walk(f.children) : []
                }
            }
        }
        return walk(nodes)
    }

    // ponytail: 요청마다 규칙을 펼친다. 규칙이 수천 개가 되면 펼친 목록을 캐시.
    public func firstMatch(_ request: FlowRequest) -> Rule? {
        enabledRules.first { $0.match.matches(request) }
    }

    /// 외부 입력용. `{"nodes":[…]}`(디스크)와 `[…]`(Proxyman 내보내기) 둘 다 받는다.
    /// 디코드 안 되는 노드(폴더 안 포함)는 건너뛰고 센다. JSON이 아니면 throw.
    public static func decodeLenient(_ data: Data) throws -> (tree: RuleTree, skipped: Int) {
        let root = try JSONDecoder().decode(LenientRoot.self, from: data)
        let (nodes, skipped) = LenientNode.collect(root.nodes)
        return (RuleTree(nodes: nodes), skipped)
    }

    public func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    public func encodedAsProxymanExport() throws -> Data {
        try Self.encoder.encode(nodes)
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }

    // MARK: - 관대한 디코딩

    private struct LenientRoot: Decodable {
        let nodes: [LenientNode]

        init(from decoder: Decoder) throws {
            if (try? decoder.unkeyedContainer()) != nil {
                nodes = try [LenientNode](from: decoder)
            } else {
                nodes = try decoder.container(keyedBy: ProxymanKey.self).decode([LenientNode].self, forKey: "nodes")
            }
        }
    }

    /// 절대 throw하지 않는 노드. 실패하면 `node == nil`, `skipped`에 센 수를 담는다.
    private struct LenientNode: Decodable {
        var node: RuleNode<Rule>?
        var skipped = 0

        init(from decoder: Decoder) {
            do {
                let type = try decoder.container(keyedBy: ProxymanKey.self).nestedContainer(keyedBy: ProxymanKey.self, forKey: "nodeType")
                guard type.contains("folder") else {
                    node = try RuleNode(from: decoder)
                    return
                }
                let f = try type.nestedContainer(keyedBy: ProxymanKey.self, forKey: "folder").nestedContainer(keyedBy: ProxymanKey.self, forKey: "_0")
                let (children, skippedChildren) = Self.collect(try f.decode([LenientNode].self, forKey: "children"))
                node = .folder(RuleFolder(
                    id: try f.decode(String.self, forKey: "id"),
                    name: try f.decode(String.self, forKey: "name"),
                    isEnabled: try f.decode(Bool.self, forKey: "isEnabled"),
                    children: children
                ))
                skipped = skippedChildren
            } catch {
                node = nil
                skipped = 1
            }
        }

        static func collect(_ list: [LenientNode]) -> ([RuleNode<Rule>], Int) {
            (list.compactMap(\.node), list.reduce(0) { $0 + $1.skipped })
        }
    }
}

// MARK: - MatchRule ↔ Proxyman 필드

extension MatchRule {
    private struct MethodName: Codable { var name: String }

    /// Proxyman 규칙 페이로드에서 매칭 필드를 읽는다. `url`이 없으면 throw.
    /// EyeProxy 전용 `eyeproxy.queryMode`/`queryItems`. 구버전 `eyeproxy.ignoreQuery`만 있으면 true → `.ignore`, false → `.exact`.
    /// `eyeproxy`가 없으면(Proxyman 규칙) `.exact`.
    public init(proxymanFields c: KeyedDecodingContainer<ProxymanKey>) throws {
        var methods = MethodMatch.any
        if c.contains("method") {
            let m = try c.nestedContainer(keyedBy: ProxymanKey.self, forKey: "method")
            if m.contains("exact") { methods = .exact(try m.decode([MethodName].self, forKey: "exact").map(\.name)) }
        }
        var queryMode = QueryMode.exact
        var conditions: [QueryCondition] = []
        if c.contains("eyeproxy") {
            let e = try c.nestedContainer(keyedBy: ProxymanKey.self, forKey: "eyeproxy")
            let legacy = try e.decodeIfPresent(Bool.self, forKey: "ignoreQuery") == true ? QueryMode.ignore : .exact
            queryMode = try e.decodeIfPresent(String.self, forKey: "queryMode").flatMap(QueryMode.init(rawValue:)) ?? legacy
            conditions = try e.decodeIfPresent([QueryCondition].self, forKey: "queryItems") ?? []
        }
        self.init(
            url: try c.decode(String.self, forKey: "url"),
            mode: try c.decodeIfPresent(String.self, forKey: "regex").flatMap(MatchMode.init(rawValue:)) ?? .wildcard,
            methods: methods,
            includeSubpaths: try c.decodeIfPresent(Bool.self, forKey: "isIncludingPaths") ?? false,
            queryMode: queryMode,
            queryConditions: conditions,
            graphQLQueryName: try c.decodeIfPresent(String.self, forKey: "graphQLQueryName")
        )
    }

    public func encode(proxymanFields c: inout KeyedEncodingContainer<ProxymanKey>) throws {
        try c.encode(url, forKey: "url")
        try c.encode(mode.rawValue, forKey: "regex")
        var m = c.nestedContainer(keyedBy: ProxymanKey.self, forKey: "method")
        switch methods {
        case .any: _ = m.nestedContainer(keyedBy: ProxymanKey.self, forKey: "any")
        case .exact(let list): try m.encode(list.map(MethodName.init), forKey: "exact")
        }
        try c.encode(includeSubpaths, forKey: "isIncludingPaths")
        try c.encode(graphQLQueryName, forKey: "graphQLQueryName")
        var e = c.nestedContainer(keyedBy: ProxymanKey.self, forKey: "eyeproxy")
        try e.encode(queryMode.rawValue, forKey: "queryMode")
        // 이전 빌드가 읽어도 크게 어긋나지 않게 함께 쓴다.
        try e.encode(queryMode == .ignore, forKey: "ignoreQuery")
        // 모드는 조건을 쓸지만 정한다. 표는 모드와 상관없이 남겨 모드를 바꿔 저장해도 잃지 않게 한다.
        if !queryConditions.isEmpty { try e.encode(queryConditions, forKey: "queryItems") }
    }
}
