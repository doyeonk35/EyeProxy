import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

/// 멈춘 요청/응답 창(스펙 §5.1): 왼쪽 대기 목록, 오른쪽 편집기. 편집 중인 값은 건별로 `drafts`에 둔다.
struct BreakpointWindow: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var drafts: [UUID: BreakpointDraft] = [:]

    var body: some View {
        let pending = model.breakpoints.pending
        HSplitView {
            List(pending, selection: $selection) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: item.request.method).font(.caption.monospaced().bold())
                        Text(item.phase == .request ? "요청" : "응답")
                            .font(.caption).padding(.horizontal, 5)
                            .background(item.phase == .request ? Color.blue.opacity(0.2) : Color.green.opacity(0.2), in: Capsule())
                    }
                    Text(verbatim: item.request.url).lineLimit(1).truncationMode(.middle)
                }
                .padding(.vertical, 2)
            }
            .frame(minWidth: 220, idealWidth: 300, maxWidth: 420)
            Group {
                if let item = pending.first(where: { $0.id == selection }) {
                    BreakpointEditor(item: item, draft: Binding(
                        get: { drafts[item.id] ?? BreakpointDraft(item) },
                        set: { drafts[item.id] = $0 }
                    )) { model.breakpoints.resolve(item.id, with: $0) }
                    .id(item.id)
                } else {
                    ContentUnavailableView(pending.isEmpty ? "멈춘 요청이 없습니다" : "왼쪽에서 항목을 고르세요",
                                           systemImage: "pause.circle",
                                           description: Text("Breakpoint 규칙에 맞는 요청·응답이 여기서 멈춥니다"))
                }
            }
            .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 560)
        .onAppear { keepSelection(pending.map(\.id)) }
        .onChange(of: pending.map(\.id)) { _, ids in keepSelection(ids) }
    }

    /// 풀린 건의 초안을 버리고, 선택이 없으면 첫 건을 고른다.
    private func keepSelection(_ ids: [UUID]) {
        drafts = drafts.filter { ids.contains($0.key) }
        if selection == nil || !ids.contains(selection!) { selection = ids.first }
    }
}

enum BreakpointTab: Hashable { case header, query, body, raw }

/// 한 건의 편집 상태(Breakpoint·Compose 요청 편집). `queryRows`는 빈 행을 잃지 않도록 경로와 따로 둔다(바뀌면 경로에 다시 쓴다).
struct BreakpointDraft {
    var request: FlowRequest
    var response: FlowResponse?
    var queryRows: [HTTPHeader]
    var tab = BreakpointTab.header
    var raw = ""
    var rawError: String?

    init(_ item: PausedItem) {
        request = item.request
        response = item.response
        queryRows = Self.queryRows(item.request.path)
    }

    init(request: FlowRequest) {
        self.request = request
        queryRows = Self.queryRows(request.path)
    }

    static func split(_ path: String) -> (path: String, query: String?) {
        guard let q = path.firstIndex(of: "?") else { return (path, nil) }
        return (String(path[..<q]), String(path[path.index(after: q)...]))
    }

    static func queryRows(_ path: String) -> [HTTPHeader] {
        var c = URLComponents()
        c.percentEncodedQuery = split(path).query
        return (c.queryItems ?? []).map { HTTPHeader(name: $0.name, value: $0.value ?? "") }
    }

    mutating func setQueryRows(_ rows: [HTTPHeader]) {
        queryRows = rows
        var c = URLComponents()
        let items = rows.filter { !$0.name.isEmpty }
        c.queryItems = items.isEmpty ? nil : items.map { URLQueryItem(name: $0.name, value: $0.value) }
        request.path = Self.split(request.path).path + (c.percentEncodedQuery.map { "?" + $0 } ?? "")
    }

    /// Raw 탭에 들어갈 때·템플릿·되돌리기 뒤에 원문을 다시 만든다.
    mutating func refreshRaw(phase: BreakpointPhase) {
        let data = phase == .request ? HTTPMessageFile.serialize(request) : response.map(HTTPMessageFile.serialize) ?? Data()
        raw = String(decoding: data, as: UTF8.self)
        rawError = nil
    }

    mutating func parseRaw(_ text: String, phase: BreakpointPhase) {
        raw = text
        do {
            if phase == .request {
                request = try HTTPMessageFile.parseRequest(Data(text.utf8), base: request)
                queryRows = Self.queryRows(request.path)
            } else {
                response = try HTTPMessageFile.parse(Data(text.utf8), fileURLBase: nil)
            }
            rawError = nil
        } catch HTTPMessageFileError.fileNotFound(let path) {
            rawError = String(localized: "파일을 찾을 수 없습니다: \(path)")
        } catch {
            rawError = phase == .request
                ? String(localized: "첫 줄은 요청줄이어야 합니다 (예: GET /path HTTP/1.1)")
                : String(localized: "첫 줄은 상태줄이어야 합니다 (예: HTTP/1.1 200 OK)")
        }
    }
}

struct BreakpointEditor: View {
    let item: PausedItem
    @Binding var draft: BreakpointDraft
    let resolve: (BreakpointResolution) -> Void

    @Environment(AppModel.self) private var model
    @State private var naming = false
    @State private var templateName = ""

    private var phase: BreakpointPhase { item.phase }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Picker("", selection: $draft.tab) {
                Text("Header").tag(BreakpointTab.header)
                if phase == .request { Text("Query").tag(BreakpointTab.query) }
                Text("Body").tag(BreakpointTab.body)
                Text("Raw").tag(BreakpointTab.raw)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Group {
                switch draft.tab {
                case .header:
                    PairEditor(rows: phase == .request ? $draft.request.headers : responseBinding(\.headers),
                               keyPrompt: "New Key…", valuePrompt: "New Value…")
                case .query:
                    PairEditor(rows: Binding(get: { draft.queryRows }, set: { draft.setQueryRows($0) }),
                               keyPrompt: "New Key…", valuePrompt: "New Value…")
                case .body: bodyEditor
                case .raw: rawEditor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            buttons
        }
        .padding()
        .onChange(of: draft.tab) { _, tab in
            if tab == .raw { draft.refreshRaw(phase: phase) } else { draft.rawError = nil }
        }
        .alert("Save as Template", isPresented: $naming) {
            TextField("템플릿 이름", text: $templateName)
            Button("취소", role: .cancel) {}
            Button("저장", action: saveTemplate).disabled(templateName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - 위쪽

    @ViewBuilder private var header: some View {
        HStack(spacing: 6) {
            Text(phase == .request ? "요청에서 멈춤" : "응답에서 멈춤").font(.headline)
            Text(verbatim: "· \(item.ruleName)").foregroundStyle(.secondary)
        }
        if phase == .request {
            HStack(spacing: 6) {
                TextField("Method", text: $draft.request.method).frame(width: 90)
                Picker("", selection: $draft.request.scheme) {
                    Text(verbatim: "http").tag("http")
                    Text(verbatim: "https").tag("https")
                }
                .labelsHidden()
                .fixedSize()
                TextField("Host", text: $draft.request.host)
                // 문자열 바인딩: 값 형식 칸은 포커스를 잃어야 반영돼 ⌘↩가 이전 값을 보낼 수 있다.
                TextField("Port", text: Binding(get: { String(draft.request.port) }, set: { t in
                    if let p = Int(t.filter(\.isNumber)), (1...65535).contains(p) { draft.request.port = p }
                }))
                .frame(width: 64)
                TextField("Path", text: Binding(
                    get: { BreakpointDraft.split(draft.request.path).path },
                    set: { p in
                        let q = BreakpointDraft.split(draft.request.path).query
                        draft.request.path = (p.hasPrefix("/") ? p : "/" + p) + (q.map { "?" + $0 } ?? "")
                    }))
            }
            .textFieldStyle(.roundedBorder)
        } else {
            Text(verbatim: "\(item.request.method) \(item.request.url)").lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            HStack {
                Text("Status Code")
                TextField("", text: Binding(get: { String(draft.response?.status ?? 0) }, set: { t in
                    guard let s = Int(t.filter(\.isNumber)), (100...999).contains(s), s != draft.response?.status else { return }
                    draft.response?.status = s
                    draft.response?.reason = ""   // 전송 때 표준 문구
                }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }
        }
    }

    private func responseBinding<V>(_ key: WritableKeyPath<FlowResponse, V>) -> Binding<V> {
        Binding(get: { draft.response![keyPath: key] }, set: { draft.response![keyPath: key] = $0 })
    }

    private var bodyData: Data { phase == .request ? draft.request.body : draft.response?.body ?? Data() }

    @ViewBuilder private var bodyEditor: some View {
        if let text = String(data: bodyData, encoding: .utf8) {
            CodeTextView(text: CodeTextView.base(text), wrap: model.settings.wrapLongLines, isEditable: true) { new in
                if phase == .request { draft.request.body = Data(new.utf8) } else { draft.response?.body = Data(new.utf8) }
            }
            .border(.separator)
        } else {
            ContentUnavailableView("바이너리 본문은 편집할 수 없습니다", systemImage: "doc",
                                   description: Text(verbatim: ByteSize.format(bodyData.count)))
        }
    }

    private var rawEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let error = draft.rawError { Text(error).foregroundStyle(.red) }
                Spacer()
                templatesMenu
            }
            // 바이너리 본문은 문자열로 바꾸면 깨지므로 읽기만.
            let editable = String(data: bodyData, encoding: .utf8) != nil
            CodeTextView(text: HTTPMessageEditor.highlighted(draft.raw), wrap: model.settings.wrapLongLines, isEditable: editable) {
                draft.parseRaw($0, phase: phase)
            }
            .border(.separator)
            if !editable { Text("바이너리 본문이 있어 Raw는 읽기 전용입니다").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var templatesMenu: some View {
        Menu("Templates") {
            let list = model.rules.breakpointTemplates.filter { $0.kind == phase }
            if list.isEmpty { Text("저장된 템플릿이 없습니다") }
            ForEach(list) { t in
                Button(t.name) {
                    if phase == .request {
                        draft.request = t.apply(to: draft.request)
                        draft.queryRows = BreakpointDraft.queryRows(draft.request.path)
                    } else if let r = draft.response {
                        draft.response = t.apply(to: r)
                    }
                    draft.refreshRaw(phase: phase)
                }
            }
            Divider()
            Button("Save as Template…") {
                templateName = ""
                naming = true
            }
            Button("Reset to the Original") {
                var fresh = BreakpointDraft(item)
                fresh.tab = .raw
                fresh.refreshRaw(phase: phase)
                draft = fresh
            }
        }
        .fixedSize()
    }

    private func saveTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespaces)
        let t = phase == .request
            ? BreakpointTemplate(name: name, kind: .request, method: draft.request.method, url: draft.request.url, headers: draft.request.headers)
            : BreakpointTemplate(name: name, kind: .response, status: draft.response?.status, headers: draft.response?.headers ?? [])
        model.rules.breakpointTemplates.append(t)
    }

    // MARK: - 아래 버튼

    private var buttons: some View {
        HStack {
            Button("Continue Original") { resolve(.continueOriginal) }
                .keyboardShortcut(".", modifiers: .command)
                .help("원래 요청/응답을 그대로 보냅니다 (⌘.)")
            Menu("Drop Connection") {
                Button("Abort: 429") { resolve(.abort(status: 429)) }
                Button("Abort: 503") { resolve(.abort(status: 503)) }
            } primaryAction: {
                resolve(.drop)
            }
            .fixedSize()
            .help("연결을 끊습니다 (⌘\\). ▾에서 429/503 응답으로 중단")
            // Menu의 primaryAction에는 단축키를 걸 수 없어 숨은 버튼으로 둔다.
            Button("Drop Connection") { resolve(.drop) }
                .keyboardShortcut("\\", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
            Spacer()
            Button("Apply & Execute") { resolve(apply()) }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(draft.rawError != nil)
        }
    }

    /// 이름 없는 헤더 행(아직 입력 중)은 보내지 않는다.
    private func apply() -> BreakpointResolution {
        if phase == .request {
            var r = draft.request
            r.headers.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            r.method = r.method.trimmingCharacters(in: .whitespaces).uppercased()
            if r.method.isEmpty { r.method = item.request.method }
            return .executeRequest(r)
        }
        guard var r = draft.response else { return .continueOriginal }
        r.headers.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        return .executeResponse(r)
    }
}

/// 편집 가능한 이름/값 표(Header·Query·템플릿 헤더). 마지막 줄 + 로 행을 더한다.
struct PairEditor: View {
    @Binding var rows: [HTTPHeader]
    let keyPrompt: LocalizedStringKey
    let valuePrompt: LocalizedStringKey

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        TextField("", text: cell(i, \.name), prompt: Text(keyPrompt)).frame(width: 200)
                        TextField("", text: cell(i, \.value), prompt: Text(valuePrompt))
                        Button { if i < rows.count { rows.remove(at: i) } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("행 삭제")
                    }
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            HStack {
                Button { rows.append(HTTPHeader(name: "", value: "")) } label: { Label("Add", systemImage: "plus") }
                Spacer()
            }
            .padding(.top, 6)
        }
    }

    /// 행을 지운 직후 이전 인덱스로 그려질 수 있어 범위를 확인한다.
    private func cell(_ i: Int, _ key: WritableKeyPath<HTTPHeader, String>) -> Binding<String> {
        Binding(get: { i < rows.count ? rows[i][keyPath: key] : "" }, set: { if i < rows.count { rows[i][keyPath: key] = $0 } })
    }
}
