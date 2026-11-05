import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct FlowDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let id = model.selectedFlowID, let flow = model.session.flow(id) {
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
        } else {
            ContentUnavailableView("요청을 선택하세요", systemImage: "network")
        }
    }

    private func request(_ flow: Flow) -> some View {
        MessagePane(title: "요청", summary: "\(flow.request.method) \(flow.request.url)",
                    headers: flow.request.headers, content: flow.request.body,
                    query: Self.query(flow.request.path), flowID: flow.id)
    }

    private static func query(_ path: String) -> [HTTPHeader] {
        (URLComponents(string: "http://x" + path)?.queryItems ?? []).map { HTTPHeader(name: $0.name, value: $0.value ?? "") }
    }

    @ViewBuilder
    private func response(_ flow: Flow) -> some View {
        if let response = flow.response {
            MessagePane(title: "응답", summary: "\(response.status) \(response.reason)",
                        headers: response.headers, content: response.body, query: nil, flowID: flow.id)
        } else if let error = flow.error {
            ContentUnavailableView("실패", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ContentUnavailableView("응답 대기 중", systemImage: "hourglass")
        }
    }
}

private struct MessagePane: View {
    enum Tab: Hashable { case headers, query, body }

    let title: LocalizedStringKey
    let summary: String
    let headers: [HTTPHeader]
    let content: Data
    let query: [HTTPHeader]?
    let flowID: FlowID
    @State private var tab = Tab.headers

    private var none: some View { Text("(없음)").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Text(summary).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                Picker("", selection: $tab) {
                    Text("헤더").tag(Tab.headers)
                    if query != nil { Text("쿼리").tag(Tab.query) }
                    Text("본문").tag(Tab.body)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(8)
            Divider()
            switch tab {
            case .headers: HeadersView(headers: headers)
            case .query:
                if let query, !query.isEmpty { HeadersView(headers: query) } else { none }
            case .body: BodyView(data: content, headers: headers).id(flowID)
            }
        }
    }
}