import Foundation
import Testing
@testable import EyeProxyKit

private var fm: FileManager { .default }

private func fixtureRoot() throws -> URL {
    try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("Proxyman")
}

private func tempDir() throws -> URL {
    let d = fm.temporaryDirectory.appendingPathComponent("importer-\(UUID().uuidString)")
    try fm.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

/// 픽스처를 임시 폴더로 복사한 가짜 Proxyman 폴더. `FIXTURES` 자리표시자를 그 폴더 경로로 바꾼다.
private func proxymanCopy(in root: URL) throws -> URL {
    let dir = root.appendingPathComponent("proxyman")
    let src = try fixtureRoot()
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for name in ["user-data", "map-local"] { try fm.copyItem(at: src.appendingPathComponent(name), to: dir.appendingPathComponent(name)) }
    let f = dir.appendingPathComponent("user-data/MapLocalFiles-RuleTree")
    try String(contentsOf: f, encoding: .utf8).replacingOccurrences(of: "FIXTURES", with: dir.path).write(to: f, atomically: true, encoding: .utf8)
    return dir
}

@MainActor private func makeStore(_ root: URL) -> RuleStore {
    RuleStore(directory: root.appendingPathComponent("eye/rules"))
}

private func snapshot(_ dir: URL) -> [String] {
    (fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])?.allObjects as? [URL] ?? [])
        .map { u in
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return "\(u.path.dropFirst(dir.path.count)) \(v?.fileSize ?? -1) \(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }.sorted()
}

@Test func previewReadsAllFiles() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let p = try ProxymanImporter.preview(proxymanDirectory: try proxymanCopy(in: root))
    #expect(p.mapLocal.count == 1)
    #expect(p.networkConditions.count == 1)
    #expect(p.sslHosts == ["img.example.com", "api.example.com"])
    #expect(p.mapRemote.isEmpty && p.breakpoint.isEmpty && p.block.isEmpty && p.allow.isEmpty)
    #expect(p.skipped == 0 && p.missingFiles.isEmpty)
}

@Test func previewMissingDirectoryThrows() {
    #expect(throws: ProxymanImportError.self) {
        try ProxymanImporter.preview(proxymanDirectory: fm.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)"))
    }
}

@Test func previewNeverWrites() throws {
    let root = try tempDir()
    let dir = try proxymanCopy(in: root)
    try shell("chmod", "-R", "a-w", dir.path)
    defer { _ = try? shell("chmod", "-R", "u+w", root.path); try? fm.removeItem(at: root) }
    let before = snapshot(dir)
    let p = try ProxymanImporter.preview(proxymanDirectory: dir)
    #expect(p.mapLocal.count == 1)
    #expect(snapshot(dir) == before)
}

@discardableResult private func shell(_ args: String...) throws -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/" + args[0])
    p.arguments = Array(args.dropFirst())
    try p.run(); p.waitUntilExit()
    return p.terminationStatus
}

@Test @MainActor func applyAppendsAndDedupes() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let p = try ProxymanImporter.preview(proxymanDirectory: try proxymanCopy(in: root))
    let store = makeStore(root)
    let settings = AppSettings(defaults: UserDefaults(suiteName: "imp-\(UUID().uuidString)")!)
    let existing = MapLocalRule(id: "EXIST", name: "mine")
    store.set(RuleTree(nodes: [.rule(existing)]), for: .mapLocal)

    let r1 = ProxymanImporter.apply(p, selection: ImportSelection(), into: store, settings: settings)
    #expect(r1.mapLocal.added == 1 && r1.networkConditions.added == 1 && r1.sslAdded == 2)
    #expect(store.tree(.mapLocal).nodes.count == 2)
    #expect(store.tree(.mapLocal).nodes.first?.id == "EXIST")
    let r2 = ProxymanImporter.apply(p, selection: ImportSelection(), into: store, settings: settings)
    #expect(r2.mapLocal.added == 0 && r2.mapLocal.skippedDuplicate == 1 && r2.networkConditions.skippedDuplicate == 1 && r2.sslAdded == 0)
    #expect(store.tree(.mapLocal).nodes.count == 2)
    #expect(store.networkConditions.count == 1)
    #expect(settings.sslPatterns == ["img.example.com", "api.example.com"])
}

@Test @MainActor func applyHonorsSelection() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let p = try ProxymanImporter.preview(proxymanDirectory: try proxymanCopy(in: root))
    let store = makeStore(root)
    let settings = AppSettings(defaults: UserDefaults(suiteName: "imp-\(UUID().uuidString)")!)
    var sel = ImportSelection(); sel.mapLocal = false; sel.sslHosts = false
    _ = ProxymanImporter.apply(p, selection: sel, into: store, settings: settings)
    #expect(store.tree(.mapLocal).nodes.isEmpty && settings.sslPatterns.isEmpty && store.networkConditions.count == 1)
}

@Test @MainActor func applyLeavesSwitchesOff() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let p = try ProxymanImporter.preview(proxymanDirectory: try proxymanCopy(in: root))
    let settings = AppSettings(defaults: UserDefaults(suiteName: "imp-\(UUID().uuidString)")!)
    _ = ProxymanImporter.apply(p, selection: ImportSelection(), into: makeStore(root), settings: settings)
    #expect(settings.toolSwitches == ToolSwitches())
}

@Test @MainActor func importedNetworkConditionsKeepOnlyOneActive() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let p = try ProxymanImporter.preview(proxymanDirectory: try proxymanCopy(in: root))
    let store = makeStore(root)
    var active = p.networkConditions[0]
    active.id = "OTHER"
    store.networkConditions = [active]
    _ = ProxymanImporter.apply(p, selection: ImportSelection(), into: store, settings: AppSettings(defaults: UserDefaults(suiteName: "imp-\(UUID().uuidString)")!))
    #expect(store.networkConditions.filter(\.isEnabled).map(\.id) == ["OTHER"])
    #expect(store.networkConditions.count == 2)
}

@Test @MainActor func copiesResponseFileFromProxymanFolder() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let p = try ProxymanImporter.preview(proxymanDirectory: try proxymanCopy(in: root))
    let store = makeStore(root)
    _ = ProxymanImporter.apply(p, selection: ImportSelection(), into: store, settings: AppSettings(defaults: UserDefaults(suiteName: "imp-\(UUID().uuidString)")!))
    guard case .rule(let rule) = store.tree(.mapLocal).nodes[0] else { Issue.record("rule 아님"); return }
    let path = try #require(rule.localFile?.path)
    #expect(path == store.mapLocalDirectory.appendingPathComponent("api.example.com_19A8BA07.json").path)
    #expect(fm.fileExists(atPath: path))
    #expect(rule.isEnabled)
}

@Test @MainActor func missingResponseFileDisablesRule() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let dir = try proxymanCopy(in: root)
    try fm.removeItem(at: dir.appendingPathComponent("map-local/api.example.com_19A8BA07.json"))
    let p = try ProxymanImporter.preview(proxymanDirectory: dir)
    #expect(p.missingFiles.count == 1)
    let store = makeStore(root)
    let r = ProxymanImporter.apply(p, selection: ImportSelection(), into: store, settings: AppSettings(defaults: UserDefaults(suiteName: "imp-\(UUID().uuidString)")!))
    guard case .rule(let rule) = store.tree(.mapLocal).nodes[0] else { Issue.record("rule 아님"); return }
    #expect(!rule.isEnabled)
    #expect(r.missingFiles.count == 1)
}

@Test @MainActor func graphQLRulesImportDisabled() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let dir = try proxymanCopy(in: root)
    let f = dir.appendingPathComponent("user-data/MapLocalFiles-RuleTree")
    try String(contentsOf: f, encoding: .utf8).replacingOccurrences(of: "\"graphQLQueryName\":null", with: "\"graphQLQueryName\":\"GetUser\"").write(to: f, atomically: true, encoding: .utf8)
    let store = makeStore(root)
    let r = ProxymanImporter.apply(try ProxymanImporter.preview(proxymanDirectory: dir), selection: ImportSelection(), into: store,
                                   settings: AppSettings(defaults: UserDefaults(suiteName: "imp-\(UUID().uuidString)")!))
    guard case .rule(let rule) = store.tree(.mapLocal).nodes[0] else { Issue.record("rule 아님"); return }
    #expect(!rule.isEnabled)
    #expect(r.graphQLDeferred == 1)
}

@Test func previewExportFileArray() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let raw = try String(contentsOf: try fixtureRoot().appendingPathComponent("proxyman_map_local_tree_rules.config"), encoding: .utf8)
    let f = root.appendingPathComponent("rules.config")
    try raw.replacingOccurrences(of: "FIXTURES", with: root.path).write(to: f, atomically: true, encoding: .utf8)
    let p = try ProxymanImporter.previewFile(f)
    #expect(p.mapLocal.count == 1 && p.mapRemote.isEmpty && p.skipped == 0)
}

@Test func previewFileNetworkConditions() throws {
    let p = try ProxymanImporter.previewFile(try fixtureRoot().appendingPathComponent("NetworkThrottlingService.json"))
    #expect(p.networkConditions.count == 1 && p.mapLocal.isEmpty)
}

@Test func previewFileUnrecognizedCountsSkipped() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let f = root.appendingPathComponent("x.config")
    try Data(#"[{"foo":1},{"bar":2}]"#.utf8).write(to: f)
    let p = try ProxymanImporter.previewFile(f)
    #expect(p.mapLocal.isEmpty && p.skipped == 2)
}

@Test func bundleRoundTrip() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let src = try ProxymanImporter.preview(proxymanDirectory: try proxymanCopy(in: root))
    let tree = RuleTree(nodes: src.mapLocal)
    let bundle = root.appendingPathComponent("out.eyeproxyrules")
    try RuleBundle.export(tree, toolName: "Map Local", mapLocalDirectory: nil, to: bundle)
    #expect(fm.fileExists(atPath: bundle.appendingPathComponent("rules.config").path))
    #expect(fm.fileExists(atPath: bundle.appendingPathComponent("map-local/api.example.com_19A8BA07.json").path))
    let raw = try String(contentsOf: bundle.appendingPathComponent("rules.config"), encoding: .utf8)
    #expect(raw.contains("map-local\\/api.example.com_19A8BA07.json") && !raw.contains(root.path))

    let p = try ProxymanImporter.previewFile(bundle)
    guard case .rule(let a) = tree.nodes[0], case .rule(let b) = try #require(p.mapLocal.first) else { Issue.record("rule 아님"); return }
    let path = try #require(b.localFile?.path)
    #expect(fm.fileExists(atPath: path))
    #expect(path.hasSuffix("out.eyeproxyrules/map-local/api.example.com_19A8BA07.json"))
    #expect(a.id == b.id && a.match == b.match && a.name == b.name && a.delaySeconds == b.delaySeconds)
    #expect(p.missingFiles.isEmpty)
}

@Test func bundleOfOtherToolCopiesNoFiles() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let tree = RuleTree(nodes: [RuleNode.rule(BlockRule(name: "b", match: MatchRule(url: "https://x.example.com/*")))])
    let bundle = root.appendingPathComponent("b")
    try RuleBundle.export(tree, toolName: "Block List", mapLocalDirectory: nil, to: bundle)
    #expect(!fm.fileExists(atPath: bundle.appendingPathComponent("map-local").path))
    #expect(try ProxymanImporter.previewFile(bundle).block.count == 1)
}

@Test func brokenFileCountsSkipped() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let dir = try proxymanCopy(in: root)
    let f = dir.appendingPathComponent("user-data/MapLocalFiles-RuleTree")
    var text = try String(contentsOf: f, encoding: .utf8)
    text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).dropLast(2)) + #",{"nodeType":{"node":{"_0":{"id":"BAD"}}}}]}"#
    try text.write(to: f, atomically: true, encoding: .utf8)
    let p = try ProxymanImporter.preview(proxymanDirectory: dir)
    #expect(p.mapLocal.count == 1 && p.skipped == 1)
}

@Test func notJSONFileCountsSkippedAndOthersLoad() throws {
    let root = try tempDir(); defer { try? fm.removeItem(at: root) }
    let dir = try proxymanCopy(in: root)
    try Data("garbage".utf8).write(to: dir.appendingPathComponent("user-data/MapRemoteService-RuleTree"))
    let p = try ProxymanImporter.preview(proxymanDirectory: dir)
    #expect(p.skipped == 1 && p.mapLocal.count == 1)
}
