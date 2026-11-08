import EyeProxyCore
import Foundation

/// 첫 일치 Map Local 규칙의 로컬 파일로 응답한다. 파일이 없으면 실제 서버로 보낸다.
public struct MapLocalInterceptor: RequestInterceptor {
    let rules: RuleTree<MapLocalRule>
    let readFile: @Sendable (URL) throws -> Data

    public init(rules: RuleTree<MapLocalRule>, readFile: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }) {
        self.rules = rules
        self.readFile = readFile
    }

    public func intercept(_ request: FlowRequest, context: FlowContext) async -> RequestDecision {
        guard let rule = rules.firstMatch(request) else { return .continue(request) }
        let response: FlowResponse
        if rule.useDirectory {
            guard let dir = rule.directoryPath, let rel = rule.relativePath(for: request),
                  let r = try? HTTPMessageFile.response(forLocalFile: Self.url(dir).appendingPathComponent(rel))
            else { return .continue(request) }
            response = r
        } else {
            guard let path = rule.localFile?.path, let r = try? load(Self.url(path)) else {
                context.annotate(.tool("Map Local 파일 없음: \(rule.name)"))
                return .continue(request)
            }
            response = r
        }
        context.annotate(.tool("Map Local: \(rule.name)"))
        if let s = rule.delaySeconds, s > 0 {
            try? await Task.sleep(for: .seconds(s))
            if Task.isCancelled { return .drop }
        }
        return .respond(response)
    }

    /// `.http`/`.json`은 HTTP 메시지로 읽고, 상태줄이 아니면 일반 파일 본문으로 쓴다.
    private func load(_ url: URL) throws -> FlowResponse {
        guard ["http", "json"].contains(url.pathExtension.lowercased()) else { return try HTTPMessageFile.response(forLocalFile: url) }
        do {
            return try HTTPMessageFile.parse(try readFile(url), fileURLBase: url.deletingLastPathComponent())
        } catch HTTPMessageFileError.badStatusLine {
            return try HTTPMessageFile.response(forLocalFile: url)
        }
    }

    private static func url(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}
