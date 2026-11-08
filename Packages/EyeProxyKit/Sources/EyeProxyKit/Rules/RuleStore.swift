import Foundation
import Observation

/// 규칙 파일 하나. 각 도구가 `extension RuleFile where R == X { static var x: Self { .init(name: "x.json") } }`로 선언한다.
public struct RuleFile<R: ToolRule>: Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

/// 모든 도구 규칙의 디스크 저장소. 앱은 `revision`을 관찰해 인터셉터 체인을 다시 만든다.
@Observable @MainActor
public final class RuleStore {
    public let directory: URL
    public private(set) var revision = 0
    public private(set) var loadWarnings: [String] = []

    /// More ▸ Default Local File Folder로 고른 폴더. nil이면 기본 폴더.
    public var mapLocalFolderOverride: URL?

    /// Map Local 응답 파일 폴더. 기본은 `rules`의 형제 `map-local`.
    public var mapLocalDirectory: URL {
        mapLocalFolderOverride ?? directory.deletingLastPathComponent().appendingPathComponent("map-local", isDirectory: true)
    }

    /// 파일 이름 → 디코드된 `RuleTree<R>`. 읽기만으로 뷰가 다시 그려지지 않게 관찰 제외.
    @ObservationIgnored private var cache: [String: any Sendable] = [:]

    public init(directory: URL) { self.directory = directory }

    public func tree<R: ToolRule>(_ file: RuleFile<R>) -> RuleTree<R> {
        if let cached = cache[file.name] as? RuleTree<R> { return cached }
        let loaded = load(file)
        cache[file.name] = loaded
        return loaded
    }

    public func set<R: ToolRule>(_ tree: RuleTree<R>, for file: RuleFile<R>) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try tree.encoded().write(to: directory.appendingPathComponent(file.name), options: .atomic)
        } catch {
            loadWarnings.append("\(file.name)을 저장하지 못했습니다: \(error.localizedDescription)")
        }
        cache[file.name] = tree
        revision += 1
    }

    private func load<R: ToolRule>(_ file: RuleFile<R>) -> RuleTree<R> {
        let url = directory.appendingPathComponent(file.name)
        guard let data = try? Data(contentsOf: url) else { return RuleTree() }
        do {
            let (tree, skipped) = try RuleTree<R>.decodeLenient(data)
            if skipped > 0 { loadWarnings.append("\(file.name)에서 읽지 못한 규칙 \(skipped)개를 건너뛰었습니다") }
            return tree
        } catch {
            quarantine(url, name: file.name)
            return RuleTree()
        }
    }

    /// 읽지 못한 파일을 `.broken-<시각>`으로 옮겨 두고 경고를 남긴다.
    private func quarantine(_ url: URL, name: String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let moved = "\(name).broken-\(f.string(from: Date()))"
        do {
            try FileManager.default.moveItem(at: url, to: directory.appendingPathComponent(moved))
            loadWarnings.append("\(name)을 읽지 못해 옮겨 두었습니다: \(moved)")
        } catch {
            loadWarnings.append("\(name)을 읽지 못했고 옮기지도 못했습니다: \(error.localizedDescription)")
        }
    }

    // MARK: 트리가 아닌 JSON 배열 파일 (Network Conditions, Breakpoint 템플릿)

    private func array<T: Codable & Sendable>(_ name: String, as _: T.Type) -> [T] {
        if let cached = cache[name] as? [T] { return cached }
        let url = directory.appendingPathComponent(name)
        var loaded: [T] = []
        if let data = try? Data(contentsOf: url) {
            do { loaded = try JSONDecoder().decode([T].self, from: data) } catch { quarantine(url, name: name) }
        }
        cache[name] = loaded
        return loaded
    }

    private func setArray<T: Codable & Sendable>(_ value: [T], name: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            loadWarnings.append("\(name)을 저장하지 못했습니다: \(error.localizedDescription)")
        }
        cache[name] = value
        revision += 1
    }

    public var networkConditions: [NetworkConditionRule] {
        get { array("network-conditions.json", as: NetworkConditionRule.self) }
        set { setArray(newValue, name: "network-conditions.json") }
    }

    /// Custom Profile…로 저장한 사용자 프로필.
    public var customNetworkProfiles: [NetworkProfile] {
        get { array("network-profiles.json", as: NetworkProfile.self) }
        set { setArray(newValue, name: "network-profiles.json") }
    }

    /// Breakpoint 편집기 템플릿.
    public var breakpointTemplates: [BreakpointTemplate] {
        get { array("breakpoint-templates.json", as: BreakpointTemplate.self) }
        set { setArray(newValue, name: "breakpoint-templates.json") }
    }

    /// 하나를 켜고 나머지는 끈다(한 번에 규칙 하나만 활성). 저장은 한 번.
    public func activateNetworkCondition(id: String) {
        networkConditions = networkConditions.map { var r = $0; r.isEnabled = r.id == id; return r }
    }
}
