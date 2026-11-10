import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct FlowDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let id = model.selectedFlowID, let flow = model.session.flow(id) {
            VStack(spacing: 0) {
                FlowHeaderBar(flow: flow)
                panes(flow)
            }
        } else {
            ContentUnavailableView("요청을 선택하세요", systemImage: "network")
        }
    }

    /// 응답 쪽은 ZStack으로 감싼다 — 안내·대기·패널로 갈래가 바뀔 때 분할 뷰 칸이 새로 꽂히면 나눔선이 새 보기의
    /// 이상 폭으로 밀려 그대로 남았다(실측: HTTPS 안내 후 응답 칸이 좁아짐).
    @ViewBuilder
    private func panes(_ flow: Flow) -> some View {
        if model.settings.layout == .classic {
            HSplitView {
                request(flow).frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                ZStack { response(flow) }.frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VSplitView {
                request(flow).frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
                ZStack { response(flow) }.frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
            }
        }
    }

    /// 응답이 HLS 재생목록이면 요청 URL(상대 URI 기준). 아니면 nil — M3U8 탭을 숨긴다.
    private static func playlistURL(_ flow: Flow) -> URL? {
        guard let response = flow.response,
              M3U8.isPlaylist(path: flow.request.path, contentType: response.header("Content-Type")) else { return nil }
        return URL(string: flow.request.url)
    }

    private func request(_ flow: Flow) -> some View {
        let playlist = Self.playlistURL(flow)
        return MessagePane(title: "요청", tabs: DetailTabs.request(flow.request, isPlaylist: playlist != nil),
                           headers: flow.request.headers, content: flow.request.body, flowID: flow.id, raw: .request(flow.request),
                           query: Self.query(flow.request.path), summary: SummaryView.rows(flow, model: model), playlistURL: playlist)
    }

    private static func query(_ path: String) -> [HTTPHeader] {
        (URLComponents(string: "http://x" + path)?.queryItems ?? []).map { HTTPHeader(name: $0.name, value: $0.value ?? "") }
    }

    @ViewBuilder
    private func response(_ flow: Flow) -> some View {
        if flow.isTunnel, flow.error == nil {
            HTTPSNotice(flow: flow)
        } else if let response = flow.response {
            let playlist = Self.playlistURL(flow)
            MessagePane(title: "응답", tabs: DetailTabs.response(response, isPlaylist: playlist != nil),
                        headers: response.headers, content: response.body, flowID: flow.id, raw: .response(response),
                        playlistURL: playlist)
        } else if let error = flow.error {
            ContentUnavailableView("실패", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ContentUnavailableView("응답 대기 중", systemImage: "hourglass")
        }
    }
}

/// 복호화하지 않은 터널(CONNECT 행)의 응답 자리(스펙 §10). 켜면 v1.1.1의 터널 재판정으로 기기가 다시 연결할 때 복호화된다.
/// 앱을 모르면(원격 기기) 첫 버튼만.
private struct HTTPSNotice: View {
    @Environment(AppModel.self) private var model
    let flow: Flow

    var body: some View {
        let host = flow.request.host
        let listed = model.settings.sslEnabled && model.settings.sslPatterns.contains(host)
        VStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(verbatim: "HTTPS Response").font(.headline)
            Text("암호화된 터널이라 내용을 볼 수 없습니다 — SSL Proxying을 켜면 다음 연결부터 복호화해 보여 줍니다")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            HStack(spacing: 8) {
                Button("Enable only this domain") { Task { await model.enableSSLProxying(for: host) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(listed)
                    .help("\(host)을(를) SSL Proxying 목록에 넣습니다")
                if let app = model.processKey(for: flow) {
                    Text(verbatim: "or").foregroundStyle(.tertiary)
                    Button { Task { await model.enableSSLProxying(forHostsOfApp: app) } } label: {
                        Text(verbatim: "Enable all domains from \"\(model.clientName(for: flow))\"")
                    }
                    .help("이 앱이 연 모든 도메인을 SSL Proxying 목록에 넣습니다")
                }
            }
            if listed {
                Label("SSL Proxying 목록에 있습니다 — 다시 연결하면 복호화됩니다", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 요청·응답 한쪽 패널. 탭 줄 `Header · … │ … · JSON`(묶음은 `DetailTabs`) + 오른쪽 `≡`(표 거르기). Compose 창의 응답 쪽도 쓴다.
struct MessagePane: View {
    let title: LocalizedStringKey
    let tabs: [[DetailTab]]
    let headers: [HTTPHeader]
    let content: Data
    let flowID: FlowID
    let raw: RawSource
    var query: [HTTPHeader] = []
    var summary: [HTTPHeader] = []
    /// 응답이 HLS 재생목록일 때 요청 URL(상대 URI 기준).
    var playlistURL: URL?
    /// 마지막으로 고른 탭. 흐름을 바꿔도 남고, 이 흐름에 없는 탭이면 Header를 보인다(돌아오면 다시 그 탭).
    @State private var tab = DetailTab.header
    @State private var filterVisible = false
    @State private var filterOptions = TableFilter()
    private var shownTab: DetailTab { DetailTabs.shown(tab, in: tabs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title).font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(Array(tabs.enumerated()), id: \.offset) { i, group in
                            if i > 0 { Divider().frame(height: 14).padding(.horizontal, 4) }
                            ForEach(group, id: \.self) { tabButton($0) }
                        }
                    }
                }
                Button { filterVisible.toggle() } label: {
                    Label("표 거르기", systemImage: "line.3.horizontal").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(filterVisible && shownTab.isTable ? Color.accentColor : .secondary)
                .disabled(!shownTab.isTable)
                .help("표 거르기 (⌘F)")
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            Divider()
            // 내용 영역이 패널 높이를 꽉 채워야 머리글이 위에 고정된다(짧으면 가운데로 밀리고, NSTextView는 넘친다).
            // 흐름이 바뀌면 표 검색어·본문 보기·트리 펼침을 새로 시작한다.
            content(shownTab)
                .id(flowID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    private func tabButton(_ t: DetailTab) -> some View {
        let on = t == shownTab
        return Button { tab = t } label: {
            Text(verbatim: t.title)
                .font(.system(size: 12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? .primary : .secondary)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(on ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private func table(_ rows: [HTTPHeader], _ empty: LocalizedStringKey) -> some View {
        KeyValueTable(rows: rows, emptyTitle: empty, filterVisible: $filterVisible, options: $filterOptions)
    }

    @ViewBuilder
    private func content(_ tab: DetailTab) -> some View {
        switch tab {
        case .header: table(headers, "헤더 없음")
        case .query: table(query, "쿼리 없음")
        case .body: BodyView(data: content, headers: headers)
        case .form:
            // ponytail: 탭을 그릴 때마다 본문을 다시 푼다(폼 본문은 작다). 큰 multipart가 느리면 .task로 옮긴다.
            table(FormFields.parse(body: BodyDecoder.decompressed(body: content, contentEncoding: header("Content-Encoding")) ?? content,
                                   contentType: header("Content-Type")), "폼 필드 없음")
        case .cookies: table(CookieParser.requestCookies(header("Cookie") ?? ""), "쿠키 없음")
        case .auth: table(AuthFields.parse(header("Authorization") ?? ""), "인증 정보 없음")
        case .setCookie:
            table(CookieParser.responseCookies(headers.filter { $0.name.caseInsensitiveCompare("Set-Cookie") == .orderedSame }.map(\.value)),
                  "쿠키 없음")
        case .raw: RawView(source: raw)
        case .summary: table(summary, "")
        case .treeview: JSONTabView(data: content, headers: headers, tree: true)
        case .m3u8: M3U8View(data: content, headers: headers, baseURL: playlistURL)
        case .json: JSONTabView(data: content, headers: headers, tree: false)
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
