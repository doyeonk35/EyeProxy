import Foundation
import Testing
@testable import EyeProxyKit

private func rule(_ id: String) -> RuleNode<AllowRule> { .rule(AllowRule(id: id, name: id)) }
private func folder(_ id: String, _ children: [RuleNode<AllowRule>]) -> RuleNode<AllowRule> {
    .folder(RuleFolder(id: id, name: id, children: children))
}

/// a, F[b, c], d
private func sample() -> RuleTree<AllowRule> { RuleTree(nodes: [rule("a"), folder("F", [rule("b"), rule("c")]), rule("d")]) }

@Test func editingOps() {
    var t = sample()
    #expect(t.allIDs == ["a", "F", "b", "c", "d"])
    #expect(t.parent(of: "c") == "F")
    #expect(t.parent(of: "a") == nil)

    t.update("c") { $0.isEnabled = false }
    #expect(t.node("c")?.isEnabled == false)

    // 폴더 밖 → 폴더 안, 폴더 안 → 최상위 끝
    t.move(["a"], into: "F", before: "c")
    #expect(t.allIDs == ["F", "b", "a", "c", "d"])
    t.move(["b"], into: nil, before: nil)
    #expect(t.allIDs == ["F", "a", "c", "d", "b"])
    // 폴더를 자기 안으로는 옮기지 않는다
    t.move(["F"], into: "F", before: nil)
    #expect(t.allIDs == ["F", "a", "c", "d", "b"])

    let copies = t.duplicate(["c"])
    #expect(copies.count == 1 && copies[0].count == 8)
    #expect(t.allIDs == ["F", "a", "c", copies[0], "d", "b"])
    #expect(t.node(copies[0])?.name == "c 복사본")

    #expect(t.remove(["F", "a"]).map(\.id) == ["F"])
    #expect(t.allIDs == ["d", "b"])
}

/// 스펙 §4.2·Task 3 표의 두 줄(Proxyman `?*`)과 scheme 없는 샘플.
@Test func sampleURLMatching() {
    let r = MatchRule(url: "https://api.example.com/v1/search?*", methods: .exact(["POST"]), ignoreQuery: false)
    #expect(r.matches(sampleURL: "https://api.example.com/v1/search?q=1"))
    #expect(!r.matches(sampleURL: "https://api.example.com/v1/search"))
    #expect(MatchRule(url: "api.example.com").matches(sampleURL: "api.example.com"))
    #expect(!MatchRule(url: "api.example.com").matches(sampleURL: ""))
}
