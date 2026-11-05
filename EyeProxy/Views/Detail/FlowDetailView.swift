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
                    cookies: CookieParser.requestCookies(flow.request.header("Cookie") ?? ""), flowID: flow.id)
    }

    private static func query(_ path: String) -> [HTTPHeader] {
        (URLComponents(string: "http://x" + path)?.queryItems ?? []).map { HTTPHeader(name: $0.name, value: $0.value ?? "") }
    }

    @ViewBuilder
    private func response(_ flow: Flow) -> some View {
        if let response = flow.response {
            let setCookies = response.headers.filter { $0.name.caseInsensitiveCompare("Set-Cookie") == .orderedSame }.map(\.value)
            MessagePane(title: "응답", headers: response.headers, content: response.body, query: nil,
                        cookies: CookieParser.responseCookies(setCookies), flowID: flow.id)
        } else if let error = flow.error {
            ContentUnavailableView("실패", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ContentUnavailableView("응답 대기 중", systemImage: "hourglass")
        }
    }
}

private struct MessagePane: View {
    enum Tab: Hashable { case headers, query, body, cookies }

    let title: LocalizedStringKey
    let headers: [HTTPHeader]
    let content: Data
    let query: [HTTPHeader]?
    let cookies: [HTTPHeader]
    let flowID: FlowID
    @State private var tab = Tab.headers

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Picker("", selection: $tab) {
                    Text("헤더").tag(Tab.headers)
                    if query != nil { Text("쿼리").tag(Tab.query) }
                    Text("본문").tag(Tab.body)
                    Text("쿠키").tag(Tab.cookies)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(8)
            Divider()
            switch tab {
            case .headers: KeyValueTable(rows: headers, emptyTitle: "헤더 없음")
            case .query: KeyValueTable(rows: query ?? [], emptyTitle: "쿼리 없음")
            case .body: BodyView(data: content, headers: headers).id(flowID)
            case .cookies: KeyValueTable(rows: cookies, emptyTitle: "쿠키 없음")
            }
        }
    }
}