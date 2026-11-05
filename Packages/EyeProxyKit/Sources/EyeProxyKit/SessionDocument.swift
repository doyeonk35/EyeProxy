import EyeProxyCore
import Foundation

public enum SessionDocument {
    public static let pathExtension = "eyeproxy"

    private struct Index: Codable {
        var version: Int
        var flows: [Flow]
        var connectionLog: [ConnectionLogEntry]
    }

    /// 디렉터리 패키지: index.json(바디 제외) + bodies/<flowID>.req|.res. 기존 경로는 통째로 교체한다.
    public static func save(flows: [Flow], connectionLog: [ConnectionLogEntry], to url: URL) throws {
        let fm = FileManager.default
        let tmp = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).tmp")
        let bodies = tmp.appending(path: "bodies")
        try fm.createDirectory(at: bodies, withIntermediateDirectories: true)
        do {
            var stripped = flows
            for i in stripped.indices {
                let name = stripped[i].id.rawValue.uuidString
                if !stripped[i].request.body.isEmpty { try stripped[i].request.body.write(to: bodies.appending(path: name + ".req")) }
                if let body = stripped[i].response?.body, !body.isEmpty { try body.write(to: bodies.appending(path: name + ".res")) }
                stripped[i].request.body = Data()
                stripped[i].response?.body = Data()
            }
            try encoder.encode(Index(version: 1, flows: stripped, connectionLog: connectionLog)).write(to: tmp.appending(path: "index.json"))
            if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: tmp) } else { try fm.moveItem(at: tmp, to: url) }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    public static func load(from url: URL) throws -> (flows: [Flow], connectionLog: [ConnectionLogEntry]) {
        let index = try decoder.decode(Index.self, from: Data(contentsOf: url.appending(path: "index.json")))
        guard index.version == 1 else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "지원하지 않는 세션 버전: \(index.version)"]) }
        var flows = index.flows
        for i in flows.indices {
            let base = url.appending(path: "bodies/\(flows[i].id.rawValue.uuidString)")
            if let d = try? Data(contentsOf: base.appendingPathExtension("req")) { flows[i].request.body = d }
            if flows[i].response != nil, let d = try? Data(contentsOf: base.appendingPathExtension("res")) { flows[i].response?.body = d }
        }
        return (flows, index.connectionLog)
    }

    // iso8601은 초 미만을 버려 왕복이 정확하지 않으므로 deferredToDate(Double 초) 사용.
    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .deferredToDate; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .deferredToDate; return d }
}
