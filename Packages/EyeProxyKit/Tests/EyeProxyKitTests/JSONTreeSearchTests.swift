import Foundation
import Testing
@testable import EyeProxyKit

// ids(루트 객체 0은 parse가 벗겨냄): user 1, name 2, tags 3, "a" 4, "Name" 5, id 6
private let sample = JSONTreeNode.parse(pretty: #"{"user":{"name":"Kim","tags":["a","Name"]},"id":7}"#)

@Test func matchesReturnsPreorderIDsForKeysAndValues() {
    // 키 "name"(2)과 값 "Name"(5) — 화면 순서. 컨테이너 미리보기("{2 keys}")는 맞추지 않는다.
    #expect(JSONTreeSearch.matches(in: sample, query: "name") == [2, 5])
    #expect(JSONTreeSearch.matches(in: sample, query: "keys") == [])
    #expect(JSONTreeSearch.matches(in: sample, query: "7") == [6])
    #expect(JSONTreeSearch.matches(in: sample, query: "user") == [1])
}

@Test func searchIsCaseInsensitiveAndMatchesKoreanKeysAndValues() {
    let n = JSONTreeNode.parse(pretty: #"{"이름":"홍길동","Info":{"별명":"이름없음"}}"#)
    #expect(JSONTreeSearch.matches(in: n, query: "이름") == [1, 3])
    #expect(JSONTreeSearch.matches(in: n, query: "INFO") == [2])
    #expect(JSONTreeSearch.matches(in: sample, query: "KIM") == [2])
}

@Test func ancestorsCoverEveryLevel() {
    #expect(JSONTreeSearch.ancestors(of: [5], in: sample) == [1, 3])
    #expect(JSONTreeSearch.ancestors(of: [2, 6], in: sample) == [1])
    #expect(JSONTreeSearch.ancestors(of: [1], in: sample) == [])
}

@Test func filterKeepsAncestorsAndWholeMatchedContainer() {
    let byValue = JSONTreeSearch.filter(sample, query: "Name")  // name(2) 키, "Name"(5) 값
    #expect(byValue.map(\.id) == [1])
    #expect(byValue[0].children?.map(\.id) == [2, 3])
    #expect(byValue[0].children?[1].children?.map(\.id) == [5])

    let container = JSONTreeSearch.filter(sample, query: "tags")
    #expect(container[0].children?.map(\.id) == [3])
    #expect(container[0].children?[0].children?.map(\.id) == [4, 5])

    #expect(JSONTreeSearch.filter(sample, query: "nothing").isEmpty)
}

@Test func emptyQueryIsNoOp() {
    #expect(JSONTreeSearch.matches(in: sample, query: "") == [])
    #expect(JSONTreeSearch.filter(sample, query: "").map(\.id) == sample.map(\.id))
    #expect(JSONTreeSearch.ancestors(of: [], in: sample) == [])
}

@Test func containerIDsListsEveryNodeWithChildren() {
    #expect(JSONTreeSearch.containerIDs(in: sample) == [1, 3])
    #expect(JSONTreeSearch.containerIDs(in: JSONTreeNode.parse(pretty: #"{"e":{},"a":[1]}"#)) == [2])
}

private final class SearchBox: @unchecked Sendable { var hits: [Int] = []; var ancestors = 0; var filteredDepth = 0; var containers = 0 }

@Test func deepTreeSearchDoesNotRecurse() {
    let box = SearchBox()
    let done = DispatchSemaphore(value: 0)
    let t = Thread {
        // 바깥 루트(id 0)는 parse가 벗겨내고, 컨테이너 1...509 아래 스칼라 510.
        let n = JSONTreeNode.parse(pretty: String(repeating: #"{"k":"#, count: 510) + #""needle""# + String(repeating: "}", count: 510))
        box.hits = JSONTreeSearch.matches(in: n, query: "needle")
        box.ancestors = JSONTreeSearch.ancestors(of: Set(box.hits), in: n).count
        var cur = JSONTreeSearch.filter(n, query: "needle").first
        while let c = cur { box.filteredDepth += 1; cur = c.children?.first }
        box.containers = JSONTreeSearch.containerIDs(in: n).count
        done.signal()
    }
    t.stackSize = 512 * 1024
    t.start()
    done.wait()
    #expect(box.hits == [510] && box.ancestors == 509 && box.filteredDepth == 510 && box.containers == 509)
}
