import Compression
import Foundation

struct CompressError: Error {}

func compress(_ data: Data, _ algorithm: compression_algorithm) throws -> Data {
    let cap = data.count + 1024
    let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
    defer { dst.deallocate() }
    let n = data.withUnsafeBytes { compression_encode_buffer(dst, cap, $0.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, algorithm) }
    guard n > 0 else { throw CompressError() }
    return Data(bytes: dst, count: n)
}

/// 실제 gzip 컨테이너: 헤더 10바이트 + raw deflate + CRC32 + ISIZE.
func gzip(_ data: Data, flags: UInt8 = 0, afterHeader: [UInt8] = []) throws -> Data {
    var crc: UInt32 = 0xffff_ffff
    for b in data { crc ^= UInt32(b); for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb8_8320 & (0 &- (crc & 1))) } }
    crc = ~crc
    var out = Data([0x1f, 0x8b, 8, flags, 0, 0, 0, 0, 0, 0xff]) + afterHeader
    out += try compress(data, COMPRESSION_ZLIB)
    for v in [crc, UInt32(data.count)] { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
    return out
}
