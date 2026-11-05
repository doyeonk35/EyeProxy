import Compression
import EyeProxyCore
import Foundation

public enum DecodedBody: Equatable, Sendable { case empty, json(pretty: String), text(String), image(Data), html(String), binary(Data) }

public enum BodyDecoder {
    public static func decode(body: Data, headers: [HTTPHeader]) -> DecodedBody {
        func header(_ n: String) -> String? { headers.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }?.value }
        if body.isEmpty { return .empty }
        guard let data = decompressed(body: body, contentEncoding: header("Content-Encoding")) else { return .binary(body) }
        if data.isEmpty { return .empty }
        let type = (header("Content-Type") ?? "").split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        if type.hasPrefix("image/") { return .image(data) }
        guard let s = String(data: data, encoding: .utf8) else { return .binary(data) }
        if type == "application/json" || type.hasSuffix("+json"), let p = reindentJSON(Array(data)) { return .json(pretty: p) }
        return type == "text/html" ? .html(s) : .text(s)
    }

    private static let jsonSpace: Set<UInt8> = [32, 9, 10, 13]
    private static let jsonDelimiters: Set<UInt8> = [32, 9, 10, 13, 0x7b, 0x7d, 0x5b, 0x5d, 0x3a, 0x2c, 0x22]
    private static let maxJSONDepth = 512

    private enum JSONState { case value, valueOrClose, key, keyOrClose, colon, afterValue, done }

    /// 키 순서·숫자 리터럴·이스케이프를 그대로 두고 들여쓰기만 다시 하는 토큰 기반 정렬.
    /// 문법(상태 기계)을 검증하며, JSON이 아니거나 깊이(512)·출력 크기(입력×4+1MB) 상한을 넘으면 nil.
    private static func reindentJSON(_ b: [UInt8]) -> String? {
        var out: [UInt8] = []
        let maxOut = b.count * 4 + 1_000_000
        var stack: [UInt8] = []          // 열린 괄호 종류: "{" 또는 "["
        var state = JSONState.value
        var justOpened = false
        var i = 0
        func nl() { out.append(10); out.append(contentsOf: [UInt8](repeating: 32, count: stack.count * 2)) }
        func flush() { if justOpened { justOpened = false; nl() } }
        func ended() { state = stack.isEmpty ? .done : .afterValue }

        while i < b.count {
            let c = b[i]
            if jsonSpace.contains(c) { i += 1; continue }
            if out.count > maxOut { return nil }
            let wantsValue = state == .value || state == .valueOrClose
            switch c {
            case 0x7b, 0x5b:  // { [
                guard wantsValue, stack.count < maxJSONDepth else { return nil }
                flush(); out.append(c); stack.append(c); justOpened = true
                state = c == 0x7b ? .keyOrClose : .valueOrClose; i += 1
            case 0x7d, 0x5d:  // } ]
                let open: UInt8 = c == 0x7d ? 0x7b : 0x5b
                guard stack.last == open, state == .afterValue || state == (open == 0x7b ? .keyOrClose : .valueOrClose) else { return nil }
                stack.removeLast()
                if justOpened { justOpened = false } else { nl() }
                out.append(c); ended(); i += 1
            case 0x2c:  // ,
                guard state == .afterValue, let top = stack.last else { return nil }
                out.append(c); nl(); state = top == 0x7b ? .key : .value; i += 1
            case 0x3a:  // :
                guard state == .colon else { return nil }
                out.append(contentsOf: Array(" : ".utf8)); state = .value; i += 1
            case 0x22:  // "
                guard wantsValue || state == .key || state == .keyOrClose else { return nil }
                var j = i + 1
                while true {
                    guard j < b.count, b[j] >= 0x20 else { return nil }
                    if b[j] == 0x22 { break }
                    if b[j] == 0x5c {
                        guard j + 1 < b.count else { return nil }
                        switch b[j + 1] {
                        case 0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74: j += 2
                        case 0x75:
                            guard j + 5 < b.count, b[(j + 2)...(j + 5)].allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 | 0x20 >= 0x61 && $0 | 0x20 <= 0x66) }) else { return nil }
                            j += 6
                        default: return nil
                        }
                    } else { j += 1 }
                }
                flush(); out.append(contentsOf: b[i...j]); i = j + 1
                if wantsValue { ended() } else { state = .colon }
            default:
                guard wantsValue else { return nil }
                var j = i
                while j < b.count, !jsonDelimiters.contains(b[j]) { j += 1 }
                guard isJSONLiteral(b[i..<j]) else { return nil }
                flush(); out.append(contentsOf: b[i..<j]); ended(); i = j
            }
        }
        return state == .done && stack.isEmpty ? String(decoding: out, as: UTF8.self) : nil
    }

    /// true/false/null 또는 -?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?
    private static func isJSONLiteral(_ t: ArraySlice<UInt8>) -> Bool {
        if [Array("true".utf8), Array("false".utf8), Array("null".utf8)].contains(Array(t)) { return true }
        var i = t.startIndex
        func digits() -> Bool { let s = i; while i < t.endIndex, t[i] >= 0x30, t[i] <= 0x39 { i += 1 }; return i > s }
        if i < t.endIndex, t[i] == 0x2d { i += 1 }
        guard i < t.endIndex else { return false }
        if t[i] == 0x30 { i += 1 } else if !digits() { return false }
        if i < t.endIndex, t[i] == 0x2e { i += 1; if !digits() { return false } }
        if i < t.endIndex, t[i] | 0x20 == 0x65 {
            i += 1
            if i < t.endIndex, t[i] == 0x2b || t[i] == 0x2d { i += 1 }
            if !digits() { return false }
        }
        return i == t.endIndex
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

    /// ponytail: 해제 결과 256 MB 상한(압축 폭탄). 넘으면 nil → 원본을 binary로 보여준다.
    static func inflate(_ input: some DataProtocol, _ algorithm: compression_algorithm, limit: Int = 256 * 1024 * 1024) -> Data? {
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
                if out.count > limit { return nil }
                switch status {
                case COMPRESSION_STATUS_END: return out
                case COMPRESSION_STATUS_OK: continue
                default: return nil
                }
            }
        }
    }
}
