import Foundation

public enum ProxymanImportError: Error, Equatable { case notFound(URL) }

public struct ProxymanImportPreview: Sendable {
    public var mapLocal: [RuleNode<MapLocalRule>] = []
    public var mapRemote: [RuleNode<MapRemoteRule>] = []
    public var breakpoint: [RuleNode<BreakpointRule>] = []
    public var block: [RuleNode<BlockRule>] = []
    public var allow: [RuleNode<AllowRule>] = []
    public var networkConditions: [NetworkConditionRule] = []
    public var sslHosts: [String] = []
    public var skipped = 0
    public var missingFiles: [String] = []
    /// Map Local 응답 파일을 복사해 올 원본 폴더(`map-local/`의 부모). Proxyman 폴더 또는 번들 폴더.
    public var sourceDirectory: URL?

    public init() {}
}

/// 도구 창 More ▸ Import…가 겨냥하는 도구.
public enum ImportTool: String, CaseIterable, Sendable {
    case mapLocal, mapRemote, breakpoint, block, allow, networkConditions
}

public struct ImportSelection: Sendable {
    public var mapLocal = true, mapRemote = true, breakpoint = true, block = true, allow = true
    public var networkConditions = true, sslHosts = true
    public init() {}
}

public struct ImportCount: Equatable, Sendable {
    public var added = 0
    public var skippedDuplicate = 0
}

public struct ImportResult: Sendable {
    public var mapLocal = ImportCount(), mapRemote = ImportCount(), breakpoint = ImportCount()
    public var block = ImportCount(), allow = ImportCount(), networkConditions = ImportCount()
    public var sslAdded = 0
    public var graphQLDeferred = 0
    public var missingFiles: [String] = []
    public var skipped = 0
}

func flatRules<R: ToolRule>(_ nodes: [RuleNode<R>]) -> [R] {
    nodes.flatMap { n -> [R] in
        switch n {
        case .rule(let r): [r]
        case .folder(let f): flatRules(f.children)
        }
    }
}

func mapRules<R: ToolRule>(_ nodes: [RuleNode<R>], _ f: (inout R) -> Void) -> [RuleNode<R>] {
    nodes.map { n in
        switch n {
        case .rule(var r): f(&r); return .rule(r)
        case .folder(var fo): fo.children = mapRules(fo.children, f); return .folder(fo)
        }
    }
}

private func allIDs<R: ToolRule>(_ nodes: [RuleNode<R>]) -> Set<String> {
    Set(nodes.flatMap { n -> [String] in
        switch n {
        case .rule(let r): [r.id]
        case .folder(let f): [f.id] + allIDs(f.children)
        }
    })
}

public enum ProxymanImporter {
    public static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.proxyman.NSProxy", isDirectory: true)

    /// EyeProxy가 쓰거나(응답 파일) 쓰기 폴더로 삼아도 되는 위치인가. Proxyman 폴더 자체·그 안·그 조상이면 false.
    /// 심볼릭 링크를 풀고(없는 끝 성분은 부모를 풀어 이어 붙임) 대소문자를 무시해 비교한다.
    public static func isSafeWriteTarget(_ url: URL, proxymanDirectory: URL = defaultDirectory) -> Bool {
        func real(_ u: URL) -> [String] {
            let u = u.standardizedFileURL
            if FileManager.default.fileExists(atPath: u.path) || u.pathComponents.count <= 1 {
                return u.resolvingSymlinksInPath().pathComponents.map { $0.lowercased() }
            }
            return real(u.deletingLastPathComponent()) + [u.lastPathComponent.lowercased()]
        }
        let target = real(url), proxyman = real(proxymanDirectory)
        return !target.starts(with: proxyman) && !proxyman.starts(with: target)
    }

    // MARK: 읽기 (파일 열기만 한다)

    public static func preview(proxymanDirectory dir: URL) throws -> ProxymanImportPreview {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { throw ProxymanImportError.notFound(dir) }
        let userData = dir.appendingPathComponent("user-data", isDirectory: true)
        let names = ((try? fm.contentsOfDirectory(atPath: userData.path)) ?? []).sorted()
        func tree<R: ToolRule>(_ matching: (String) -> Bool, _: R.Type, into p: inout ProxymanImportPreview) -> [RuleNode<R>] {
            names.filter(matching).flatMap { name -> [RuleNode<R>] in
                guard let data = try? Data(contentsOf: userData.appendingPathComponent(name)),
                      let r = try? RuleTree<R>.decodeLenient(data) else { p.skipped += 1; return [] }
                p.skipped += r.skipped
                return r.tree.nodes
            }
        }
        var p = ProxymanImportPreview()
        p.sourceDirectory = dir
        p.mapLocal = tree({ $0 == "MapLocalFiles-RuleTree" }, MapLocalRule.self, into: &p)
        p.mapRemote = tree({ $0 == "MapRemoteService-RuleTree" }, MapRemoteRule.self, into: &p)
        p.breakpoint = tree({ $0 == "BreakpointFiles-RuleTree" }, BreakpointRule.self, into: &p)
        p.block = tree({ $0.localizedCaseInsensitiveContains("block") }, BlockRule.self, into: &p)
        p.allow = tree({ $0.localizedCaseInsensitiveContains("allow") }, AllowRule.self, into: &p)
        if names.contains("NetworkThrottlingService") {
            if let d = try? Data(contentsOf: userData.appendingPathComponent("NetworkThrottlingService")),
               let list = try? JSONDecoder().decode([NetworkConditionRule].self, from: d) {
                p.networkConditions = list
            } else { p.skipped += 1 }
        }
        if let ssl = names.first(where: { $0.hasPrefix("SSLList-") }) {
            if let d = try? Data(contentsOf: userData.appendingPathComponent(ssl)), let hosts = sslHosts(d) {
                p.sslHosts = hosts
            } else { p.skipped += 1 }
        }
        p.missingFiles = missing(p.mapLocal)
        return p
    }

    /// `{"nodes":[{"kind":{"domain":[{"url":…}]}}]}`. `excludeNodes`는 읽지 않는다.
    private static func sslHosts(_ data: Data) -> [String]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let nodes = root["nodes"] as? [[String: Any]] ?? []
        return nodes.flatMap { n -> [String] in
            let domains = (n["kind"] as? [String: Any])?["domain"] as? [[String: Any]] ?? []
            return domains.compactMap { $0["url"] as? String }
        }
    }

    /// 한 도구의 내보내기 파일(규칙 모양이 서로 겹쳐서 필수 키로 도구를 가른다: toURL→Remote, blockAction→Block, isLocalFileEnable→Local, isRequest/isResponse→Breakpoint, 나머지→Allow).
    /// (`.config` 배열 또는 `{"nodes":…}`) 또는 `rules.config`가 든 번들 폴더. 도구를 아는 호출부는 `previewFile(_:as:)`를 쓴다.
    public static func previewFile(_ url: URL) throws -> ProxymanImportPreview {
        let (data, _) = try readFile(url)
        if let list = try? JSONDecoder().decode([NetworkConditionRule].self, from: data), !list.isEmpty {
            return try previewFile(url, as: .networkConditions)
        }
        let text = String(decoding: data, as: UTF8.self)
        func count<R: ToolRule>(_ t: R.Type, if guardOK: Bool) -> Int? {
            guard guardOK, let r = try? RuleTree<R>.decodeLenient(data), !r.tree.nodes.isEmpty else { return nil }
            return r.tree.nodes.count
        }
        let has = { (key: String) in text.contains("\"\(key)\"") }
        let isBP = has("isRequest") || has("isResponse")
        // 규칙 모양이 겹치므로(MapLocal/Allow는 거의 아무 페이로드나 읽는다) 필수 키가 있는 도구만 후보로 두고,
        // 읽힌 노드가 가장 많은 도구가 이긴다(동률이면 앞선 도구). 깨진 노드는 skipped로 센다.
        let candidates: [(ImportTool, Int?)] = [
            (.mapRemote, count(MapRemoteRule.self, if: has("toURL"))),
            (.block, count(BlockRule.self, if: has("blockAction"))),
            (.mapLocal, count(MapLocalRule.self, if: has("isLocalFileEnable"))),
            (.breakpoint, count(BreakpointRule.self, if: isBP)),
            (.allow, count(AllowRule.self, if: !(has("toURL") || has("blockAction") || has("isLocalFileEnable") || isBP))),
        ]
        let best = candidates.compactMap { t, n in n.map { (t, $0) } }.max { $0.1 < $1.1 }?.0
        // 어느 도구로도 읽히지 않으면 Network Conditions로도 못 읽으므로(위에서 확인) 노드 수가 건너뜀으로 잡힌다.
        return try previewFile(url, as: best ?? .networkConditions)
    }

    /// 파일을 `tool` 규칙으로만 읽는다(추측하지 않음). 그 도구로 읽지 못한 노드는 skipped로 센다.
    public static func previewFile(_ url: URL, as tool: ImportTool) throws -> ProxymanImportPreview {
        let (data, bundle) = try readFile(url)
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw ProxymanImportError.notFound(url) }
        let total = (obj as? [Any])?.count ?? ((obj as? [String: Any])?["nodes"] as? [Any])?.count ?? 0
        var p = ProxymanImportPreview()
        p.sourceDirectory = bundle
        func take<R: ToolRule>(_: R.Type) -> [RuleNode<R>] {
            guard let r = try? RuleTree<R>.decodeLenient(data) else { p.skipped = total; return [] }
            p.skipped = r.skipped
            return r.tree.nodes
        }
        switch tool {
        case .mapLocal:
            // 번들의 상대 경로는 번들 폴더 기준 절대 경로로 되돌린다.
            p.mapLocal = mapRules(take(MapLocalRule.self)) { r in
                if let b = bundle, let path = r.localFile?.path, !path.hasPrefix("/") { r.localFile?.path = b.appendingPathComponent(path).path }
            }
        case .mapRemote: p.mapRemote = take(MapRemoteRule.self)
        case .breakpoint: p.breakpoint = take(BreakpointRule.self)
        case .block: p.block = take(BlockRule.self)
        case .allow: p.allow = take(AllowRule.self)
        case .networkConditions:
            if let list = try? JSONDecoder().decode([NetworkConditionRule].self, from: data) { p.networkConditions = list } else { p.skipped = total }
        }
        p.missingFiles = missing(p.mapLocal)
        return p
    }

    /// 파일이면 그 내용, 폴더면 번들로 보고 `rules.config`. 번들 안의 `rules.config`를 직접 고른 경우도 번들로 본다
    /// (열기 패널은 폴더에서 Open을 누르면 고르지 않고 들어가 버린다).
    private static func readFile(_ url: URL) throws -> (Data, bundle: URL?) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { throw ProxymanImportError.notFound(url) }
        let parent = url.deletingLastPathComponent()
        let bundle = isDir.boolValue ? url
            : url.lastPathComponent == "rules.config" && parent.pathExtension == "eyeproxyrules" ? parent : nil
        return (try Data(contentsOf: bundle?.appendingPathComponent("rules.config") ?? url), bundle)
    }

    private static func missing(_ nodes: [RuleNode<MapLocalRule>]) -> [String] {
        flatRules(nodes).compactMap(\.localFile?.path).filter { !FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: 적용

    @MainActor
    public static func apply(_ preview: ProxymanImportPreview, selection: ImportSelection, into store: RuleStore, settings: AppSettings,
                             proxymanDirectory: URL = defaultDirectory) -> ImportResult {
        var result = ImportResult()
        result.skipped = preview.skipped
        var deferred = 0

        func merge<R: ToolRule>(_ incoming: [RuleNode<R>], _ file: RuleFile<R>, _ count: inout ImportCount, prepare: (inout R) -> Void = { _ in }) {
            var tree = store.tree(file)
            var ids = allIDs(tree.nodes)
            var added = 0, dup = 0
            func filter(_ nodes: [RuleNode<R>]) -> [RuleNode<R>] {
                nodes.compactMap { n in
                    switch n {
                    case .rule(let r):
                        if ids.contains(r.id) { dup += 1; return nil }
                        ids.insert(r.id); added += 1
                        return n
                    case .folder(var f):
                        if ids.contains(f.id) { dup += flatRules(f.children).count; return nil }
                        ids.insert(f.id)
                        f.children = filter(f.children)
                        return .folder(f)
                    }
                }
            }
            let fresh = mapRules(filter(incoming)) { r in
                if let q = r.match.graphQLQueryName, !q.isEmpty { r.isEnabled = false; deferred += 1 }
                prepare(&r)
            }
            count.added += added
            count.skippedDuplicate += dup
            guard added > 0 else { return }
            tree.nodes += fresh
            store.set(tree, for: file)
        }

        if selection.mapLocal {
            let roots = [proxymanDirectory, preview.sourceDirectory].compactMap { $0 }
                .map { $0.appendingPathComponent("map-local", isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path }
            merge(preview.mapLocal, .mapLocal, &result.mapLocal) { r in
                guard let ref = r.localFile else { return }
                let src = URL(fileURLWithPath: ref.path)
                let resolved = src.standardizedFileURL.resolvingSymlinksInPath().path
                // 가져온 원본이 Proxyman 폴더(기본 위치/미리보기 원본)나 번들 안이면 우리 폴더로 복사한다.
                let inside = roots.contains { resolved.hasPrefix($0 + "/") }
                if inside, FileManager.default.fileExists(atPath: src.path) {
                    let dest = store.mapLocalDirectory.appendingPathComponent(src.lastPathComponent)
                    do {
                        try FileManager.default.createDirectory(at: store.mapLocalDirectory, withIntermediateDirectories: true)
                        if !FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.copyItem(at: src, to: dest) }
                        r.localFile?.path = dest.path
                    } catch {
                        r.isEnabled = false
                        result.missingFiles.append(ref.path)
                    }
                } else if !FileManager.default.fileExists(atPath: ref.path) {
                    r.isEnabled = false
                    result.missingFiles.append(ref.path)
                }
            }
        }
        if selection.mapRemote { merge(preview.mapRemote, .mapRemote, &result.mapRemote) }
        if selection.breakpoint { merge(preview.breakpoint, .breakpoint, &result.breakpoint) }
        if selection.block { merge(preview.block, .blockList, &result.block) }
        if selection.allow { merge(preview.allow, .allowList, &result.allow) }
        result.graphQLDeferred = deferred

        if selection.networkConditions {
            let existing = store.networkConditions
            let ids = Set(existing.map(\.id))
            var fresh = preview.networkConditions.filter { !ids.contains($0.id) }
            result.networkConditions.skippedDuplicate = preview.networkConditions.count - fresh.count
            result.networkConditions.added = fresh.count
            // 한 번에 하나만 켜는 규칙: 합쳐서 둘 이상이면 가져온 쪽을 끈다.
            if (existing + fresh).filter(\.isEnabled).count > 1 { fresh = fresh.map { var r = $0; r.isEnabled = false; return r } }
            if !fresh.isEmpty { store.networkConditions = existing + fresh }
        }
        if selection.sslHosts {
            var seen = Set(settings.sslPatterns)
            let add = preview.sslHosts.filter { seen.insert($0).inserted }
            result.sslAdded = add.count
            if !add.isEmpty { settings.sslPatterns += add }
        }
        return result
    }
}
