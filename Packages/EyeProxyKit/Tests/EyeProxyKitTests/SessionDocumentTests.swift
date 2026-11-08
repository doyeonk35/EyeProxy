import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

@Test func roundTripPreservesBodiesOutsideIndex() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).eyeproxy")
    defer { try? FileManager.default.removeItem(at: url) }
    var f = Flow.fixture(client: "1", decrypted: true); f.request.body = Data("REQ".utf8); f.response = .init(status: 200, reason: "OK", headers: [], body: Data("RES".utf8))
    try SessionDocument.save(flows: [f], connectionLog: [], to: url)
    let index = try String(contentsOf: url.appending(path: "index.json"), encoding: .utf8)
    #expect(!index.contains("UkVR"))   // "REQ" base64가 index에 없음
    #expect(FileManager.default.fileExists(atPath: url.appending(path: "bodies/\(f.id.rawValue.uuidString).res").path))
    let loaded = try SessionDocument.load(from: url)
    #expect(loaded.flows == [f])
}

@Test func saveReplacesExistingAndKeepsLog() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).eyeproxy")
    defer { try? FileManager.default.removeItem(at: url) }
    var f = Flow.fixture(client: "1", decrypted: false); f.request.body = Data("REQ".utf8)
    let log = ConnectionLogEntry(id: UUID(), date: .now, clientAddress: "1", host: "h", port: 1, message: "m")
    try SessionDocument.save(flows: [f], connectionLog: [log], to: url)
    try SessionDocument.save(flows: [Flow.fixture(client: "2", decrypted: false)], connectionLog: [], to: url)
    let loaded = try SessionDocument.load(from: url)
    #expect(loaded.flows.count == 1 && loaded.flows[0].clientAddress == "2" && loaded.connectionLog.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.appending(path: "bodies/\(f.id.rawValue.uuidString).req").path))
    try SessionDocument.save(flows: [f], connectionLog: [log], to: url)
    #expect(try SessionDocument.load(from: url).connectionLog == [log])
}

@Test func loadMissingDirectoryThrows() { #expect(throws: (any Error).self) { try SessionDocument.load(from: URL(filePath: "/nonexistent.eyeproxy")) } }

@Test func loadUnsupportedVersionThrows() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).eyeproxy")
    defer { try? FileManager.default.removeItem(at: url) }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data(#"{"version":99,"flows":[],"connectionLog":[]}"#.utf8).write(to: url.appending(path: "index.json"))
    #expect(throws: (any Error).self) { try SessionDocument.load(from: url) }
}

@Test func roundTripProcessesAndToleratesMissingKey() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).eyeproxy"); defer { try? FileManager.default.removeItem(at: url) }
    let f = Flow.fixture(client: "127.0.0.1", decrypted: false); let p = ProcessIdentity(pid: 1, path: "/Applications/Safari.app/Contents/MacOS/Safari")
    try SessionDocument.save(flows: [f], connectionLog: [], processes: [f.id: p], to: url)
    #expect(try SessionDocument.load(from: url).processes == [f.id: p])
    try SessionDocument.save(flows: [f], connectionLog: [], to: url)
    #expect(try SessionDocument.load(from: url).processes.isEmpty)
}

@Test func sessionDocumentRoundTripsComments() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).eyeproxy"); defer { try? FileManager.default.removeItem(at: url) }
    let f = Flow.fixture(client: "1", decrypted: false)
    try SessionDocument.save(flows: [f], connectionLog: [], comments: [f.id: "메모\n둘째 줄"], to: url)
    #expect(try SessionDocument.load(from: url).comments == [f.id: "메모\n둘째 줄"])
    try SessionDocument.save(flows: [f], connectionLog: [], to: url)
    #expect(try SessionDocument.load(from: url).comments.isEmpty)
    try Data(#"{"version":1,"flows":[],"connectionLog":[]}"#.utf8).write(to: url.appending(path: "index.json"))
    #expect(try SessionDocument.load(from: url).comments.isEmpty)
}

@Test @MainActor func sessionFileRoundTripsStableNumbers() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).eyeproxy"); defer { try? FileManager.default.removeItem(at: url) }
    let fs = (1...3).map { Flow.fixture(client: "\($0)", decrypted: false) }
    let numbers = [fs[0].id: 1, fs[1].id: 3, fs[2].id: 7]
    try SessionDocument.save(flows: fs, connectionLog: [], numbers: numbers, to: url)
    let loaded = try SessionDocument.load(from: url)
    #expect(loaded.numbers == numbers)
    let s = SessionStore(); s.replace(flows: loaded.flows, numbers: loaded.numbers)
    #expect(s.numbersByID == numbers)
    let next = Flow.fixture(client: "4", decrypted: false); s.apply(.requestStarted(next))
    #expect(s.number(next.id) == 8)
}

@Test @MainActor func legacySessionGetsPositionalNumbers() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).eyeproxy"); defer { try? FileManager.default.removeItem(at: url) }
    let fs = (1...3).map { Flow.fixture(client: "\($0)", decrypted: false) }
    try SessionDocument.save(flows: fs, connectionLog: [], to: url)
    // 구버전 index.json: save가 만든 모양에서 numbers 키만 뺀다.
    let indexURL = url.appending(path: "index.json")
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any])
    json["numbers"] = nil
    try JSONSerialization.data(withJSONObject: json).write(to: indexURL)
    let loaded = try SessionDocument.load(from: url)
    #expect(loaded.numbers == nil)
    let s = SessionStore(); s.replace(flows: loaded.flows, numbers: loaded.numbers)
    #expect(fs.map { s.number($0.id) } == [1, 2, 3])
}

@Test @MainActor func sessionFileRoundTripsHighlights() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).eyeproxy"); defer { try? FileManager.default.removeItem(at: url) }
    let a = Flow.fixture(client: "1", decrypted: false), b = Flow.fixture(client: "2", decrypted: false)
    let highlights = [a.id: FlowHighlight(color: .purple, strikethrough: true), b.id: FlowHighlight(color: nil, strikethrough: true)]
    try SessionDocument.save(flows: [a, b], connectionLog: [], highlights: highlights, to: url)
    let loaded = try SessionDocument.load(from: url)
    #expect(loaded.highlights == highlights)
    let s = SessionStore(); s.replace(flows: loaded.flows, highlights: loaded.highlights, numbers: loaded.numbers)
    #expect(s.highlights == highlights)
    try Data(#"{"version":1,"flows":[],"connectionLog":[]}"#.utf8).write(to: url.appending(path: "index.json"))
    #expect(try SessionDocument.load(from: url).highlights.isEmpty)   // 구버전 세션
}
