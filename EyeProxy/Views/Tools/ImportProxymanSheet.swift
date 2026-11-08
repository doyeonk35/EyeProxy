import AppKit
import EyeProxyKit
import SwiftUI
import UniformTypeIdentifiers

extension ProxymanImporter {
    /// From Proxyman…이 읽는 폴더. DEBUG 빌드에서만 `EYEPROXY_PROXYMAN_DIR`로 바꿀 수 있다(실제 Proxyman 폴더를 건드리지 않고 시트를 확인하려고).
    static var appDirectory: URL {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["EYEPROXY_PROXYMAN_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return defaultDirectory
    }
}

/// Proxyman 가져오기 확인 시트(스펙 §5.9). `tool`이 nil이면 Proxyman 폴더 전체(Tools ▸ Import Settings ▸ From Proxyman…),
/// 있으면 도구 창 More ▸ Import…로 고른 파일 하나를 그 도구로만 읽는다.
struct ImportProxymanSheet: View {
    var file: URL?
    var tool: ImportTool?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var preview: ProxymanImportPreview?
    @State private var failure: String?
    @State private var selection = ImportSelection()
    @State private var result: ImportResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(file == nil ? "Proxyman에서 가져오기" : "규칙 가져오기").font(.headline)
            if let file {
                Text(verbatim: (file.path as NSString).abbreviatingWithTildeInPath).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                HStack { Spacer(); Button("닫기") { dismiss() }.keyboardShortcut(.defaultAction) }
            } else if let result {
                summary(result)
                HStack { Spacer(); Button("닫기") { dismiss() }.keyboardShortcut(.defaultAction) }
            } else if let preview {
                choices(preview)
                HStack {
                    Spacer()
                    Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("가져오기") { result = ProxymanImporter.apply(preview, selection: selection, into: model.rules, settings: model.settings,
                                                                         proxymanDirectory: ProxymanImporter.appDirectory) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!rows(preview).contains { $0.count > 0 && selection[keyPath: $0.key] }
                                  && !(showsSSL(preview) && selection.sslHosts))
                }
            }
        }
        .padding(20)
        .frame(width: 480, alignment: .leading)
        .onAppear(perform: load)
    }

    // MARK: - 미리보기

    private struct Row {
        let title: String
        let count: Int
        let graphQL: Int
        let key: WritableKeyPath<ImportSelection, Bool>
        let tool: ImportTool
    }

    private func allRows(_ p: ProxymanImportPreview) -> [Row] {
        [
            Row(title: "Map Local", count: ruleCount(p.mapLocal), graphQL: graphQLCount(p.mapLocal), key: \.mapLocal, tool: .mapLocal),
            Row(title: "Map Remote", count: ruleCount(p.mapRemote), graphQL: graphQLCount(p.mapRemote), key: \.mapRemote, tool: .mapRemote),
            Row(title: "Breakpoint", count: ruleCount(p.breakpoint), graphQL: graphQLCount(p.breakpoint), key: \.breakpoint, tool: .breakpoint),
            Row(title: "Block List", count: ruleCount(p.block), graphQL: graphQLCount(p.block), key: \.block, tool: .block),
            Row(title: "Allow List", count: ruleCount(p.allow), graphQL: graphQLCount(p.allow), key: \.allow, tool: .allow),
            Row(title: "Network Conditions", count: p.networkConditions.count, graphQL: 0, key: \.networkConditions, tool: .networkConditions),
        ]
    }

    /// 도구 하나로 가져오면 그 도구 줄만.
    private func rows(_ p: ProxymanImportPreview) -> [Row] {
        allRows(p).filter { tool == nil || $0.tool == tool }
    }

    private func showsSSL(_ p: ProxymanImportPreview) -> Bool { file == nil && !p.sslHosts.isEmpty }

    @ViewBuilder private func choices(_ p: ProxymanImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows(p), id: \.title) { row in
                Toggle(isOn: $selection[dynamicMember: row.key]) { Text(verbatim: "\(row.title) \(row.count)") }
                    .disabled(row.count == 0)
            }
            if showsSSL(p) {
                Toggle(isOn: $selection.sslHosts) { Text("SSL Proxying 목록도 가져오기 (\(p.sslHosts.count))") }
            }
        }
        let graphQL = rows(p).map(\.graphQL).reduce(0, +)
        if p.skipped > 0 || !p.missingFiles.isEmpty || graphQL > 0 {
            VStack(alignment: .leading, spacing: 4) {
                if p.skipped > 0 { warning("읽지 못한 항목 \(p.skipped)개는 건너뜁니다") }
                if !p.missingFiles.isEmpty {
                    warning("응답 파일이 없는 Map Local 규칙 \(p.missingFiles.count)개는 꺼진 채로 추가됩니다. 편집기에서 파일을 다시 고르세요.")
                    Text(verbatim: p.missingFiles.joined(separator: "\n")).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(4).truncationMode(.middle).textSelection(.enabled)
                }
                if graphQL > 0 { warning("GraphQL 규칙 \(graphQL)개: 2차에서 지원, 꺼진 채로 추가") }
            }
        }
        Text("가져온 도구는 꺼진 상태로 추가됩니다. 각 도구 창에서 켜세요.").foregroundStyle(.secondary)
    }

    private func warning(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 결과

    @ViewBuilder private func summary(_ r: ImportResult) -> some View {
        let counts: [(String, ImportCount, ImportTool)] = [
            ("Map Local", r.mapLocal, .mapLocal), ("Map Remote", r.mapRemote, .mapRemote), ("Breakpoint", r.breakpoint, .breakpoint),
            ("Block List", r.block, .block), ("Allow List", r.allow, .allow), ("Network Conditions", r.networkConditions, .networkConditions),
        ]
        VStack(alignment: .leading, spacing: 4) {
            Text("가져오기를 마쳤습니다").font(.subheadline.bold())
            ForEach(counts.filter { c in (tool == nil || tool == c.2) && (c.1.added > 0 || c.1.skippedDuplicate > 0) }, id: \.0) { c in
                Text("\(c.0): \(c.1.added)개 추가, 이미 있는 \(c.1.skippedDuplicate)개 건너뜀")
            }
            if file == nil, selection.sslHosts { Text("SSL Proxying 목록: \(r.sslAdded)개 추가") }
            if r.skipped > 0 { warning("읽지 못한 항목 \(r.skipped)개를 건너뛰었습니다") }
            if !r.missingFiles.isEmpty { warning("응답 파일이 없는 Map Local 규칙 \(r.missingFiles.count)개를 꺼 두었습니다") }
            if r.graphQLDeferred > 0 { warning("GraphQL 규칙 \(r.graphQLDeferred)개: 2차에서 지원, 꺼진 채로 추가") }
        }
        Text("가져온 도구는 꺼진 상태로 추가됩니다. 각 도구 창에서 켜세요.").foregroundStyle(.secondary)
    }

    // MARK: - 읽기

    private func load() {
        guard preview == nil, failure == nil, result == nil else { return }
        do {
            let p = if let file, let tool { try ProxymanImporter.previewFile(file, as: tool) }
                    else { try ProxymanImporter.preview(proxymanDirectory: ProxymanImporter.appDirectory) }
            // 개수가 0인 도구와 겨냥하지 않은 도구는 끈 채로 둔다.
            for row in allRows(p) { selection[keyPath: row.key] = row.count > 0 && (tool == nil || row.tool == tool) }
            selection.sslHosts = showsSSL(p)
            preview = p
        } catch ProxymanImportError.notFound where file == nil {
            failure = String(localized: "Proxyman 데이터를 찾지 못했습니다")
        } catch ProxymanImportError.notFound {
            // 파일 경로의 notFound는 JSON이 아닌 파일도 포함한다.
            failure = String(localized: "규칙 파일로 읽지 못했습니다. Proxyman 내보내기(.config/.json)나 .eyeproxyrules 번들을 고르세요.")
        } catch {
            failure = String(localized: "파일을 읽지 못했습니다: \(error.localizedDescription)")
        }
    }
}

private func ruleCount<R: ToolRule>(_ nodes: [RuleNode<R>]) -> Int {
    nodes.reduce(0) { $0 + ($1.rule == nil ? 0 : 1) + ruleCount($1.children) }
}

private func graphQLCount<R: ToolRule>(_ nodes: [RuleNode<R>]) -> Int {
    nodes.reduce(0) { n, node in
        n + ((node.rule?.match.graphQLQueryName ?? "").isEmpty ? 0 : 1) + graphQLCount(node.children)
    }
}

/// More ▸ Import…/Export…의 파일 패널.
@MainActor enum RuleBundlePanel {
    /// `.config`·`.json` 파일 또는 `.eyeproxyrules` 폴더.
    static func chooseImport() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "config") ?? .data]
        panel.message = String(localized: "Proxyman 내보내기 파일(.config/.json)이나 EyeProxy 번들 폴더(.eyeproxyrules) 또는 그 안의 rules.config를 고르세요")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    /// 번들 폴더 위치. 이미 있으면(저장 패널에서 덮어쓰기를 확인함) 휴지통으로 옮긴다. Proxyman 폴더 안·위는 거부한다.
    static func chooseExport(name: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).eyeproxyrules"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard ProxymanImporter.isSafeWriteTarget(url) else { throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path]) }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        return url
    }
}
