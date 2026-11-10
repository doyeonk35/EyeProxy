import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct FlowDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let id = model.selectedFlowID, let flow = model.session.flow(id) {
            VStack(spacing: 0) {
                FlowHeaderBar(flow: flow)
                SummaryView(flow: flow)
                panes(flow)
            }
        } else {
            ContentUnavailableView("요청을 선택하세요", systemImage: "network")
        }
    }

    @ViewBuilder
    private func panes(_ flow: Flow) -> some View {
        if model.settings.layout == .classic {
            HSplitView {
                request(flow).frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                response(flow).frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VSplitView {
                request(flow).frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
                response(flow).frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
            }
        }
    }

    private func request(_ flow: Flow) -> some View {
        MessagePane(title: "요청", headers: flow.request.headers, content: flow.request.body,
                    query: Self.query(flow.request.path),
                    cookies: CookieParser.requestCookies(flow.request.header("Cookie") ?? ""), flowID: flow.id,
                    raw: .request(flow.request))
    }

    private static func query(_ path: String) -> [HTTPHeader] {
        (URLComponents(string: "http://x" + path)?.queryItems ?? []).map { HTTPHeader(name: $0.name, value: $0.value ?? "") }
    }

    @ViewBuilder
    private func response(_ flow: Flow) -> some View {
        if let response = flow.response {
            let setCookies = response.headers.filter { $0.name.caseInsensitiveCompare("Set-Cookie") == .orderedSame }.map(\.value)
            MessagePane(title: "응답", headers: response.headers, content: response.body, query: nil,
                        cookies: CookieParser.responseCookies(setCookies), flowID: flow.id,
                        raw: .response(response),
                        playlistURL: M3U8.isPlaylist(path: flow.request.path, contentType: response.header("Content-Type"))
                            ? URL(string: flow.request.url) : nil)
        } else if let error = flow.error {
            ContentUnavailableView("실패", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ContentUnavailableView("응답 대기 중", systemImage: "hourglass")
        }
    }
}

/// 요청·응답 한쪽(헤더·쿼리·본문·쿠키·Raw, 재생목록이면 M3U8). Compose 창의 응답 쪽도 쓴다.
struct MessagePane: View {
    enum Tab: Hashable { case headers, query, body, cookies, raw, m3u8 }

    let title: LocalizedStringKey
    let headers: [HTTPHeader]
    let content: Data
    let query: [HTTPHeader]?
    let cookies: [HTTPHeader]
    let flowID: FlowID
    let raw: RawSource
    /// 응답이 HLS 재생목록일 때 요청 URL(상대 URI 기준). nil이면 M3U8 탭을 숨긴다.
    var playlistURL: URL?
    @State private var tab = Tab.headers
    /// 재생목록이 아닌 흐름으로 옮기면 M3U8 대신 헤더를 보인다(고른 탭은 남겨 재생목록으로 돌아오면 다시 M3U8).
    private var shownTab: Tab { tab == .m3u8 && playlistURL == nil ? .headers : tab }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Picker("", selection: Binding(get: { shownTab }, set: { tab = $0 })) {
                    Text("헤더").tag(Tab.headers)
                    if query != nil { Text("쿼리").tag(Tab.query) }
                    Text("본문").tag(Tab.body)
                    Text("쿠키").tag(Tab.cookies)
                    Text("Raw").tag(Tab.raw)
                    if playlistURL != nil { Text("M3U8").tag(Tab.m3u8) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .id(playlistURL != nil)  // 칸 수가 바뀌면 다시 만들어야 폭이 맞는다
            }
            .padding(8)
            Divider()
            // 내용 영역이 패널 높이를 꽉 채워야 머리글이 위에 고정된다(짧으면 가운데로 밀리고, NSTextView는 넘친다).
            Group {
                switch shownTab {
                case .headers: KeyValueTable(rows: headers, emptyTitle: "헤더 없음").id(flowID)
                case .query: KeyValueTable(rows: query ?? [], emptyTitle: "쿼리 없음").id(flowID)
                case .body: BodyView(data: content, headers: headers).id(flowID)
                case .cookies: KeyValueTable(rows: cookies, emptyTitle: "쿠키 없음").id(flowID)
                case .raw: RawView(source: raw).id(flowID)
                case .m3u8: M3U8View(data: content, headers: headers, baseURL: playlistURL).id(flowID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }
}

/// Raw 탭 원문과 다시 만들지 정하는 싼 키(시작 줄 + 헤더 + 본문 길이 — 본문 전체 비교는 비싸다).
/// Breakpoint Execute·Map Remote로 같은 흐름의 요청이 바뀌면 키가 바뀌어 다시 만든다.
struct RawSource {
    let key: Int
    let make: @Sendable () -> String

    static func request(_ r: FlowRequest) -> RawSource {
        RawSource(key: key(r.method, r.url, r.headers, r.body.count)) { RawMessage.request(r) }
    }

    static func response(_ r: FlowResponse) -> RawSource {
        RawSource(key: key(r.status, r.reason, r.headers, r.body.count)) { RawMessage.response(r) }
    }

    private static func key(_ a: some Hashable, _ b: String, _ headers: [HTTPHeader], _ count: Int) -> Int {
        var h = Hasher()
        h.combine(a); h.combine(b); h.combine(count)
        for x in headers { h.combine(x.name); h.combine(x.value) }
        return h.finalize()
    }
}

/// Raw 탭. 원문은 키가 바뀔 때만 메인 밖에서 만든다(세션 이벤트마다 텍스트를 다시 넣으면 스크롤·선택이 풀린다).
private struct RawView: View {
    let source: RawSource
    @State private var text: NSAttributedString?
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let text {
                CodeTextView(text: text, wrap: model.settings.wrapLongLines)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: source.key) {
            let s = await Task.detached(operation: source.make).value
            // 키가 바뀌어 이 작업이 취소됐으면 늦게 끝난 옛 결과로 새 Raw를 덮지 않는다.
            if Task.isCancelled { return }
            text = CodeTextView.base(s)
        }
    }
}
