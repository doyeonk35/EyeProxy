import EyeProxyCore
import Foundation

/// 첫 일치 Map Remote 규칙으로 요청 목적지를 바꿔 업스트림으로 보낸다.
public struct MapRemoteInterceptor: RequestInterceptor {
    let rules: RuleTree<MapRemoteRule>

    public init(rules: RuleTree<MapRemoteRule>) { self.rules = rules }

    public func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision {
        guard let rule = rules.firstMatch(request) else { return .continue(request) }
        let to = rule.mapTo
        var out = request

        if let s = to.scheme?.lowercased(), s == "http" || s == "https" {
            let oldDefault = request.scheme == "http" ? 80 : 443
            out.scheme = s
            if to.port == nil, request.port == oldDefault { out.port = s == "http" ? 80 : 443 }
        }
        if let h = to.host { out.host = h }
        if let p = to.port { out.port = p }

        var path = request.path
        var query: String?
        if let q = path.firstIndex(of: "?") {
            query = String(path[path.index(after: q)...])
            path = String(path[..<q])
        }
        if let mapPath = to.path {
            let body = "/" + mapPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if rule.match.includeSubpaths, let prefix = rule.matchedPrefix,
               let r = path.range(of: prefix, options: [.anchored, .caseInsensitive]),
               r.upperBound == path.endIndex || path[r.upperBound] == "/" {
                path = (body == "/" ? "" : body) + path[r.upperBound...]
                if path.isEmpty { path = "/" }
            } else {
                path = body
            }
        }
        if let q = to.query { query = q }
        out.path = path + (query.map { "?" + $0 } ?? "")

        if !rule.preserveHostHeader {
            let isDefault = (out.scheme == "http" && out.port == 80) || (out.scheme == "https" && out.port == 443)
            let host = out.host.contains(":") ? "[\(out.host)]" : out.host
            let value = isDefault ? host : "\(host):\(out.port)"
            if let i = out.headers.firstIndex(where: { $0.name.caseInsensitiveCompare("Host") == .orderedSame }) {
                out.headers[i].value = value
            } else {
                out.headers.append(HTTPHeader(name: "Host", value: value))
            }
        }

        context.annotate(.tool("Map Remote: \(rule.name)"))
        if rule.preserveOriginalURL { context.annotate(.originalURL(request.url)) }
        return .continue(out)
    }
}
