import Foundation
import Testing
@testable import EyeProxyKit

private func parse(_ s: String) throws -> HostList.Parsed { try HostList.parse(Data(s.utf8)) }

@Test func parsesLinesCommentsAndBlank() throws {
    let p = try parse("# c\r\napi.example.com\n\n  *.Example.org  \n")
    #expect(p.patterns == ["api.example.com", "*.example.org"]); #expect(p.rejected == 0)
}
@Test func parseTakesHostFromURLAndDropsPort() throws {
    #expect(try parse("https://api.example.com:8443/v1/x?y=1\ncdn.example.org:443").patterns == ["api.example.com", "cdn.example.org"])
}
@Test func parseRejectsInvalidAndDedupes() throws {
    let p = try parse("a b.example.com\napi.example.com\nAPI.example.com\nv?.example.net\nbad/host")
    #expect(p.patterns == ["api.example.com", "v?.example.net"]); #expect(p.rejected == 2)
}
@Test func parseAcceptsBOM() throws { #expect(try parse("\u{FEFF}api.example.com").patterns == ["api.example.com"]) }
@Test func parseReadsProxymanSSLJSON() throws {
    let j = #"{"nodes":[{"kind":{"domain":[{"url":"api.example.com"},{"url":"*.example.org"}]}}]}"#
    #expect(try parse(j).patterns == ["api.example.com", "*.example.org"])
}
@Test func parseRejectsLargeFileAndBadJSON() {
    #expect(throws: HostListError.tooLarge) { try HostList.parse(Data(count: 1_048_577)) }
    #expect(throws: HostListError.invalidJSON) { try parse("{not json") }
    #expect(throws: HostListError.notText) { try HostList.parse(Data([0xff, 0xfe, 0x00])) }
}
@Test func hostListSerializeRoundTrips() throws {
    let pats = ["api.example.com", "*.example.org"]
    let data = HostList.serialize(pats)
    let s = String(decoding: data, as: UTF8.self)
    #expect(s.hasPrefix("# Prog host list")); #expect(s.hasSuffix("\n"))
    #expect(try HostList.parse(data).patterns == pats)
}
@Test func mergeIsCaseInsensitiveAndKeepsOrder() {
    let r = HostList.merge(["B.example.com", "c.example.com"], into: ["a.example.com", "b.example.com"])
    #expect(r.merged == ["a.example.com", "b.example.com", "c.example.com"]); #expect(r.added == ["c.example.com"])
}
