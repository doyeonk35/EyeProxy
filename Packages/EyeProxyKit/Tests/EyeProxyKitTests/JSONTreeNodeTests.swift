import Foundation
import Testing
@testable import EyeProxyKit

@Test func treeNodesKeepOriginalOrderAndLiterals() {
    let n = JSONTreeNode.parse(pretty: "{\n  \"z\" : [\n    1,\n    {}\n  ],\n  \"a\" : 12345678901234567890,\n  \"s\" : \"x\"\n}")
    #expect(n.map(\.key) == ["z", "a", "s"] && n[0].preview == "[2 items]" && n[0].children?.map(\.preview) == ["1", "{0 keys}"] && n[1].preview == "12345678901234567890" && n[2].preview == "\"x\"" && n[2].children == nil)
    #expect(JSONTreeNode.parse(pretty: "\"s\"").map(\.preview) == ["\"s\""])
}

private final class Box: @unchecked Sendable { var depth = 0; var preview = "" }

@Test func treeParseSurvivesMaxNestingOnSmallStack() {
    let box = Box()
    let done = DispatchSemaphore(value: 0)
    let t = Thread {
        let n = JSONTreeNode.parse(pretty: String(repeating: "[", count: 512) + String(repeating: "]", count: 512))
        box.preview = n.first?.preview ?? ""
        var cur = n.first
        while let c = cur, let k = c.children, !k.isEmpty { box.depth += 1; cur = k[0] }
        done.signal()
    }
    t.stackSize = 512 * 1024
    t.start()
    done.wait()
    #expect(box.preview == "[1 items]" && box.depth == 510)
}
