import Foundation
import Testing
@testable import EyeProxyKit

@Test func masterPlaylistParsesVariantsAndRenditions() throws {
    let text = """
    #EXTM3U
    #EXT-X-VERSION:6
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",LANGUAGE="en",DEFAULT=YES,AUTOSELECT=YES,URI="audio/en.m3u8"
    #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Korean, KR",LANGUAGE="ko"
    #EXT-X-STREAM-INF:BANDWIDTH=2000000,AVERAGE-BANDWIDTH=1800000,RESOLUTION=1280x720,CODECS="avc1.640028,mp4a.40.2",FRAME-RATE=29.970,AUDIO="aud"
    hd/index.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=500000
    https://cdn.example.com/sd/index.m3u8
    """
    let base = URL(string: "https://example.com/live/master.m3u8")
    guard case .master(let m) = try #require(M3U8.parse(text, baseURL: base)) else {
        Issue.record("master 아님"); return
    }
    #expect(m.variants.count == 2)
    let hd = m.variants[0]
    #expect(hd.bandwidth == 2_000_000)
    #expect(hd.averageBandwidth == 1_800_000)
    #expect(hd.resolution == "1280x720")
    #expect(hd.codecs == "avc1.640028,mp4a.40.2")
    #expect(hd.frameRate == 29.97)
    #expect(hd.uri == "hd/index.m3u8")
    #expect(hd.absoluteURL?.absoluteString == "https://example.com/live/hd/index.m3u8")
    let sd = m.variants[1]
    #expect(sd.bandwidth == 500_000 && sd.averageBandwidth == nil && sd.resolution == nil && sd.codecs == nil && sd.frameRate == nil)
    #expect(sd.absoluteURL?.absoluteString == "https://cdn.example.com/sd/index.m3u8")

    #expect(m.renditions.count == 2)
    let audio = m.renditions[0]
    #expect(audio.type == "AUDIO" && audio.groupID == "aud" && audio.name == "English" && audio.language == "en" && audio.isDefault)
    #expect(audio.uri == "audio/en.m3u8")
    #expect(audio.absoluteURL?.absoluteString == "https://example.com/live/audio/en.m3u8")
    let subs = m.renditions[1]
    #expect(subs.type == "SUBTITLES" && subs.name == "Korean, KR" && subs.language == "ko" && !subs.isDefault)
    #expect(subs.uri == nil && subs.absoluteURL == nil)
}

@Test func mediaPlaylistResolvesRelativeURIsAndByteRanges() throws {
    let text = "#EXTM3U\r\n#EXT-X-TARGETDURATION:10\r\n#EXT-X-MEDIA-SEQUENCE:42\r\n#EXT-X-PLAYLIST-TYPE:VOD\r\n\r\n# comment\r\n#EXTINF:9.009,first\r\n#EXT-X-BYTERANGE:1000@2000\r\nseg1.ts\r\n#EXTINF:10,\r\n../other/seg2.ts\r\n#EXTINF:4.5\r\nhttps://cdn.example.com/seg3.ts\r\n#EXT-X-ENDLIST\r\n"
    let base = URL(string: "https://example.com/vod/a/master.m3u8?token=abc")
    guard case .media(let m) = try #require(M3U8.parse(text, baseURL: base)) else {
        Issue.record("media 아님"); return
    }
    #expect(m.targetDuration == 10 && m.mediaSequence == 42 && m.playlistType == "VOD" && m.hasEndList)
    #expect(m.segments.map(\.index) == [0, 1, 2])
    #expect(m.segments.map(\.duration) == [9.009, 10, 4.5])
    #expect(m.segments.map(\.title) == ["first", nil, nil])
    #expect(m.segments.map(\.uri) == ["seg1.ts", "../other/seg2.ts", "https://cdn.example.com/seg3.ts"])
    #expect(m.segments.map { $0.absoluteURL?.absoluteString } == [
        "https://example.com/vod/a/seg1.ts",
        "https://example.com/vod/other/seg2.ts",
        "https://cdn.example.com/seg3.ts",
    ])
    #expect(m.segments.map(\.byteRange) == ["1000@2000", nil, nil])

    // baseURL 없으면 절대 URL 없음.
    guard case .media(let noBase) = try #require(M3U8.parse(text, baseURL: nil)) else {
        Issue.record("media 아님"); return
    }
    #expect(noBase.segments.allSatisfy { $0.absoluteURL == nil })
}

@Test func mediaPlaylistMarksDiscontinuityAndKey() throws {
    let text = """
    #EXTM3U
    #EXT-X-TARGETDURATION:6
    #EXT-X-KEY:METHOD=AES-128,URI="https://keys.example.com/k1",IV=0x1234
    #EXTINF:6.0,
    a.ts
    #EXT-X-DISCONTINUITY
    #EXT-X-KEY:METHOD=NONE
    #EXT-X-UNKNOWN-TAG:FOO=1
    #EXTINF:6.0,
    b.ts
    #EXTINF:6.0,
    c.ts
    """
    guard case .media(let m) = try #require(M3U8.parse(text, baseURL: URL(string: "https://example.com/p.m3u8"))) else {
        Issue.record("media 아님"); return
    }
    #expect(m.segments.map(\.discontinuity) == [false, true, false])
    #expect(m.keys == [.init(method: "AES-128", uri: "https://keys.example.com/k1"), .init(method: "NONE", uri: nil)])
    #expect(!m.hasEndList && m.mediaSequence == nil && m.playlistType == nil)
}

@Test func nonPlaylistReturnsNil() {
    #expect(M3U8.parse("", baseURL: nil) == nil)
    #expect(M3U8.parse("{\"a\":1}", baseURL: nil) == nil)
    #expect(M3U8.parse("hello\n#EXTM3U\n", baseURL: nil) == nil)
}

@Test func isPlaylistDetectsPathAndContentTypes() {
    #expect(M3U8.isPlaylist(path: "/live/master.m3u8", contentType: nil))
    #expect(M3U8.isPlaylist(path: "/live/INDEX.M3U8?token=1", contentType: nil))
    #expect(M3U8.isPlaylist(path: "/live/a.m3u8#frag", contentType: nil))
    #expect(M3U8.isPlaylist(path: "/play", contentType: "application/vnd.apple.mpegurl"))
    #expect(M3U8.isPlaylist(path: "/play", contentType: "Application/X-MpegURL; charset=utf-8"))
    #expect(M3U8.isPlaylist(path: "/play", contentType: "audio/mpegurl"))
    #expect(!M3U8.isPlaylist(path: "/seg1.ts", contentType: "video/mp2t"))
    #expect(!M3U8.isPlaylist(path: "/m3u8/data.json", contentType: "application/json"))
}
