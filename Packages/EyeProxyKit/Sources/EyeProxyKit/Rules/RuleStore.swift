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

    /// Map Local 응답 파일 폴더(`rules`의 형제).
    public var mapLocalDirectory: URL {
        directory.deletingLastPathComponent().appendingPathComponent("map-local", isDirectory: true)
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
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            let moved = "\(file.name).broken-\(f.string(from: Date()))"
            do {
                try FileManager.default.moveItem(at: url, to: directory.appendingPathComponent(moved))
                loadWarnings.append("\(file.name)을 읽지 못해 옮겨 두었습니다: \(moved)")
            } catch {
                loadWarnings.append("\(file.name)을 읽지 못했고 옮기지도 못했습니다: \(error.localizedDescription)")
            }
            return RuleTree()
        }
    }
}
