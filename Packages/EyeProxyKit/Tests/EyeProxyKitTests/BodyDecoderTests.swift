import EyeProxyCore
import Compression
import Foundation
import Testing
@testable import EyeProxyKit

private func h(_ n: String, _ v: String) -> HTTPHeader { .init(name: n, value: v) }

@Test func decodesGzipJSON() throws {
    let gz = try gzip(Data(#"{"a":1}"#.utf8))
    #expect(BodyDecoder.decode(body: gz, headers: [h("Content-Encoding", "gzip"), h("Content-Type", "application/json")]) == .json(pretty: "{\n  \"a\" : 1\n}"))
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
