import Foundation
import Testing
@testable import EyeProxyKit

@Test func highlighterClassifiesPrettyJSON() {
    let s = "{\n  \"k\" : \"v\",\n  \"n\" : -1.5e3,\n  \"b\" : true,\n  \"z\" : null\n}"
    let t = JSONHighlighter.tokens(s)
    #expect(t.map(\.kind) == [.key, .string, .key, .number, .key, .keyword, .key, .keyword])
    #expect((s as NSString).substring(with: t[1].range) == "\"v\"" && (s as NSString).substring(with: t[3].range) == "-1.5e3")
}

@Test func highlighterRangesSurviveNonASCII() {
    let s = "{\n  \"한글\" : \"é\\\"x\",\n  \"n\" : 1\n}"
    let t = JSONHighlighter.tokens(s)
    #expect((s as NSString).substring(with: t[0].range) == "\"한글\"" && (s as NSString).substring(with: t[1].range) == "\"é\\\"x\"" && (s as NSString).substring(with: t[3].range) == "1")
}
