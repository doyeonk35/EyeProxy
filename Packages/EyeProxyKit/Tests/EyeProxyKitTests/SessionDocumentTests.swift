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
