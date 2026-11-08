import Foundation

/// 규칙 번들 폴더: `rules.config`(Proxyman 내보내기와 같은 노드 배열) + `map-local/` 응답 파일.
public enum RuleBundle {
    /// `toolName`은 호출부 표시용이라 파일에는 쓰지 않는다(가져올 때 규칙 모양으로 도구를 판별).
    public static func export<R: ToolRule>(_ tree: RuleTree<R>, toolName: String, mapLocalDirectory: URL?, to folder: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var out = tree
        if let ml = tree as? RuleTree<MapLocalRule> {
            let files = folder.appendingPathComponent("map-local", isDirectory: true)
            var copyError: Error?
            let rewritten = mapRules(ml.nodes) { r in
                guard let ref = r.localFile else { return }
                let src = ref.path.hasPrefix("/") ? URL(fileURLWithPath: ref.path) : mapLocalDirectory?.appendingPathComponent(ref.path)
                guard let src, fm.fileExists(atPath: src.path) else { return }
                do {
                    try fm.createDirectory(at: files, withIntermediateDirectories: true)
                    let dest = files.appendingPathComponent(src.lastPathComponent)
                    try? fm.removeItem(at: dest)
                    try fm.copyItem(at: src, to: dest)
                    r.localFile?.path = "map-local/" + src.lastPathComponent
                } catch { copyError = error }
            }
            if let copyError { throw copyError }
            out = RuleTree(nodes: rewritten) as! RuleTree<R>
        }
        try out.encodedAsProxymanExport().write(to: folder.appendingPathComponent("rules.config"), options: .atomic)
    }
}
