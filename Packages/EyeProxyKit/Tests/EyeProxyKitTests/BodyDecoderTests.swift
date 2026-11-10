import EyeProxyCore
import Compression
import Foundation
import Testing
@testable import EyeProxyKit

private func h(_ n: String, _ v: String) -> HTTPHeader { .init(name: n, value: v) }

/// Appearance ▸ Tab Width: JSON Pretty 들여쓰기 칸 수(기본 2).
@Test func jsonIndentFollowsTabWidth() {
    let body = Data(#"{"a":[1]}"#.utf8), headers = [h("Content-Type", "application/json")]
    let four = "{\n    \"a\" : [\n        1\n    ]\n}"
    #expect(BodyDecoder.json(body: body, headers: headers, indent: 4) == four)
    #expect(BodyDecoder.decode(body: body, headers: headers, indent: 4) == .json(pretty: four, raw: #"{"a":[1]}"#))
    #expect(BodyDecoder.json(body: body, headers: headers) == "{\n  \"a\" : [\n    1\n  ]\n}")
}

@Test func decodesGzipJSON() throws {
    let gz = try gzip(Data(#"{"a":1}"#.utf8))
    #expect(BodyDecoder.decode(body: gz, headers: [h("Content-Encoding", "gzip"), h("Content-Type", "application/json")]) == .json(pretty: "{\n  \"a\" : 1\n}", raw: "{\"a\":1}"))
}

@Test func gzipWithFNAMESkipsHeaderField() throws {
    let gz = try gzip(Data("hi".utf8), flags: 8, afterHeader: Array("a.txt".utf8) + [0])
    #expect(BodyDecoder.decode(body: gz, headers: [h("content-encoding", "GZIP"), h("Content-Type", "text/plain; charset=utf-8")]) == .text("hi"))
}

@Test func decodesBrotli() throws {  // br 바이트는 테스트 시점에 COMPRESSION_BROTLI로 인코딩해 만든다.
    let br = try compress(Data("hello".utf8), COMPRESSION_BROTLI)
    #expect(BodyDecoder.decode(body: br, headers: [h("Content-Encoding", "br"), h("Content-Type", "text/plain")]) == .text("hello"))
}

@Test func deflateRawAndZlibWrapped() throws {
    let raw = try compress(Data("abc".utf8), COMPRESSION_ZLIB)
    #expect(BodyDecoder.decompressed(body: raw, contentEncoding: "deflate") == Data("abc".utf8))
    #expect(BodyDecoder.decompressed(body: Data([0x78, 0x9c]) + raw, contentEncoding: "deflate") == Data("abc".utf8))
}

@Test func inflateStopsAtOutputLimit() throws {
    let zeros = try compress(Data(count: 1 << 20), COMPRESSION_ZLIB)
    #expect(BodyDecoder.inflate(zeros, COMPRESSION_ZLIB, limit: 1 << 20)?.count == 1 << 20)
    #expect(BodyDecoder.inflate(zeros, COMPRESSION_ZLIB, limit: (1 << 20) - 1) == nil)
}

@Test func badOrUnknownEncodingIsBinary() {
    let body = Data([1, 2, 3, 4])
    #expect(BodyDecoder.decode(body: body, headers: [h("Content-Encoding", "gzip")]) == .binary(body))
    #expect(BodyDecoder.decode(body: body, headers: [h("Content-Encoding", "zstd")]) == .binary(body))
    #expect(BodyDecoder.decompressed(body: body, contentEncoding: "identity") == body)
}

@Test func nonUTF8FallsBackToBinary() { #expect(BodyDecoder.decode(body: Data([0xff, 0xfe, 0x00]), headers: [h("Content-Type", "text/plain")]) == .binary(Data([0xff, 0xfe, 0x00]))) }
@Test func imageByContentType() { #expect(BodyDecoder.decode(body: Data([1]), headers: [h("Content-Type", "image/png")]) == .image(Data([1]))) }
@Test func classification() {
    #expect(BodyDecoder.decode(body: Data(), headers: []) == .empty)
    #expect(BodyDecoder.decode(body: Data("<p>".utf8), headers: [h("Content-Type", "text/html")]) == .html("<p>"))
    #expect(BodyDecoder.decode(body: Data("{bad".utf8), headers: [h("Content-Type", "application/ld+json")]) == .text("{bad"))
    #expect(BodyDecoder.decode(body: Data("x".utf8), headers: []) == .text("x"))
}

private func json(_ s: String) -> DecodedBody { BodyDecoder.decode(body: Data(s.utf8), headers: [h("Content-Type", "application/json")]) }

@Test func jsonPreservesKeyOrderAndBigIntegers() {
    #expect(json(#"{"z":1,"a":2}"#) == .json(pretty: "{\n  \"z\" : 1,\n  \"a\" : 2\n}", raw: #"{"z":1,"a":2}"#))
    #expect(json("12345678901234567890") == .json(pretty: "12345678901234567890", raw: "12345678901234567890"))
    #expect(json(#"{"n":12345678901234567890}"#) == .json(pretty: "{\n  \"n\" : 12345678901234567890\n}", raw: #"{"n":12345678901234567890}"#))
}

@Test func jsonNestedEmptyAndEscapes() {
    #expect(json(#"{"a":[1,{"b":[]},{}],"c":"\u00e9\"x\\/"}"#) == .json(pretty: "{\n  \"a\" : [\n    1,\n    {\n      \"b\" : []\n    },\n    {}\n  ],\n  \"c\" : \"\\u00e9\\\"x\\\\/\"\n}", raw: #"{"a":[1,{"b":[]},{}],"c":"\u00e9\"x\\/"}"#))
}

@Test func invalidJSONFallsBackToText() {
    for bad in ["{\"a\":", "{\"a\":1", "[1,2}", "nope", "{\"a\"", "}"] { #expect(json(bad) == .text(bad)) }
}

@Test func emptyBodyWithContentEncodingIsEmpty() {
    #expect(BodyDecoder.decode(body: Data(), headers: [h("Content-Encoding", "gzip")]) == .empty)
}

@Test func malformedGzipDoesNotCrash() throws {
    let ok = try gzip(Data("hello hello hello".utf8))
    let cases: [Data] = [
        Data([0x1f, 0x8b, 8, 8, 0, 0, 0, 0, 0, 0xff] + Array("name-without-nul".utf8) + [UInt8](repeating: 7, count: 8)),  // FNAME 미종료
        Data([0x1f, 0x8b, 8, 4, 0, 0, 0, 0, 0, 0xff, 0xff, 0xff] + [UInt8](repeating: 1, count: 8)),                      // FEXTRA 길이 초과
        Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff]),                                                                    // 헤더만
        Data([0x1f, 0x8b, 8, 2, 0, 0, 0, 0, 0, 0xff]),                                                                    // FHCRC만
        ok.prefix(10 + (ok.count - 18) / 2),                                                                                // deflate 중간 절단
    ]
    for c in cases {
        #expect(BodyDecoder.decompressed(body: c, contentEncoding: "gzip") == nil)
        #expect(BodyDecoder.decode(body: c, headers: [h("Content-Encoding", "gzip")]) == .binary(c))
    }
}

@Test func structurallyInvalidJSONIsText() {
    let bad = ["[1 2]", #"{"a":1 "b":2}"#, "true false", "{} {}", "1 2", "{:}", "{,}", "[1,]", #"{"a":,}"#, "{1:2}", #"{"a" "b"}"#,
               "01", "1.", "-", "+1", "1e", "nan", #"["\x"]"#, #"["\u12G4"]"#, "[\"a\nb\"]", "[,1]", #"{"a":1,}"#, "]", "[}"]
    for s in bad { #expect(json(s) == .text(s), "\(s)") }
}

@Test func validJSONStillFormats() {
    #expect(json("[]") == .json(pretty: "[]", raw: "[]"))
    #expect(json(" [ 1 , -2.5e+3 , true , null , \"x\" ] ") == .json(pretty: "[\n  1,\n  -2.5e+3,\n  true,\n  null,\n  \"x\"\n]", raw: " [ 1 , -2.5e+3 , true , null , \"x\" ] "))
    #expect(json(#"{"a":{"b":[0,{}]}}"#) == .json(pretty: "{\n  \"a\" : {\n    \"b\" : [\n      0,\n      {}\n    ]\n  }\n}", raw: #"{"a":{"b":[0,{}]}}"#))
    #expect(json("\"s\"") == .json(pretty: "\"s\"", raw: "\"s\""))
}

@Test(.timeLimit(.minutes(1))) func deeplyNestedJSONFallsBackToText() {
    let s = String(repeating: "[", count: 100_000)
    #expect(json(s) == .text(s))
    let ok = String(repeating: "[", count: 512) + String(repeating: "]", count: 512)
    if case .json = json(ok) {} else { Issue.record("depth 512 should format") }
}
