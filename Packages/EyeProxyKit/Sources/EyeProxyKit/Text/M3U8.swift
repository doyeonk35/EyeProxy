import Foundation

public enum M3U8Playlist: Equatable, Sendable {
    case master(Master), media(Media)

    public struct Master: Equatable, Sendable {
        public var variants: [Variant]
        public var renditions: [Rendition]
    }

    public struct Variant: Equatable, Sendable {
        public var bandwidth: Int?
        public var averageBandwidth: Int?
        public var resolution: String?
        public var codecs: String?
        public var frameRate: Double?
        public var uri: String
        public var absoluteURL: URL?
    }

    /// `#EXT-X-MEDIA` (오디오·자막 등).
    public struct Rendition: Equatable, Sendable {
        public var type: String
        public var groupID: String
        public var name: String
        public var language: String?
        public var isDefault: Bool
        public var uri: String?
        public var absoluteURL: URL?
    }

    public struct Media: Equatable, Sendable {
        public var targetDuration: Int?
        public var mediaSequence: Int?
        public var playlistType: String?
        public var hasEndList: Bool
        public var segments: [Segment]
        public var keys: [Key]
    }

    public struct Segment: Equatable, Sendable {
        public var index: Int
        public var duration: Double
        public var title: String?
        public var uri: String
        public var absoluteURL: URL?
        /// `EXT-X-BYTERANGE` 원문 그대로 ("1000@2000").
        public var byteRange: String?
        public var discontinuity: Bool
    }

    public struct Key: Equatable, Sendable {
        public var method: String
        public var uri: String?
    }
}

public enum M3U8 {
    private static let contentTypes: Set<String> = ["application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl"]

    /// path가 `.m3u8`로 끝나거나(쿼리·프래그먼트 무시) Content-Type이 HLS 재생목록 타입이면 true.
    public static func isPlaylist(path: String, contentType: String?) -> Bool {
        if path.prefix(while: { $0 != "?" && $0 != "#" }).lowercased().hasSuffix(".m3u8") { return true }
        guard let mime = contentType?.split(separator: ";").first else { return false }
        return contentTypes.contains(mime.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// 첫 줄이 `#EXTM3U`가 아니면 nil. `#EXT-X-STREAM-INF`가 하나라도 있으면 master, 아니면 media. 모르는 태그는 무시.
    public static func parse(_ text: String, baseURL: URL?) -> M3U8Playlist? {
        let body = text.first == "\u{FEFF}" ? text.dropFirst() : Substring(text)
        let lines = body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.first?.hasPrefix("#EXTM3U") == true else { return nil }
        func resolve(_ uri: String) -> URL? { baseURL.flatMap { URL(string: uri, relativeTo: $0)?.absoluteURL } }
        let isMaster = lines.contains { $0.hasPrefix("#EXT-X-STREAM-INF:") }

        var variants: [M3U8Playlist.Variant] = []
        var renditions: [M3U8Playlist.Rendition] = []
        var media = M3U8Playlist.Media(hasEndList: false, segments: [], keys: [])
        var streamInf: [String: String]?
        var extinf: (duration: Double, title: String?)?
        var byteRange: String?
        var discontinuity = false

        for line in lines.dropFirst() {
            guard line.hasPrefix("#") else {
                if isMaster {
                    if let a = streamInf {
                        variants.append(.init(
                            bandwidth: a["BANDWIDTH"].flatMap { Int($0) },
                            averageBandwidth: a["AVERAGE-BANDWIDTH"].flatMap { Int($0) },
                            resolution: a["RESOLUTION"], codecs: a["CODECS"],
                            frameRate: a["FRAME-RATE"].flatMap { Double($0) },
                            uri: line, absoluteURL: resolve(line)))
                    }
                    streamInf = nil
                } else {
                    if let inf = extinf {
                        media.segments.append(.init(
                            index: media.segments.count, duration: inf.duration, title: inf.title,
                            uri: line, absoluteURL: resolve(line), byteRange: byteRange, discontinuity: discontinuity))
                    }
                    extinf = nil; byteRange = nil; discontinuity = false
                }
                continue
            }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let value = parts.count > 1 ? parts[1] : ""
            switch parts[0] {
            case "#EXT-X-STREAM-INF": streamInf = attributes(value)
            case "#EXT-X-MEDIA":
                let a = attributes(value)
                renditions.append(.init(
                    type: a["TYPE"] ?? "", groupID: a["GROUP-ID"] ?? "", name: a["NAME"] ?? "",
                    language: a["LANGUAGE"], isDefault: a["DEFAULT"] == "YES",
                    uri: a["URI"], absoluteURL: a["URI"].flatMap(resolve)))
            case "#EXT-X-TARGETDURATION": media.targetDuration = Int(value)
            case "#EXT-X-MEDIA-SEQUENCE": media.mediaSequence = Int(value)
            case "#EXT-X-PLAYLIST-TYPE": media.playlistType = String(value)
            case "#EXT-X-ENDLIST": media.hasEndList = true
            case "#EXTINF":
                let f = value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                let title = f.count > 1 ? f[1].trimmingCharacters(in: .whitespaces) : ""
                // 쉼표 앞 첫 숫자 토큰만 ("10.0 ", "-1 tvg-id=...").
                let number = (f.first ?? "").trimmingCharacters(in: .whitespaces).prefix { "0123456789.+-".contains($0) }
                extinf = (Double(number) ?? 0, title.isEmpty ? nil : title)
            case "#EXT-X-BYTERANGE": byteRange = String(value)
            case "#EXT-X-DISCONTINUITY": discontinuity = true
            case "#EXT-X-KEY":
                let a = attributes(value)
                media.keys.append(.init(method: a["METHOD"] ?? "", uri: a["URI"]))
            default: break
            }
        }
        return isMaster ? .master(.init(variants: variants, renditions: renditions)) : .media(media)
    }

    /// `KEY=VALUE,KEY="quoted, value"` → 딕셔너리. 따옴표 안 쉼표는 값에 포함.
    static func attributes(_ s: Substring) -> [String: String] {
        var result: [String: String] = [:]
        var rest = s
        while let eq = rest.firstIndex(of: "=") {
            let key = rest[..<eq].trimmingCharacters(in: .whitespaces)
            rest = rest[rest.index(after: eq)...]
            if rest.first == "\"" {
                let body = rest.dropFirst()
                let close = body.firstIndex(of: "\"") ?? body.endIndex
                result[key] = String(body[..<close])
                rest = body[close...].dropFirst()
            } else {
                let comma = rest.firstIndex(of: ",") ?? rest.endIndex
                result[key] = rest[..<comma].trimmingCharacters(in: .whitespaces)
                rest = rest[comma...]
            }
            guard let comma = rest.firstIndex(of: ",") else { break }
            rest = rest[rest.index(after: comma)...]
        }
        return result
    }
}
