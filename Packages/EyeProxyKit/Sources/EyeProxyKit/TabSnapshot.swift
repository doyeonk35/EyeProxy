import Foundation

/// 탭 하나의 저장본. 필터는 규칙·AND/OR만 저장된다(`FlowFilter`의 Codable).
public struct TabSnapshot: Codable, Equatable, Sendable {
    public var filePath: String?          // nil = 라이브
    public var selection: SidebarItem?
    public var filter: FlowFilter
    public init(filePath: String?, selection: SidebarItem?, filter: FlowFilter) {
        self.filePath = filePath
        self.selection = selection
        self.filter = filter
    }
}

public struct OpenTabs: Codable, Equatable, Sendable {
    public var tabs: [TabSnapshot]
    public var activeIndex: Int?
    public init(tabs: [TabSnapshot], activeIndex: Int?) {
        self.tabs = tabs
        self.activeIndex = activeIndex
    }

    /// 첫 라이브 탭은 실행 탭(main)에 넣고 나머지는 저장 순서대로 뒤에 연다.
    public func restorePlan() -> RestorePlan {
        let m = tabs.firstIndex { $0.filePath == nil }
        var rest = tabs
        let main = m.map { rest.remove(at: $0) }
        let active: RestorePlan.Active
        if let a = activeIndex, tabs.indices.contains(a) {
            if a == m { active = .main } else { active = .rest(m.map { a > $0 ? a - 1 : a } ?? a) }
        } else {
            active = .none
        }
        return RestorePlan(main: main, rest: rest, active: active)
    }
}

public struct RestorePlan: Equatable, Sendable {
    public enum Active: Equatable, Sendable { case main, rest(Int), none }
    public var main: TabSnapshot?         // 첫 라이브 탭(실행 탭에 넣는다). 없으면 nil
    public var rest: [TabSnapshot]        // 나머지, 저장 순서
    public var active: Active
}
