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
                    headers: flow.request.headers, content: flow.request.body)
    }

    @ViewBuilder
    private func response(_ flow: Flow) -> some View {
        if let response = flow.response {
            MessagePane(title: "응답", summary: "\(response.status) \(response.reason)",
                        headers: response.headers, content: response.body)
        } else if let error = flow.error {
            ContentUnavailableView("실패", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ContentUnavailableView("응답 대기 중", systemImage: "hourglass")
        }
    }
}

private struct MessagePane: View {
    enum Tab: Hashable { case headers, body }

    let title: LocalizedStringKey
    let summary: String
    let headers: [HTTPHeader]
    let content: Data
    @State private var tab = Tab.headers

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Text(summary).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                Picker("", selection: $tab) {
                    Text("헤더").tag(Tab.headers)
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
            case .body: rawBody
            }
        }
    }

    /// P1 Raw 본문. Task 14의 BodyView가 대체한다.
    @ViewBuilder private var rawBody: some View {
        if let text = Self.rawText(content, headers: headers) {
            ScrollView {
                // ponytail: 거대한 Text는 느리다 → 앞 100k자만. Task 14 BodyView에서 해소.
                Text(text.count > Self.limit ? String(text.prefix(Self.limit)) + "\n…" : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        } else {
            ContentUnavailableView("본문 없음", systemImage: "doc")
        }
    }

    private static let limit = 100_000

    static func rawText(_ data: Data, headers: [HTTPHeader]) -> String? {
        switch BodyDecoder.decode(body: data, headers: headers) {
        case .empty: return nil
        case .json(let s), .text(let s), .html(let s): return s
        case .image(let d), .binary(let d): return String(localized: "(바이너리 \(d.count)바이트)")
        }
    }
}
