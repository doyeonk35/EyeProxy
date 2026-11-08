import EyeProxyCore
import Foundation

/// `curl …` 명령을 요청으로 푼다(`CurlExport.command(for:)`의 역). 셸 따옴표·`\` 줄바꿈만 해석하고 변수 치환은 하지 않는다.
public enum CurlParser {
    /// 값을 받지만 요청에 반영하지 않는 옵션(값이 URL로 잘못 잡히지 않게 건너뛴다).
    private static let ignoredWithValue: Set<String> = [
        "-o", "--output", "-m", "--max-time", "--connect-timeout", "-w", "--write-out", "--retry", "-x", "--proxy",
        "--cacert", "--cert", "--key", "-r", "--range",
    ]

    public static func parse(_ command: String) -> FlowRequest? {
        guard let args = tokenize(command), args.first == "curl" else { return nil }
        var method: String?, url: String?, getMode = false
        var headers: [HTTPHeader] = [], data: [String] = []
        var i = 1
        func value() -> String? {
            i += 1
            return i < args.count ? args[i] : nil
        }
        while i < args.count {
            var arg = args[i]
            var attached: String?
            // -XPOST, -H'X: y' 같은 붙여 쓴 짧은 옵션
            if arg.count > 2, arg.hasPrefix("-"), !arg.hasPrefix("--"), "XHdAbu".contains(arg[arg.index(after: arg.startIndex)]) {
                attached = String(arg.dropFirst(2))
                arg = String(arg.prefix(2))
            }
            let next = { attached ?? value() }
            switch arg {
            case "-X", "--request": method = next()?.uppercased()
            case "-H", "--header":
                if let h = next(), let colon = h.firstIndex(of: ":") {
                    headers.append(HTTPHeader(name: h[..<colon].trimmingCharacters(in: .whitespaces),
                                              value: h[h.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
                }
            case "-d", "--data", "--data-raw", "--data-binary", "--data-ascii": if let d = next() { data.append(d) }
            case "--url": url = next()
            case "-G", "--get": getMode = true
            case "-A", "--user-agent": if let v = next() { headers.append(HTTPHeader(name: "User-Agent", value: v)) }
            case "-b", "--cookie": if let v = next() { headers.append(HTTPHeader(name: "Cookie", value: v)) }
            case "-u", "--user":
                if let v = next() { headers.append(HTTPHeader(name: "Authorization", value: "Basic " + Data(v.utf8).base64EncodedString())) }
            case _ where ignoredWithValue.contains(arg): _ = next()
            case _ where arg.hasPrefix("-") && arg.count > 1: break   // --compressed, -s, -k, -L 등
            default: if url == nil { url = arg }
            }
            i += 1
        }
        guard var urlString = url else { return nil }
        var body = Data()
        let joined = data.joined(separator: "&")
        if getMode {
            if !data.isEmpty { urlString += (urlString.contains("?") ? "&" : "?") + joined }
        } else if !data.isEmpty {
            body = Data(joined.utf8)
            if !headers.contains(where: { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
                headers.append(HTTPHeader(name: "Content-Type", value: "application/x-www-form-urlencoded"))
            }
        }
        return request(url: urlString, method: method ?? (body.isEmpty ? "GET" : "POST"), headers: headers, body: body)
    }

    /// URL 문자열로 요청을 만든다. scheme이 없으면 http(curl과 같다). http·https가 아니거나 호스트가 없으면 nil.
    public static func request(url: String, method: String = "GET", headers: [HTTPHeader] = [], body: Data = Data()) -> FlowRequest? {
        var text = url.trimmingCharacters(in: .whitespaces)
        if !text.contains("://") { text = "http://" + text }
        guard let c = URLComponents(string: text), let scheme = c.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = c.host, !host.isEmpty else { return nil }
        let path = (c.percentEncodedPath.isEmpty ? "/" : c.percentEncodedPath) + (c.percentEncodedQuery.map { "?" + $0 } ?? "")
        return FlowRequest(method: method, scheme: scheme, host: host, port: c.port ?? (scheme == "http" ? 80 : 443),
                           path: path, headers: headers, body: body)
    }

    /// POSIX 셸 단어 나누기의 부분집합: '…'(그대로), "…"(\" \\ \$ \` 이스케이프), 따옴표 밖 \ 이스케이프·\ 줄바꿈 이어 붙이기.
    /// 따옴표가 닫히지 않으면 nil.
    static func tokenize(_ s: String) -> [String]? {
        var out: [String] = [], cur = "", inWord = false
        let it = Array(s)
        var i = 0
        while i < it.count {
            let ch = it[i]
            switch ch {
            case "'":
                guard let end = it[(i + 1)...].firstIndex(of: "'") else { return nil }
                cur += String(it[(i + 1)..<end]); inWord = true; i = end
            case "\"":
                inWord = true; i += 1
                while i < it.count, it[i] != "\"" {
                    if it[i] == "\\", i + 1 < it.count, it[i + 1].isNewline || "\"\\$`".contains(it[i + 1]) {
                        if !it[i + 1].isNewline { cur.append(it[i + 1]) }
                        i += 2
                    } else { cur.append(it[i]); i += 1 }
                }
                guard i < it.count else { return nil }
            case "\\":
                if i + 1 < it.count {
                    // \ 줄바꿈은 이어 붙이기("\r\n"은 Character 한 글자)
                    if !it[i + 1].isNewline { cur.append(it[i + 1]); inWord = true }
                    i += 1
                }
            case _ where ch.isWhitespace:
                if inWord { out.append(cur); cur = ""; inWord = false }
            default:
                cur.append(ch); inWord = true
            }
            i += 1
        }
        if inWord { out.append(cur) }
        return out
    }
}
