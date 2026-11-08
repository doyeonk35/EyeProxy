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
        if let h = to.host, !h.isEmpty { out.host = h }
        if let p = to.port { out.port = p }

        var path = request.path
        var query: String?
        if let q = path.firstIndex(of: "?") {
            query = String(path[path.index(after: q)...])
            path = String(path[..<q])
        }
        if let mapPath = to.path, !mapPath.isEmpty {
            let body = "/" + mapPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if rule.match.includeSubpaths, let prefix = rule.matchedPrefix, prefix.isEmpty {
                path = (body == "/" ? "" : body) + path
            } else if rule.match.includeSubpaths, let prefix = rule.matchedPrefix,
                      let r = path.range(of: prefix, options: [.anchored, .caseInsensitive]),
                      r.upperBound == path.endIndex || path[r.upperBound] == "/" {
                path = (body == "/" ? "" : body) + path[r.upperBound...]
                if path.isEmpty { path = "/" }
            } else {
                path = body
            }
        }
        if let q = to.query, !q.isEmpty { query = q }
        out.path = path + (query.map { "?" + $0 } ?? "")

        if !rule.preserveHostHeader { out.syncHostHeader() }

        context.annotate(ToolMark.annotation(.mapRemote, detail: rule.name))
        // 끔: 기록은 보낸 요청으로 바뀌고(`requestSent`) 원래 URL을 남긴다. 켬: 표시 URL은 그대로, 실제 전송 URL을 남긴다.
        context.annotate(rule.preserveOriginalURL ? .sentURL(out.url) : .originalURL(request.url))
        return .continue(out)
    }
}

extension FlowRequest {
    /// Host 헤더를 host[:port](기본 포트 생략)로 맞춘다. 없으면 더한다. Core는 요청의 Host 헤더를 그대로 보낸다.
    mutating func syncHostHeader() {
        let isDefault = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
        let name = host.contains(":") ? "[\(host)]" : host
        let value = isDefault ? name : "\(name):\(port)"
        if let i = headers.firstIndex(where: { $0.name.caseInsensitiveCompare("Host") == .orderedSame }) {
            headers[i].value = value
        } else {
            headers.append(HTTPHeader(name: "Host", value: value))
        }
    }
}
