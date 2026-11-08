import EyeProxyCore
import EyeProxyKit
import SwiftUI

/// Compose 창(스펙 §5.8): 위 Method·URL·SEND, 왼쪽 요청 편집(Header·Query·Body·Raw), 오른쪽 응답, 아래 Template·History·(…).
/// 요청은 EyeProxy 프록시를 거쳐 나가 메인 목록에도 기록된다.
struct ComposeView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = BreakpointDraft(request: ComposeView.emptyRequest)
    @State private var urlText = ""
    @State private var result: ComposeResult?
    @State private var error: String?
    @State private var sending: Task<Void, Never>?
    @State private var timeout: TimeInterval? = 60
    @State private var history: [ComposeHistoryEntry] = []
    @State private var importing = false
    @State private var customTimeout = false
    @State private var customTimeoutText = ""
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar.padding(10)
            Divider()
            HSplitView {
                requestPane.frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                responsePane.frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            bottomBar.padding(.horizontal, 10).padding(.vertical, 6)
        }
        .frame(minWidth: 900, minHeight: 520)
        .onAppear {
            history = ComposeHistory.load()
            takeSeed()
        }
        .onChange(of: model.composeSeed) { _, _ in takeSeed() }
        // URL 칸 → 요청. 붙여 넣은 cURL은 메서드·헤더·본문까지 푼다.
        .onChange(of: urlText) { _, text in
            if text.trimmingCharacters(in: .whitespaces).hasPrefix("curl "), let r = CurlParser.parse(text) {
                load(r)
            } else if let r = CurlParser.request(url: text), r.url != draft.request.url {
                (draft.request.scheme, draft.request.host, draft.request.port, draft.request.path) = (r.scheme, r.host, r.port, r.path)
            }
        }
        // Query·Raw 편집 → URL 칸. 입력 중인 URL과 같은 요청이면 건드리지 않는다(커서 유지).
        .onChange(of: draft.request.url) { _, url in
            if CurlParser.request(url: urlText)?.url != url, !draft.request.host.isEmpty { urlText = url }
        }
        .onChange(of: draft.tab) { _, tab in
            if tab == .raw { draft.refreshRaw(phase: .request) } else { draft.rawError = nil }
            if tab == .query { draft.queryRows = BreakpointDraft.queryRows(draft.request.path) }
        }
        .sheet(isPresented: $importing) { CurlImportSheet { load($0) } }
        .alert("Request Timeout", isPresented: $customTimeout) {
            TextField("초", text: $customTimeoutText)
            Button("취소", role: .cancel) {}
            Button("확인") { if let s = TimeInterval(customTimeoutText), s > 0 { timeout = s } }
        } message: {
            Text("응답을 기다릴 시간(초)")
        }
    }

    // MARK: - 위

    private var topBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(Self.methods, id: \.self) { m in Button(m) { draft.request.method = m } }
            } label: {
                Text(verbatim: draft.request.method).font(.body.monospaced().bold()).foregroundStyle(FlowColors.method(draft.request.method))
            }
            .fixedSize()
            TextField("", text: $urlText, prompt: Text(verbatim: "Enter URL (Focus: ⌘K | Paste cURL Here | Send: ⌘↩)"))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .focused($urlFocused)
                .onSubmit(send)
                // ⌘K: URL 칸으로. 크기 0인 버튼은 단축키가 먹지 않아 칸 뒤에 투명하게 깐다.
                .background {
                    Button("") { urlFocused = true }
                        .keyboardShortcut("k")
                        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                }
            if sending != nil {
                Button("CANCEL") { sending?.cancel() }
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button("SEND (⌘↩)", action: send)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - 왼쪽 요청

    private var requestPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Request").font(.headline)
                Picker("", selection: $draft.tab) {
                    Text("Header").tag(BreakpointTab.header)
                    Text("Query").tag(BreakpointTab.query)
                    Text("Body").tag(BreakpointTab.body)
                    Text("Raw").tag(BreakpointTab.raw)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            Group {
                switch draft.tab {
                case .header: PairEditor(rows: $draft.request.headers, keyPrompt: "New Key…", valuePrompt: "New Value…")
                case .query:
                    PairEditor(rows: Binding(get: { draft.queryRows }, set: { draft.setQueryRows($0) }),
                               keyPrompt: "New Key…", valuePrompt: "New Value…")
                case .body: bodyEditor
                case .raw: rawEditor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
    }

    @ViewBuilder private var bodyEditor: some View {
        if let text = String(data: draft.request.body, encoding: .utf8) {
            CodeTextView(text: CodeTextView.base(text), wrap: model.settings.wrapLongLines, isEditable: true) { draft.request.body = Data($0.utf8) }
                .border(.separator)
        } else {
            ContentUnavailableView("바이너리 본문은 편집할 수 없습니다", systemImage: "doc",
                                   description: Text(verbatim: ByteSize.format(draft.request.body.count)))
        }
    }

    private var rawEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let e = draft.rawError { Text(e).foregroundStyle(.red) }
            let editable = String(data: draft.request.body, encoding: .utf8) != nil
            CodeTextView(text: HTTPMessageEditor.highlighted(draft.raw), wrap: model.settings.wrapLongLines, isEditable: editable) {
                draft.parseRaw($0, phase: .request)
            }
            .border(.separator)
        }
    }

    // MARK: - 오른쪽 응답

    @ViewBuilder private var responsePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Response").font(.headline)
                if let result {
                    Text(verbatim: "\(result.response.status)").bold()
                        .foregroundStyle(result.response.status >= 400 ? Color("StatusError") : result.response.status >= 300 ? Color("StatusRedirect") : Color("StatusSuccess"))
                    Text(verbatim: "\(result.milliseconds) ms · \(ByteSize.format(result.response.body.count))").foregroundStyle(.secondary)
                }
                if sending != nil { ProgressView().controlSize(.small) }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.top, 10)
            if let error {
                ContentUnavailableView("요청 실패", systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(maxHeight: .infinity)
            } else if let result {
                MessagePane(title: "", headers: result.response.headers, content: result.response.body, query: nil,
                            cookies: CookieParser.responseCookies(result.response.headers
                                .filter { $0.name.caseInsensitiveCompare("Set-Cookie") == .orderedSame }.map(\.value)),
                            flowID: result.id)
                    .id(result.id)
            } else {
                ContentUnavailableView("No Response Data", systemImage: "tray").frame(maxHeight: .infinity)
            }
        }
        // 짧은 내용이 가운데로 밀리지 않게 위에 붙인다.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 아래

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Menu("Template") {
                ForEach(ComposeTemplate.allCases, id: \.self) { t in Button(t.title) { load(t.request) } }
                Divider()
                Button("Import from cURL…") { importing = true }
            }
            .fixedSize()
            Menu("History") {
                if history.isEmpty { Text("보낸 요청이 없습니다") }
                ForEach(history) { h in
                    Button {
                        load(h.request)
                    } label: {
                        Text(verbatim: "\(h.request.method) \(h.request.url) — \(h.status.map { "\($0)" } ?? "실패") · \(h.date.formatted(date: .omitted, time: .standard))")
                    }
                }
            }
            .fixedSize()
            Menu {
                Picker("Request Timeout", selection: Binding(get: { Self.timeouts.contains(timeout) ? timeout : -1 }, set: { new in
                    if new == -1 { customTimeoutText = timeout.map { String(Int($0)) } ?? ""; customTimeout = true } else { timeout = new }
                })) {
                    Text("15초").tag(TimeInterval?.some(15))
                    Text("30초").tag(TimeInterval?.some(30))
                    Text("60초").tag(TimeInterval?.some(60))
                    Text(Self.timeouts.contains(timeout) ? "사용자 지정…" : "사용자 지정 (\(Int(timeout ?? 0))초)…").tag(TimeInterval?.some(-1))
                    Text("없음").tag(TimeInterval?.none)
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Request Timeout")
            Spacer()
            Text(timeout.map { "Timeout \(Int($0))s" } ?? "Timeout 없음").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 동작

    private static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    private static let timeouts: [TimeInterval?] = [15, 30, 60, nil]
    private static let emptyRequest = FlowRequest(method: "GET", scheme: "http", host: "", port: 80, path: "/", headers: [], body: Data())

    private func takeSeed() {
        guard let seed = model.composeSeed else { return }
        model.composeSeed = nil
        load(seed)
    }

    private func load(_ request: FlowRequest) {
        var d = BreakpointDraft(request: request)
        d.tab = draft.tab
        if d.tab == .raw { d.refreshRaw(phase: .request) }
        draft = d
        urlText = request.host.isEmpty ? "" : request.url
        result = nil
        error = nil
    }

    private func send() {
        guard sending == nil else { return }
        guard let client = model.composeClient else { error = String(localized: "프록시가 실행 중이 아닙니다"); return }
        var request = draft.request
        guard !request.host.isEmpty, let target = CurlParser.request(url: urlText) else {
            error = String(localized: "URL을 입력하세요 (http·https)")
            return
        }
        (request.scheme, request.host, request.port, request.path) = (target.scheme, target.host, target.port, target.path)
        request.method = request.method.trimmingCharacters(in: .whitespaces).uppercased()
        request.headers.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        error = nil
        let timeout = self.timeout
        sending = Task {
            let start = Date()
            var status: Int?
            do {
                let response = try await client.send(request, timeout: timeout)
                status = response.status
                result = ComposeResult(response: response, milliseconds: Int(Date().timeIntervalSince(start) * 1000))
            } catch {
                result = nil
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                self.error = cancelled ? String(localized: "취소됨") : error.localizedDescription
            }
            history = ComposeHistory.record(request, status: status, into: history)
            sending = nil
        }
    }
}

private struct ComposeResult {
    let id = FlowID()
    let response: FlowResponse
    let milliseconds: Int
}

// MARK: - 템플릿

private enum ComposeTemplate: CaseIterable {
    case empty, getQuery, postJSON, postForm, postMultipart

    var title: LocalizedStringKey {
        switch self {
        case .empty: "Empty Request"
        case .getQuery: "GET with Query"
        case .postJSON: "POST with JSON"
        case .postForm: "POST with Form"
        case .postMultipart: "POST with Multiparts"
        }
    }

    var request: FlowRequest {
        func make(_ method: String, _ url: String, _ contentType: String? = nil, _ body: String = "") -> FlowRequest {
            CurlParser.request(url: url, method: method, headers: contentType.map { [HTTPHeader(name: "Content-Type", value: $0)] } ?? [],
                               body: Data(body.utf8))!
        }
        switch self {
        case .empty:
            return FlowRequest(method: "GET", scheme: "http", host: "", port: 80, path: "/", headers: [], body: Data())
        case .getQuery:
            return make("GET", "https://httpbin.org/get?name=eyeproxy&page=1")
        case .postJSON:
            return make("POST", "https://httpbin.org/post", "application/json", "{\n  \"name\": \"eyeproxy\",\n  \"count\": 1\n}")
        case .postForm:
            return make("POST", "https://httpbin.org/post", "application/x-www-form-urlencoded", "name=eyeproxy&count=1")
        case .postMultipart:
            let boundary = "EyeProxyBoundary" + UUID().uuidString.replacing("-", with: "").prefix(16)
            let body = "--\(boundary)\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\neyeproxy\r\n"
                + "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"hello.txt\"\r\nContent-Type: text/plain\r\n\r\nhello\r\n"
                + "--\(boundary)--\r\n"
            return make("POST", "https://httpbin.org/post", "multipart/form-data; boundary=\(boundary)", body)
        }
    }
}

private struct CurlImportSheet: View {
    let onImport: (FlowRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import from cURL").font(.headline)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minWidth: 520, minHeight: 220)
                .border(.separator)
            if failed { Text("cURL 명령을 읽지 못했습니다").foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    guard let r = CurlParser.parse(text) else { failed = true; return }
                    onImport(r)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }
}

// MARK: - History

/// 보낸 요청 기록(응답 본문은 저장하지 않는다). 최신이 앞, 최대 100개.
struct ComposeHistoryEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let request: FlowRequest
    /// nil = 실패·취소
    let status: Int?
}

@MainActor enum ComposeHistory {
    static let url = AppModel.supportDirectory.appending(path: "compose-history.json")
    static let limit = 100

    static func load() -> [ComposeHistoryEntry] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([ComposeHistoryEntry].self, from: $0) } ?? []
    }

    static func record(_ request: FlowRequest, status: Int?, into history: [ComposeHistoryEntry]) -> [ComposeHistoryEntry] {
        let updated = Array(([ComposeHistoryEntry(date: Date(), request: request, status: status)] + history).prefix(limit))
        try? JSONEncoder().encode(updated).write(to: url, options: .atomic)
        return updated
    }
}
