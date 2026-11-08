import EyeProxyCore
import Foundation

public enum SessionDocument {
    public static let pathExtension = "eyeproxy"

    private struct Index: Codable {
        var version: Int
        var flows: [Flow]
        var connectionLog: [ConnectionLogEntry]
        var processes: [String: ProcessIdentity]?   // 키: FlowID.rawValue.uuidString. 구버전 세션엔 없음.
        var comments: [String: String]?             // 키 동일. 구버전 세션엔 없음.
        var numbers: [String: Int]?                 // 키 동일. 안정 번호(ID 열). 구버전 세션엔 없음.
    }

    /// 디렉터리 패키지: index.json(바디 제외) + bodies/<flowID>.req|.res. 기존 경로는 통째로 교체한다. `numbers`는 흐름별 안정 번호.
    public static func save(flows: [Flow], connectionLog: [ConnectionLogEntry], processes: [FlowID: ProcessIdentity] = [:],
                            comments: [FlowID: String] = [:], numbers: [FlowID: Int] = [:], to url: URL) throws {
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
            let keyed = Dictionary(uniqueKeysWithValues: processes.map { ($0.key.rawValue.uuidString, $0.value) })
            let notes = Dictionary(uniqueKeysWithValues: comments.map { ($0.key.rawValue.uuidString, $0.value) })
            let numbered = Dictionary(uniqueKeysWithValues: numbers.map { ($0.key.rawValue.uuidString, $0.value) })
            try encoder.encode(Index(version: 1, flows: stripped, connectionLog: connectionLog, processes: keyed, comments: notes,
                                     numbers: numbered)).write(to: tmp.appending(path: "index.json"))
            if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: tmp) } else { try fm.moveItem(at: tmp, to: url) }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    /// `numbers`는 파일에 `numbers` 키가 없으면(구버전 세션) nil — `SessionStore.replace`가 순서대로 매긴다.
    public static func load(from url: URL) throws -> (flows: [Flow], connectionLog: [ConnectionLogEntry], processes: [FlowID: ProcessIdentity],
                                                     comments: [FlowID: String], numbers: [FlowID: Int]?) {
        let index = try decoder.decode(Index.self, from: Data(contentsOf: url.appending(path: "index.json")))
        guard index.version == 1 else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "지원하지 않는 세션 버전: \(index.version)"]) }
        var flows = index.flows
        for i in flows.indices {
            let base = url.appending(path: "bodies/\(flows[i].id.rawValue.uuidString)")
            if let d = try? Data(contentsOf: base.appendingPathExtension("req")) { flows[i].request.body = d }
            if flows[i].response != nil, let d = try? Data(contentsOf: base.appendingPathExtension("res")) { flows[i].response?.body = d }
        }
        // FlowID는 UUID에서 만들 수 없으므로 읽어 둔 플로우의 id로 되돌린다(플로우가 없는 항목은 버린다).
        var processes: [FlowID: ProcessIdentity] = [:]
        var comments: [FlowID: String] = [:]
        var numbers: [FlowID: Int]? = index.numbers.map { _ in [:] }
        for f in flows {
            let key = f.id.rawValue.uuidString
            if let p = index.processes?[key] { processes[f.id] = p }
            if let c = index.comments?[key] { comments[f.id] = c }
            if let n = index.numbers?[key] { numbers?[f.id] = n }
        }
        return (flows, index.connectionLog, processes, comments, numbers)
    }

    // iso8601은 초 미만을 버려 왕복이 정확하지 않으므로 deferredToDate(Double 초) 사용.
    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .deferredToDate; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .deferredToDate; return d }
}
