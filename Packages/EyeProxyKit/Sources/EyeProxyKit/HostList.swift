import Foundation

public enum HostListError: Error, Equatable { case tooLarge, notText, invalidJSON }

/// SSL Proxying 호스트 목록 파일(텍스트 한 줄에 패턴 하나, 또는 Proxyman SSL JSON).
public enum HostList {
    public static let maxFileSize = 1_048_576

    public struct Parsed: Equatable, Sendable { public var patterns: [String]; public var rejected: Int }

    public static func parse(_ data: Data) throws(HostListError) -> Parsed {
        guard data.count <= maxFileSize else { throw .tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw .notText }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var lines: [String] = []
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            guard let hosts = ProxymanImporter.sslHosts(Data(text.utf8)) else { throw .invalidJSON }
            lines = hosts
        } else {
            lines = text.split(whereSeparator: \.isNewline).map(String.init).filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.hasPrefix("#")
            }
        }
        return normalized(lines)
    }

    /// 그룹 시트 도메인 칸: 줄이나 쉼표로 나눈 항목. 빈 항목은 버린 것으로 세지 않는다.
    public static func patterns(fromText text: String) -> Parsed {
        normalized(text.split { $0.isNewline || $0 == "," }.filter { !$0.allSatisfy(\.isWhitespace) }.map(String.init))
    }

    private static func normalized(_ lines: [String]) -> Parsed {
        var seen = Set<String>(), patterns: [String] = [], rejected = 0
        for l in lines {
            guard let p = normalize(l) else { rejected += 1; continue }
            if seen.insert(p).inserted { patterns.append(p) }
        }
        return Parsed(patterns: patterns, rejected: rejected)
    }

    public static func normalize(_ line: String) -> String? {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("://") { s = URL(string: s)?.host ?? "" }
        if let r = s.range(of: #":\d+$"#, options: .regularExpression) { s.removeSubrange(r) }
        s = s.lowercased()
        let ok = Set("abcdefghijklmnopqrstuvwxyz0123456789.-_*?")
        return s.isEmpty || !s.allSatisfy(ok.contains) ? nil : s
    }

    public static func serialize(_ patterns: [String]) -> Data {
        let head = "# Prog host list — 한 줄에 호스트 패턴 하나. *는 임의 문자열, ?는 한 글자."
        return Data(([head] + patterns).joined(separator: "\n").appending("\n").utf8)
    }

    public static func merge(_ new: [String], into existing: [String]) -> (merged: [String], added: [String]) {
        var seen = Set(existing.map { $0.lowercased() }), added: [String] = []
        for p in new where seen.insert(p.lowercased()).inserted { added.append(p) }
        return (existing + added, added)
    }
}
