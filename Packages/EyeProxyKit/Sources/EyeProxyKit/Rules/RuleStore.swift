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
    /// 읽지 못했고 옮기지도 못한 파일. 덮어쓰면 원본을 잃으므로 이번 실행에서는 저장하지 않는다.
    @ObservationIgnored private var readOnly: Set<String> = []

    public init(directory: URL) { self.directory = directory }

    public func tree<R: ToolRule>(_ file: RuleFile<R>) -> RuleTree<R> {
        if let cached = cache[file.name] as? RuleTree<R> { return cached }
        let loaded = load(file)
        cache[file.name] = loaded
        return loaded
    }

    /// 저장에 실패하면 캐시·revision을 그대로 두고 경고한다(재시작 후 규칙이 사라지지 않게).
    public func set<R: ToolRule>(_ tree: RuleTree<R>, for file: RuleFile<R>) {
        guard write(name: file.name, { try tree.encoded() }) else { return }
        cache[file.name] = tree
        revision += 1
    }

    /// 사용자가 경고를 확인했다.
    public func clearWarnings() { loadWarnings = [] }

    private func write(name: String, _ encode: () throws -> Data) -> Bool {
        if readOnly.contains(name) {
            loadWarnings.append("\(name)은 원본을 보관하지 못해 저장하지 않았습니다")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encode().write(to: directory.appendingPathComponent(name), options: .atomic)
            return true
        } catch {
            loadWarnings.append("\(name)을 저장하지 못했습니다: \(error.localizedDescription)")
            return false
        }
    }

    /// 파일 내용. 없으면 nil. 있는데 읽지 못하면 빈 규칙으로 덮어쓰지 않도록 옮겨 두고 nil.
    private func read(_ name: String) -> Data? {
        let url = directory.appendingPathComponent(name)
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            aside(url, name: name, suffix: "broken", move: true)
            return nil
        }
    }

    private func load<R: ToolRule>(_ file: RuleFile<R>) -> RuleTree<R> {
        let url = directory.appendingPathComponent(file.name)
        guard let data = read(file.name) else { return RuleTree() }
        do {
            let (tree, skipped) = try RuleTree<R>.decodeLenient(data)
            // 다음 저장이 건너뛴 규칙을 지우므로 원본을 남겨 둔다.
            if skipped > 0 { aside(url, name: file.name, suffix: "backup", move: false, skipped: skipped) }
            return tree
        } catch {
            aside(url, name: file.name, suffix: "broken", move: true)
            return RuleTree()
        }
    }

    /// 원본을 `<이름>.<suffix>-<시각>`으로 옮기거나(읽지 못함) 복사하고(건너뜀) 경고를 남긴다.
    /// 옮기지 못한 파일은 이번 실행에서 저장하지 않는다.
    private func aside(_ url: URL, name: String, suffix: String, move: Bool, skipped: Int = 0) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let target = "\(name).\(suffix)-\(f.string(from: Date()))"
        let to = directory.appendingPathComponent(target)
        do {
            if move { try FileManager.default.moveItem(at: url, to: to) } else { try FileManager.default.copyItem(at: url, to: to) }
            loadWarnings.append(move ? "\(name)을 읽지 못해 옮겨 두었습니다: \(target)"
                                     : "\(name)에서 읽지 못한 규칙 \(skipped)개를 건너뛰었습니다. 원본: \(target)")
        } catch {
            readOnly.insert(name)
            loadWarnings.append("\(name)을 읽지 못했고 따로 보관하지도 못해 이번 실행에서는 저장하지 않습니다: \(error.localizedDescription)")
        }
    }

    // MARK: 트리가 아닌 JSON 배열 파일 (Network Conditions, Breakpoint 템플릿)

    private func array<T: Codable & Sendable>(_ name: String, as _: T.Type) -> [T] {
        if let cached = cache[name] as? [T] { return cached }
        var loaded: [T] = []
        if let data = read(name) {
            do { loaded = try JSONDecoder().decode([T].self, from: data) } catch {
                aside(directory.appendingPathComponent(name), name: name, suffix: "broken", move: true)
            }
        }
        cache[name] = loaded
        return loaded
    }

    private func setArray<T: Codable & Sendable>(_ value: [T], name: String) {
        guard write(name: name, { try JSONEncoder().encode(value) }) else { return }
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
