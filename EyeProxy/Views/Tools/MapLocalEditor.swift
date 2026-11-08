import AppKit
import EyeProxyCore
import EyeProxyKit
import SwiftUI

struct MapLocalWindow: View {
    @Environment(AppModel.self) private var model
    @State private var folderRejected = false

    var body: some View {
        ToolWindow(
            windowID: "tool-map-local", title: "Map Local",
            description: "Map a Response with a Local File or Directory. Support Status Code, Headers and Body.",
            toolSwitch: \.mapLocal, file: .mapLocal, newRule: { MapLocalRule() },
            editorStyle: .window(id: "map-local-editor"),
            helpURL: URL(string: "https://docs.proxyman.com/advanced-features/map-local"),
            prefill: { rule, pending in
                model.editorMessages[rule.id] = MapLocalMessage.text(for: model.session.flow(pending.flowID)?.response)
            }
        ) {
            Menu("Default Local File Folder") {
                Button("Choose Folder…") {
                    if let url = MapLocalMessage.pick(directory: true) { folderRejected = !model.setMapLocalFolder(url) }
                }
                Button("Use Default Folder") { model.setMapLocalFolder(nil) }
                Button("Reveal in Finder") {
                    let dir = model.rules.mapLocalDirectory
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
            }
        } editor: { _, _, _ in
            EmptyView()
        } columns: {
            ruleColumn("Method") { (r: MapLocalRule) in Text(verbatim: RuleText.method(r.match)) }
            ruleColumn("Matching Rule") { (r: MapLocalRule) in MatchingRuleCell(match: r.match) }
            ruleColumn("Map from") { (r: MapLocalRule) in
                Text(verbatim: MapLocalMessage.source(r)).lineLimit(1).truncationMode(.middle)
            }
        }
        .alert("이 폴더는 쓸 수 없습니다", isPresented: $folderRejected) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("Proxyman 폴더이거나 그 폴더를 포함합니다. 다른 폴더를 고르세요.")
        }
    }
}

extension AppModel {
    /// More ▸ Default Local File Folder. nil = 기본 폴더. Proxyman 폴더(그 안·조상 포함)는 거절하고 false.
    @discardableResult func setMapLocalFolder(_ url: URL?) -> Bool {
        if let url, !ProxymanImporter.isSafeWriteTarget(url) { return false }
        settings.mapLocalDefaultFolder = url?.path
        rules.mapLocalFolderOverride = url
        return true
    }
}

@MainActor enum MapLocalMessage {
    static let defaultText = "HTTP/1.1 200 OK\nContent-Type: application/json; charset=utf-8\n\n{\n  \"status\": \"ok\"\n}"

    /// 우클릭 ▸ Map Local…: 받은 응답을 압축 푼 HTTP 메시지로. 응답이 없으면 기본 메시지.
    /// ponytail: UTF-8이 아닌 본문은 깨져 들어간다. 바이너리 응답이 필요하면 Select Local File로 고른다.
    static func text(for response: FlowResponse?) -> String {
        guard var r = response else { return defaultText }
        let encoding = r.headers.first { $0.name.caseInsensitiveCompare("Content-Encoding") == .orderedSame }?.value
        if encoding != nil, let plain = BodyDecoder.decompressed(body: r.body, contentEncoding: encoding) {
            r.body = plain
            r.headers.removeAll { $0.name.caseInsensitiveCompare("Content-Encoding") == .orderedSame }
        }
        r.headers.removeAll { $0.name.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame }
        return String(decoding: HTTPMessageFile.serialize(r), as: UTF8.self)
    }

    static func source(_ r: MapLocalRule) -> String {
        if r.useDirectory { return "Directory: \(r.directoryPath ?? "")" }
        return r.localFile.map { "File: \($0.path)" } ?? ""
    }

    static func pick(directory: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        panel.canCreateDirectories = directory
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 편집기로 열어 다시 써도 되는 파일이면 그 내용. 폴더 안·Proxyman 밖·UTF-8일 때만(아니면 읽기 전용 미리보기).
    static func editableText(_ path: String, _ dir: URL) -> String? {
        guard isInside(path, dir), ProxymanImporter.isSafeWriteTarget(URL(fileURLWithPath: path)) else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    static func isInside(_ path: String, _ dir: URL) -> Bool {
        let d = dir.standardizedFileURL.path
        return URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(d.hasSuffix("/") ? d : d + "/")
    }

    /// `<host>_<ruleID>.http`. 경로 문자가 섞이지 않게 영숫자·`.`·`-` 밖은 `_`로.
    static func fileName(_ r: MapLocalRule) -> String {
        // hostPattern은 http:// 규칙에 nil이라 scheme을 바꿔 호스트만 뽑는다.
        var https = r.match
        if https.url.lowercased().hasPrefix("http://") { https.url = "https://" + https.url.dropFirst(7) }
        return "\(clean(https.hostPattern ?? "local"))_\(clean(r.id)).http"
    }

    private static func clean(_ s: String) -> String {
        String(s.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") ? $0 : "_" })
    }

    /// 이 규칙이 만든 응답 파일인가(`fileName`처럼 이름에 규칙 id). 아니면(복제한 규칙·가져온 파일) 제자리에 덮어쓰지 않는다.
    static func owns(_ path: String, _ r: MapLocalRule) -> Bool {
        URL(fileURLWithPath: path).lastPathComponent.hasSuffix("_\(clean(r.id)).http")
    }

    /// 고른 파일 미리보기(읽기 전용).
    static func preview(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int else {
            return String(localized: "(파일을 찾을 수 없습니다)")
        }
        guard size <= 1_000_000, let data = try? Data(contentsOf: url) else { return String(localized: "(파일이 커서 미리보기를 생략합니다: \(ByteSize.format(size)))") }
        return String(data: data, encoding: .utf8) ?? String(localized: "(바이너리 파일: \(ByteSize.format(size)))")
    }

    /// 고른 파일을 편집 가능한 HTTP 메시지로. HTTP 메시지 파일이면 원문, 아니면 200 응답으로 감싼다.
    static func converted(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if ["http", "json"].contains(url.pathExtension.lowercased()), HTTPMessageEditor.hasStatusLine(String(decoding: data.prefix(200), as: UTF8.self)) {
            return String(decoding: data, as: UTF8.self)
        }
        return (try? HTTPMessageFile.response(forLocalFile: url)).map { String(decoding: HTTPMessageFile.serialize($0), as: UTF8.self) }
    }
}

/// "Map Local Editor: <이름>" 창(스펙 §6.3). 새 규칙은 Save(⌘S) 때 트리에 들어간다.
/// 응답 파일은 `rules.mapLocalDirectory` 안에만 쓴다. 고른 외부 파일은 그대로 참조하고 읽기 전용으로 보인다.
struct MapLocalEditor: View {
    let ruleID: String

    @Environment(AppModel.self) private var model
    @State private var rule: MapLocalRule?
    /// 마지막 저장(또는 처음 연) 상태. 이것과 다르면 저장 안 된 변경.
    @State private var baseline: MapLocalRule?
    @State private var message = ""
    @State private var messageDirty = false
    /// 외부 파일을 고른 상태면 그 미리보기(읽기 전용).
    @State private var external: String?
    @State private var error: String?
    @State private var missing = false
    /// Proxyman 폴더에 쓰려다 막힌 경로(알림).
    @State private var blocked: String?
    /// 규칙이 트리에 있었다(열 때 있었거나 저장했다). 저장 때 없으면 그사이 삭제된 것.
    @State private var inTree = false

    private var dir: URL { model.rules.mapLocalDirectory }
    private var isDirty: Bool { rule != baseline || messageDirty }

    var body: some View {
        Group {
            if let rule = Binding($rule) {
                content(rule)
            } else if missing {
                Text("규칙을 찾을 수 없습니다").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .navigationTitle("Map Local Editor: " + (rule?.name ?? ""))
        .background(WindowCloseGuard(isDirty: { isDirty }, save: save))
        .onAppear(perform: load)
        .alert("저장할 수 없습니다", isPresented: Binding(get: { blocked != nil }, set: { if !$0 { blocked = nil } })) {
            Button("확인", role: .cancel) { blocked = nil }
        } message: {
            Text(blocked ?? "")
        }
    }

    private func content(_ rule: Binding<MapLocalRule>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Matching Rule") {
                Form {
                    MatchRuleFields(name: rule.name, match: rule.match)
                    Text("Advanced Settings:").foregroundStyle(.secondary).padding(.top, 4)
                    Picker("Delay Response", selection: rule.delaySeconds) {
                        ForEach(MapLocalRule.delayPresets, id: \.self) { s in
                            if let s { Text("\(s)초").tag(s as Int?) } else { Text("No Delay").tag(s) }
                        }
                    }
                    .fixedSize()
                }
                .formStyle(.columns)
                .padding(6)
            }
            GroupBox("Map To") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: rule.useDirectory) {
                        Text("Local File").tag(false)
                        Text("Local Directory").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    if rule.wrappedValue.useDirectory { directoryPane(rule) } else { filePane(rule) }
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            bottomBar(rule)
        }
        .padding()
    }

    @ViewBuilder private func filePane(_ rule: Binding<MapLocalRule>) -> some View {
        Toggle("Enable Local File", isOn: rule.useLocalFile).toggleStyle(.checkbox)
        Text(verbatim: "File: " + (rule.wrappedValue.localFile?.path ?? String(localized: "(저장하면 만들어집니다)")))
            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        if let external {
            HStack {
                Text("선택한 파일을 그대로 응답으로 씁니다").foregroundStyle(.secondary)
                Spacer()
                Button("HTTP 메시지로 편집", action: convertExternal)
            }
            CodeTextView(text: CodeTextView.base(external), wrap: model.settings.wrapLongLines)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(.separator)
        } else {
            // 입력으로 바뀐 것만 수정됨으로 본다(불러오기·변환은 `message`에 바로 쓴다).
            HTTPMessageEditor(message: Binding(get: { message }, set: { message = $0; messageDirty = true }),
                              isSaved: !messageDirty && rule.wrappedValue.localFile != nil)
        }
    }

    @ViewBuilder private func directoryPane(_ rule: Binding<MapLocalRule>) -> some View {
        HStack {
            Text(verbatim: "Directory: " + (rule.wrappedValue.directoryPath ?? ""))
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Button("Choose Folder…") {
                if let url = MapLocalMessage.pick(directory: true) { rule.wrappedValue.directoryPath = url.path }
            }
        }
        Text("일치한 부분 뒤의 경로를 이 폴더 아래에서 찾습니다. 파일이 없으면 실제 서버 응답을 씁니다.")
            .font(.caption).foregroundStyle(.secondary)
        Spacer()
    }

    private func bottomBar(_ rule: Binding<MapLocalRule>) -> some View {
        HStack(spacing: 8) {
            Button("Select Local File", action: selectFile).disabled(rule.wrappedValue.useDirectory)
            Text("HTTP 메시지 형식이나 로컬 파일을 받습니다").foregroundStyle(.secondary)
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                .help("HTTP 메시지는 상태줄, 헤더, 빈 줄, 본문 순서입니다. 다른 파일(JSON·이미지 등)을 고르면 상태 200으로 그 파일을 본문으로 씁니다.")
            if let error { Text(error).foregroundStyle(.red).lineLimit(2) }
            Spacer()
            Menu {
                Button("Reveal in Finder") {
                    if let path = rule.wrappedValue.localFile?.path { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                }
                .disabled(rule.wrappedValue.localFile == nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .fixedSize()
            Button("Save") { _ = save() }
                .keyboardShortcut("s")
                .help("Save (⌘S)")
        }
    }

    // MARK: - 불러오기·저장

    private func load() {
        guard rule == nil else { return }
        let existing = model.rules.tree(.mapLocal).node(ruleID)?.rule
        guard let r = (model.editorDrafts.removeValue(forKey: ruleID) as? MapLocalRule) ?? existing else {
            missing = true
            return
        }
        rule = r
        baseline = r
        inTree = existing != nil
        if let prefilled = model.editorMessages.removeValue(forKey: ruleID) {
            message = prefilled
            messageDirty = true
        } else if let path = r.localFile?.path {
            if let text = MapLocalMessage.editableText(path, dir) { message = text } else { external = MapLocalMessage.preview(path) }
            messageDirty = false
        } else {
            message = MapLocalMessage.defaultText
            messageDirty = false
        }
    }

    private func selectFile() {
        guard let url = MapLocalMessage.pick(directory: false) else { return }
        rule?.localFile = LocalFileRef(name: url.lastPathComponent, path: url.path)
        if let text = MapLocalMessage.editableText(url.path, dir) {
            external = nil
            message = text
        } else {
            external = MapLocalMessage.preview(url.path)
        }
        messageDirty = false
    }

    private func convertExternal() {
        guard let path = rule?.localFile?.path else { return }
        // 폴더 안 파일이 사라졌으면 기본 메시지로 다시 만든다.
        guard let text = MapLocalMessage.converted(path) ?? (FileManager.default.fileExists(atPath: path) ? nil : MapLocalMessage.defaultText) else {
            error = String(localized: "파일을 읽지 못했습니다")
            return
        }
        external = nil
        message = text
        messageDirty = true
        // 원본(바깥 파일·폴더 안 바이너리)은 덮어쓰지 않는다. 저장하면 폴더 안에 새 파일을 만들어 가리킨다.
        rule?.localFile = nil
    }

    /// 응답 파일(파일 모드·편집 가능일 때)과 규칙을 저장한다. 실패하면 false.
    @discardableResult private func save() -> Bool {
        guard var r = rule else { return false }
        // 지금 트리의 규칙에 합친다: 편집기에서 바꾸지 않은 Enabled·이름은 표에서 그사이 바꾼 값을 따른다(M3).
        let live = model.rules.tree(.mapLocal).node(r.id)?.rule
        if let live, let baseline {
            if r.isEnabled == baseline.isEnabled { r.isEnabled = live.isEnabled }
            if r.name == baseline.name { r.name = live.name }
        } else if live == nil, inTree, !confirmReAdd(r.name) {
            return false
        }
        if r.match.url.isEmpty || r.match.validationError != nil {
            error = r.match.validationError ?? String(localized: "URL을 입력하세요")
            return false
        }
        if r.useDirectory, r.directoryPath == nil {
            error = String(localized: "폴더를 고르세요")
            return false
        }
        if !r.useDirectory, external == nil {
            let current = r.localFile?.path
            // 이 규칙의 파일만 제자리에 덮어쓴다. 복제한 규칙은 원본 규칙의 파일을 가리키므로 새 파일을 만든다(I4).
            let inside = current.map {
                MapLocalMessage.isInside($0, dir) && MapLocalMessage.owns($0, r) && ProxymanImporter.isSafeWriteTarget(URL(fileURLWithPath: $0))
            } ?? false
            if messageDirty || !inside {
                // 내 파일은 덮어쓰고, 없거나 남의(바깥·다른 규칙) 파일이면 폴더 안에 새로 만들어 가리킨다.
                let target = inside ? URL(fileURLWithPath: current!) : dir.appendingPathComponent(MapLocalMessage.fileName(r))
                // 폴더 설정과 무관하게 Proxyman 폴더에는 절대 쓰지 않는다.
                guard ProxymanImporter.isSafeWriteTarget(target) else {
                    blocked = String(localized: "Proxyman 폴더에는 쓰지 않습니다: \(target.path)")
                    return false
                }
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try Data(message.utf8).write(to: target, options: .atomic)
                } catch {
                    self.error = String(localized: "응답 파일을 저장하지 못했습니다: \(error.localizedDescription)")
                    return false
                }
                r.localFile = LocalFileRef(name: target.lastPathComponent, path: target.path)
            }
        }
        var tree = model.rules.tree(.mapLocal)
        if tree.node(r.id) != nil { tree.update(r.id) { $0 = .rule(r) } } else { tree.insert([.rule(r)], into: nil) }
        let before = model.rules.revision
        model.rules.set(tree, for: .mapLocal)
        // 규칙 파일 저장 실패는 RuleStore가 경고로 알린다. 편집 상태는 저장 안 됨으로 남긴다.
        guard model.rules.revision != before else {
            error = String(localized: "규칙을 저장하지 못했습니다")
            return false
        }
        rule = r
        baseline = r
        inTree = true
        error = nil
        messageDirty = false
        return true
    }

    /// 편집 중 표에서 지운 규칙을 저장하려 할 때 다시 추가할지 묻는다.
    private func confirmReAdd(_ name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "규칙 \"\(name)\"은 편집하는 동안 삭제되었습니다")
        alert.informativeText = String(localized: "저장하면 규칙을 다시 추가합니다.")
        alert.addButton(withTitle: String(localized: "다시 추가"))
        alert.addButton(withTitle: String(localized: "취소"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// 창 닫기 전에 저장 안 된 변경을 묻는다. SwiftUI 창 delegate 앞에 끼어들고 나머지 메시지는 원래 delegate로 넘긴다.
struct WindowCloseGuard: NSViewRepresentable {
    let isDirty: () -> Bool
    let save: () -> Bool

    final class Hook: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        var isDirty: () -> Bool = { false }
        var save: () -> Bool = { true }
        nonisolated(unsafe) weak var original: (any NSWindowDelegate)?

        func install(on window: NSWindow) {
            guard window.delegate !== self else { return }
            original = window.delegate
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard isDirty() else { return original?.windowShouldClose?(sender) ?? true }
            let alert = NSAlert()
            alert.messageText = String(localized: "저장하지 않은 변경 사항이 있습니다")
            alert.addButton(withTitle: String(localized: "저장"))
            alert.addButton(withTitle: String(localized: "저장 안 함"))
            alert.addButton(withTitle: String(localized: "취소"))
            alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
                guard let self, let sender else { return }
                switch response {
                case .alertFirstButtonReturn: if self.save() { sender.close() }
                case .alertSecondButtonReturn: sender.close()
                default: break
                }
            }
            return false
        }

        override nonisolated func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
        }

        override nonisolated func forwardingTarget(for aSelector: Selector!) -> Any? {
            original?.responds(to: aSelector) == true ? original : nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> Hook {
        let view = Hook()
        let coordinator = context.coordinator
        view.onWindow = { coordinator.install(on: $0) }
        return view
    }

    func updateNSView(_ view: Hook, context: Context) {
        context.coordinator.isDirty = isDirty
        context.coordinator.save = save
    }
}
