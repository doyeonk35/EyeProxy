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

@Test @MainActor func mapLocalDirectoryHonorsOverride() {
    let dir = tempDir()
    let store = RuleStore(directory: dir)
    let custom = URL(fileURLWithPath: "/tmp/eyeproxy-custom", isDirectory: true)
    store.mapLocalFolderOverride = custom
    #expect(store.mapLocalDirectory == custom)
    store.mapLocalFolderOverride = nil
    #expect(store.mapLocalDirectory == dir.deletingLastPathComponent().appendingPathComponent("map-local", isDirectory: true))
}
