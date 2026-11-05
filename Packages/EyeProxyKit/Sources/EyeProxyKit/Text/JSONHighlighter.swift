import Foundation

public struct JSONToken: Equatable, Sendable {
    public enum Kind: Sendable { case key, string, number, keyword }
    public let kind: Kind
    public let range: NSRange  // UTF-16 단위 — NSAttributedString에 그대로 쓴다
}

public enum JSONHighlighter {
    /// BodyDecoder의 pretty 출력("key" : value) 전제. 구두점은 토큰으로 내지 않는다.
    public static func tokens(_ pretty: String) -> [JSONToken] {
        JSONScanner.scan(pretty).compactMap { t in
            switch t.kind {
            case .key: JSONToken(kind: .key, range: t.range)
            case .string: JSONToken(kind: .string, range: t.range)
            case .number: JSONToken(kind: .number, range: t.range)
            case .keyword: JSONToken(kind: .keyword, range: t.range)
            case .open, .close, .colon, .comma: nil
            }
        }
    }
}

/// Highlighter와 JSONTreeNode가 공유하는 토크나이저. 검증은 하지 않는다(BodyDecoder가 이미 검증).
enum JSONScanner {
    enum Kind { case key, string, number, keyword, open, close, colon, comma }
    struct Tok { let kind: Kind; let range: NSRange }

    static func scan(_ s: String) -> [Tok] {
        let u = Array(s.utf16)
        var out: [Tok] = []
        var i = 0
        func isNumberUnit(_ c: UInt16) -> Bool { (c >= 0x30 && c <= 0x39) || c == 0x2d || c == 0x2b || c == 0x2e || c | 0x20 == 0x65 }
        while i < u.count {
            let c = u[i]
            switch c {
            case 0x22:
                var j = i + 1
                while j < u.count, u[j] != 0x22 { j += u[j] == 0x5c ? 2 : 1 }
                let end = min(j, u.count - 1)
                var k = end + 1
                while k < u.count, u[k] == 0x20 { k += 1 }
                let isKey = k < u.count && u[k] == 0x3a
                out.append(Tok(kind: isKey ? .key : .string, range: NSRange(location: i, length: end - i + 1)))
                i = end + 1
            case 0x7b, 0x5b: out.append(Tok(kind: .open, range: NSRange(location: i, length: 1))); i += 1
            case 0x7d, 0x5d: out.append(Tok(kind: .close, range: NSRange(location: i, length: 1))); i += 1
            case 0x3a: out.append(Tok(kind: .colon, range: NSRange(location: i, length: 1))); i += 1
            case 0x2c: out.append(Tok(kind: .comma, range: NSRange(location: i, length: 1))); i += 1
            case 0x74, 0x66, 0x6e:  // t f n → true/false/null
                var j = i
                while j < u.count, u[j] >= 0x61, u[j] <= 0x7a { j += 1 }
                out.append(Tok(kind: .keyword, range: NSRange(location: i, length: j - i))); i = j
            default:
                if isNumberUnit(c) {
                    var j = i
                    while j < u.count, isNumberUnit(u[j]) { j += 1 }
                    out.append(Tok(kind: .number, range: NSRange(location: i, length: j - i))); i = j
                } else { i += 1 }
            }
        }
        return out
    }
}
