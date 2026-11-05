import Compression
import EyeProxyCore
import Foundation

public enum DecodedBody: Equatable, Sendable { case empty, json(pretty: String), text(String), image(Data), html(String), binary(Data) }

public enum BodyDecoder {
    public static func decode(body: Data, headers: [HTTPHeader]) -> DecodedBody {
        func header(_ n: String) -> String? { headers.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }?.value }
        guard let data = decompressed(body: body, contentEncoding: header("Content-Encoding")) else { return .binary(body) }
        if data.isEmpty { return .empty }
        let type = (header("Content-Type") ?? "").split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        if type.hasPrefix("image/") { return .image(data) }
        guard let s = String(data: data, encoding: .utf8) else { return .binary(data) }
        if type == "application/json" || type.hasSuffix("+json"),
           let obj = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .fragmentsAllowed, .withoutEscapingSlashes]),
           let p = String(data: pretty, encoding: .utf8) { return .json(pretty: p) }
        return type == "text/html" ? .html(s) : .text(s)
    }

    /// nil이면 해제 실패 또는 알 수 없는 인코딩. "gzip, br"처럼 여러 개면 역순으로 푼다.
    public static func decompressed(body: Data, contentEncoding: String?) -> Data? {
        let tokens = (contentEncoding ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        var data = body
        for t in tokens.reversed() {
            switch t {
            case "", "identity": continue
            case "gzip", "x-gzip": guard let d = gunzip(data) else { return nil }; data = d
            case "deflate": guard let d = inflate(data, COMPRESSION_ZLIB) ?? inflate(data.dropFirst(2), COMPRESSION_ZLIB) else { return nil }; data = d
            case "br": guard let d = inflate(data, COMPRESSION_BROTLI) else { return nil }; data = d
            default: return nil
            }
        }
        return data
    }

    /// RFC 1952 헤더(FEXTRA/FNAME/FCOMMENT/FHCRC 포함)를 건너뛰고 raw deflate 해제. 트레일러(CRC)는 검증하지 않는다.
    private static func gunzip(_ d: Data) -> Data? {
        let b = [UInt8](d)
        guard b.count >= 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return nil }
        let flags = b[3]
        var p = 10
        if flags & 4 != 0 { guard p + 2 <= b.count else { return nil }; p += 2 + Int(b[p]) + Int(b[p + 1]) << 8 }
        for bit: UInt8 in [8, 16] where flags & bit != 0 {
            guard let z = b[min(p, b.count)...].firstIndex(of: 0) else { return nil }
            p = z + 1
        }
        if flags & 2 != 0 { p += 2 }
        guard p < b.count else { return nil }
        return inflate(Data(b[p...]), COMPRESSION_ZLIB)
    }

    private static func inflate(_ input: some DataProtocol, _ algorithm: compression_algorithm) -> Data? {
        let src = [UInt8](input)
        let chunk = 64 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { dst.deallocate() }
        var out = Data()
        let sp = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { sp.deallocate() }
        guard compression_stream_init(sp, COMPRESSION_STREAM_DECODE, algorithm) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(sp) }
        return src.withUnsafeBufferPointer { sbuf -> Data? in
            sp.pointee.src_ptr = sbuf.baseAddress ?? UnsafePointer(dst)
            sp.pointee.src_size = sbuf.count
            while true {
                sp.pointee.dst_ptr = dst
                sp.pointee.dst_size = chunk
                let status = compression_stream_process(sp, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                out.append(dst, count: chunk - sp.pointee.dst_size)
                switch status {
                case COMPRESSION_STATUS_END: return out
                case COMPRESSION_STATUS_OK: continue
                default: return nil
                }
            }
        }
    }
}
