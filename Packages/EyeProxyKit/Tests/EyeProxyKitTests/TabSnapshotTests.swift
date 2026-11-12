import Foundation
import Testing
@testable import EyeProxyKit

private func live(_ sel: SidebarItem? = nil) -> TabSnapshot { TabSnapshot(filePath: nil, selection: sel, filter: FlowFilter()) }
private func file(_ p: String) -> TabSnapshot { TabSnapshot(filePath: p, selection: nil, filter: FlowFilter()) }

@Test func restorePlanPutsFirstLiveTabFirst() {
    let a = file("/tmp/a.eyeproxy"), l1 = live(.host("api.example.com")), l2 = live(), b = file("/tmp/b.har")
    let plan = OpenTabs(tabs: [a, l1, l2, b], activeIndex: 3).restorePlan()
    #expect(plan.main == l1)
    #expect(plan.rest == [a, l2, b])
    #expect(plan.active == .rest(2))
}

@Test func restorePlanActiveCases() {
    let a = file("/tmp/a.eyeproxy"), l1 = live(.host("api.example.com")), l2 = live(), b = file("/tmp/b.har")
    let tabs = [a, l1, l2, b]
    #expect(OpenTabs(tabs: tabs, activeIndex: 1).restorePlan().active == .main)
    #expect(OpenTabs(tabs: tabs, activeIndex: nil).restorePlan().active == .none)
    #expect(OpenTabs(tabs: tabs, activeIndex: 9).restorePlan().active == .none)
    let files = OpenTabs(tabs: [a, b], activeIndex: 0).restorePlan()
    #expect(files.main == nil)
    #expect(files.rest == [a, b])
    #expect(files.active == .rest(0))
    let empty = OpenTabs(tabs: [], activeIndex: nil).restorePlan()
    #expect(empty.main == nil)
    #expect(empty.rest.isEmpty)
    #expect(empty.active == .none)
}

@Test func snapshotRoundTripsGroupSelectionAndRules() throws {
    let g = HostGroup(name: "g", hostPatterns: ["*.example.com"], apps: [])
    var f = FlowFilter()
    f.rules = [FilterRule(key: .url, match: .contains, text: "v1")]
    let s = TabSnapshot(filePath: nil, selection: .group(g), filter: f)
    #expect(try JSONDecoder().decode(TabSnapshot.self, from: JSONEncoder().encode(s)) == s)
}
