import Testing
@testable import EyeProxyKit

@Test func treeNodesKeepOriginalOrderAndLiterals() {
    let n = JSONTreeNode.parse(pretty: "{\n  \"z\" : [\n    1,\n    {}\n  ],\n  \"a\" : 12345678901234567890,\n  \"s\" : \"x\"\n}")
    #expect(n.map(\.key) == ["z", "a", "s"] && n[0].preview == "[2 items]" && n[0].children?.map(\.preview) == ["1", "{0 keys}"] && n[1].preview == "12345678901234567890" && n[2].preview == "\"x\"" && n[2].children == nil)
    #expect(JSONTreeNode.parse(pretty: "\"s\"").map(\.preview) == ["\"s\""])
}
