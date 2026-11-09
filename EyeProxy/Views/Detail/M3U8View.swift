import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

/// 응답 M3U8 탭(스펙 §7): master면 변형·렌디션 표, media면 요약 줄 + 세그먼트·키 표. URI는 절대 URL, 우클릭으로 복사.
struct M3U8View: View {
    let data: Data
    let headers: [HTTPHeader]
    let baseURL: URL?
    @State private var playlist: M3U8Playlist??

    var body: some View {
        Group {
            switch playlist {
            case nil: ProgressView()
            case .some(nil): ContentUnavailableView("재생목록이 아닙니다", systemImage: "list.bullet.rectangle")
            case .master(let m)??: master(m)
            case .media(let m)??: media(m)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let (body, headers, base) = (data, headers, baseURL)
            playlist = await Task.detached {
                let encoding = headers.first { $0.name.caseInsensitiveCompare("Content-Encoding") == .orderedSame }?.value
                let text = String(decoding: BodyDecoder.decompressed(body: body, contentEncoding: encoding) ?? body, as: UTF8.self)
                return M3U8.parse(text, baseURL: base)
            }.value
        }
    }

    private func master(_ m: M3U8Playlist.Master) -> some View {
        VSplitView {
            titled("변형", Table(rows(m.variants)) {
                TableColumn("BANDWIDTH") { Text($0.value.bandwidth.map(String.init) ?? "") }.width(min: 60, ideal: 80)
                TableColumn("AVERAGE-BANDWIDTH") { Text($0.value.averageBandwidth.map(String.init) ?? "") }.width(min: 60, ideal: 80)
                TableColumn("RESOLUTION") { Text($0.value.resolution ?? "") }.width(min: 60, ideal: 80)
                TableColumn("CODECS") { Text($0.value.codecs ?? "") }.width(min: 60, ideal: 150)
                TableColumn("FRAME-RATE") { Text($0.value.frameRate.map { String($0) } ?? "") }.width(min: 40, ideal: 60)
                TableColumn("URI") { uri($0.value.absoluteURL?.absoluteString ?? $0.value.uri) }.width(min: 200, ideal: 300)
            })
            if !m.renditions.isEmpty {
                titled("렌디션", Table(rows(m.renditions)) {
                    TableColumn("TYPE") { Text($0.value.type) }.width(min: 50, ideal: 80)
                    TableColumn("GROUP-ID") { Text($0.value.groupID) }.width(min: 50, ideal: 70)
                    TableColumn("NAME") { Text($0.value.name) }.width(min: 50, ideal: 90)
                    TableColumn("LANGUAGE") { Text($0.value.language ?? "") }.width(min: 40, ideal: 70)
                    TableColumn("DEFAULT") { Text($0.value.isDefault ? "YES" : "NO") }.width(min: 40, ideal: 60)
                    TableColumn("URI") { uri($0.value.absoluteURL?.absoluteString ?? $0.value.uri ?? "") }.width(min: 200, ideal: 300)
                })
            }
        }
    }

    private func media(_ m: M3U8Playlist.Media) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: [
                "TARGETDURATION \(m.targetDuration.map(String.init) ?? "-")",
                "MEDIA-SEQUENCE \(m.mediaSequence.map(String.init) ?? "-")",
                "PLAYLIST-TYPE \(m.playlistType ?? "-")",
                "ENDLIST \(m.hasEndList ? "YES" : "NO")",
                "세그먼트 \(m.segments.count)개",
            ].joined(separator: " · "))
            .font(.callout).textSelection(.enabled).padding(8)
            Divider()
            VSplitView {
                titled("세그먼트", Table(rows(m.segments)) {
                    // 미디어 시퀀스 번호(요약 줄의 MEDIA-SEQUENCE부터).
                    TableColumn("#") { Text(String((m.mediaSequence ?? 0) + $0.value.index)).monospacedDigit() }.width(min: 30, ideal: 44)
                    TableColumn("길이") { Text(String($0.value.duration)).monospacedDigit() }.width(min: 40, ideal: 64)
                    TableColumn("URI") { uri($0.value.absoluteURL?.absoluteString ?? $0.value.uri) }.width(min: 200, ideal: 300)
                    TableColumn("BYTERANGE") { Text($0.value.byteRange ?? "") }.width(min: 60, ideal: 110)
                    TableColumn("DISCONTINUITY") { Text($0.value.discontinuity ? "●" : "") }.width(min: 40, ideal: 100)
                })
                if !m.keys.isEmpty {
                    titled("키", Table(rows(m.keys)) {
                        TableColumn("METHOD") { Text($0.value.method) }.width(min: 60, ideal: 100)
                        TableColumn("URI") { uri($0.value.absoluteURL?.absoluteString ?? $0.value.uri ?? "") }
                    })
                }
            }
        }
    }

    /// 표 위 작은 제목. 줄무늬를 끄면 빈 자리에 둥근 빈 줄이 그려지지 않는다(목록과 같은 설정).
    private func titled(_ title: LocalizedStringKey, _ table: some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
            table.alternatingRowBackgrounds(.disabled)
        }
    }

    private func uri(_ s: String) -> some View {
        Text(s).lineLimit(1).truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button("URL 복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(s, forType: .string)
                }
            }
    }

    /// Table은 Identifiable 행이 필요하다 — 순서를 id로 쓴다.
    private func rows<T>(_ items: [T]) -> [Indexed<T>] { items.enumerated().map { Indexed(id: $0.offset, value: $0.element) } }
}

private struct Indexed<T>: Identifiable {
    let id: Int
    let value: T
}
