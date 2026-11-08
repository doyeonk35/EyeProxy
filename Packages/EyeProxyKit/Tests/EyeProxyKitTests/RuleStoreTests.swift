import EyeProxyCore
import Foundation
import Testing
@testable import EyeProxyKit

private struct TestRule: ToolRule {
    var id: String
    var name: String = ""
    var isEnabled: Bool = true
    var match = MatchRule(url: "https://api.example.com/*")

    init(id: String) { self.id = id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ProxymanKey.self)
        id = try c.decode(String.self, forKey: "id")
        name = try c.decode(String.self, forKey: "name")
        isEnabled = try c.decode(Bool.self, forKey: "isEnabled")
        match = try MatchRule(proxymanFields: c)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: ProxymanKey.self)
        try c.encode(id, forKey: "id")
        try c.encode(name, forKey: "name")
        try c.encode(isEnabled, forKey: "isEnabled")
        try match.encode(proxymanFields: &c)
    }
}

extension RuleFile where R == TestRule {
    fileprivate static var test: Self { .init(name: "test.json") }
}

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent("rules", isDirectory: true)
}

@Test @MainActor func savesAndReloadsTree() {
    let dir = tempDir()
    let store = RuleStore(directory: dir)
    #expect(store.tree(.test).nodes.isEmpty && store.revision == 0)
    let tree = RuleTree(nodes: [.rule(TestRule(id: "a")), .folder(RuleFolder(id: "f", name: "F", children: [.rule(TestRule(id: "b"))]))])
    store.set(tree, for: .test)
    #expect(store.tree(.test) == tree && store.revision == 1)
    #expect(RuleStore(directory: dir).tree(.test) == tree)
    #expect(store.mapLocalDirectory == dir.deletingLastPathComponent().appendingPathComponent("map-local", isDirectory: true))
}

@Test @MainActor func brokenFileIsMovedAsideWithWarning() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("{".utf8).write(to: dir.appendingPathComponent("test.json"))
    let store = RuleStore(directory: dir)
    #expect(store.tree(.test).nodes.isEmpty)
    #expect(store.loadWarnings.count == 1)
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(names.contains { $0.hasPrefix("test.json.broken-") } && !names.contains("test.json"))
    _ = store.tree(.test)
    #expect(store.loadWarnings.count == 1)
}

@Test @MainActor func skippedNodesWarnWithoutMovingFile() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data(#"{"nodes":[{"bogus":1}]}"#.utf8).write(to: dir.appendingPathComponent("test.json"))
    let store = RuleStore(directory: dir)
    #expect(store.tree(.test).nodes.isEmpty && store.loadWarnings.count == 1)
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("test.json").path))
}

private func names(_ dir: URL) throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: dir.path) }

/// 있는데 읽을 수 없는 파일은 빈 규칙으로 보고 덮어쓰지 않는다: 옮겨 두고 경고한다(FLAG 1).
@Test @MainActor func unreadableFileIsQuarantinedNotOverwritten() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("test.json")
    let original = try RuleTree(nodes: [.rule(TestRule(id: "keep"))]).encoded()
    try original.write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    let store = RuleStore(directory: dir)
    #expect(store.tree(.test).nodes.isEmpty && store.loadWarnings.count == 1)
    store.set(RuleTree(nodes: [.rule(TestRule(id: "new"))]), for: .test)
    let moved = try #require(try names(dir).first { $0.hasPrefix("test.json.broken-") })
    let backup = dir.appendingPathComponent(moved)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
    #expect(try Data(contentsOf: backup) == original)
}

/// 건너뛴 규칙이 있으면 첫 저장 전에 원본을 남겨 둔다.
@Test @MainActor func skippedNodesKeepBackupBeforeSave() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let original = Data(#"{"nodes":[{"bogus":1}]}"#.utf8)
    try original.write(to: dir.appendingPathComponent("test.json"))
    let store = RuleStore(directory: dir)
    _ = store.tree(.test)
    store.set(RuleTree(nodes: [.rule(TestRule(id: "a"))]), for: .test)
    let backup = try #require(try names(dir).first { $0.hasPrefix("test.json.backup-") })
    #expect(try Data(contentsOf: dir.appendingPathComponent(backup)) == original)
    #expect(store.loadWarnings.contains { $0.contains(backup) })
}

/// 저장에 실패하면 캐시·revision을 바꾸지 않고 경고한다(재시작 후 사라지는 규칙 방지).
@Test @MainActor func failedWriteKeepsCacheAndWarns() throws {
    let dir = tempDir()
    let store = RuleStore(directory: dir)
    let first = RuleTree(nodes: [.rule(TestRule(id: "a"))])
    store.set(first, for: .test)
    store.networkConditions = []
    let revision = store.revision
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
    store.set(RuleTree(nodes: [.rule(TestRule(id: "b"))]), for: .test)
    store.networkConditions = [NetworkConditionRule(id: "n", name: "N", url: "x.example.com", isEnabled: true,
                                                    networkProfile: NetworkProfile(name: "T", downloadBandwidth: 0, uploadBandwidth: 0))]
    #expect(store.tree(.test) == first && store.networkConditions.isEmpty && store.revision == revision)
    #expect(store.loadWarnings.count == 2)
    store.clearWarnings()
    #expect(store.loadWarnings.isEmpty)
}

@Test @MainActor func mapLocalDirectoryHonorsOverride() {
    let dir = tempDir()
    let store = RuleStore(directory: dir)
    let custom = URL(fileURLWithPath: "/tmp/eyeproxy-custom", isDirectory: true)
    store.mapLocalFolderOverride = custom
    #expect(store.mapLocalDirectory == custom)
    store.mapLocalFolderOverride = nil
    #expect(store.mapLocalDirectory == dir.deletingLastPathComponent().appendingPathComponent("map-local", isDirectory: true))
}
