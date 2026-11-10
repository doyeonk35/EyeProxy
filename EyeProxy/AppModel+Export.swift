import AppKit
import EyeProxyCore
import EyeProxyKit
import Foundation
import UniformTypeIdentifiers

/// Flow ▸ Export·Save Requests(스펙 §8.4). 직렬화는 Kit(`FlowExport`·`SessionDocument`), 앱은 범위와 저장 패널만.
extension AppModel {
    enum ExportFormat {
        case har, csv, session

        var types: [UTType] {
            switch self {
            case .har: AppModel.harTypes
            case .csv: [.commaSeparatedText]
            case .session: [AppModel.sessionType]
            }
        }

        var pathExtension: String {
            switch self {
            case .har: "har"
            case .csv: "csv"
            case .session: SessionDocument.pathExtension
            }
        }
    }

    /// 내보낼 항목. `scope` 중 보이는 행이 있으면 그 행만, 없으면(nil·빈 값·전부 숨김) 보이는 행 전체(스펙 §8.4).
    /// 순서는 안정 번호 오름차순 — 목록 정렬 상태에 따라 파일 내용이 달라지지 않게.
    func exportItems(scope: Set<FlowID>?) -> [ExportItem] {
        // 묶어 둔 목록은 트래픽 중 최대 250 ms 늦다 — 막 도착한 응답 본문까지 담도록 지금 맞춘다.
        refreshVisibleRows()
        let visible = visibleFlows
        let chosen = visible.filter { scope?.contains($0.id) ?? false }
        return (chosen.isEmpty ? visible : chosen)
            .map { flow in
                let client = clientName(for: flow)
                return ExportItem(flow: flow, number: session.number(flow.id) ?? 0, comment: session.comments[flow.id],
                                  highlight: session.highlights[flow.id], client: client.isEmpty ? nil : client)
            }
            .sorted { $0.number < $1.number }
    }

    /// 선택 중 보이는 행. Save Requests의 대상·켜짐 판단(필터가 숨긴 선택은 저장하지 않는다).
    var visibleSelectedFlowIDs: Set<FlowID> {
        guard !selectedFlowIDs.isEmpty else { return [] }
        return Set(visibleFlows.lazy.map(\.id).filter(selectedFlowIDs.contains))
    }

    /// Flow ▸ Export ▸ … 와 우클릭 ▸ Export ▸ …. 범위는 `exportItems(scope:)`.
    func export(_ format: ExportFormat, scope: Set<FlowID>?) async {
        let items = exportItems(scope: scope)
        guard !items.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = format.types
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "Prog-\(stamp.string(from: .now)).\(format.pathExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let ids = Set(items.map(\.flow.id))
        // 연결 기록은 흐름별이 아니라 세션 전체 기록이다 → 세션 전부를 내보낼 때만 담는다(숨긴 호스트가 새지 않게).
        let log = ids.count == session.flows.count ? session.connectionLog : []
        let attribution = processes.attribution.filter { ids.contains($0.key) }
        do {
            try await Task.detached {
                switch format {
                case .har: try FlowExport.har(items, version: version).write(to: url, options: .atomic)
                // Mac용 Excel은 BOM이 없으면 UTF-8 CSV를 시스템 인코딩으로 읽어 한글이 깨진다 → 앱이 쓰는 파일에만 붙인다(Kit 출력은 그대로).
                case .csv: try (Data([0xEF, 0xBB, 0xBF]) + Data(FlowExport.csv(items).utf8)).write(to: url, options: .atomic)
                case .session:
                    try SessionDocument.save(
                        flows: items.map(\.flow), connectionLog: log, processes: attribution,
                        comments: Dictionary(uniqueKeysWithValues: items.compactMap { i in i.comment.map { (i.flow.id, $0) } }),
                        highlights: Dictionary(uniqueKeysWithValues: items.compactMap { i in i.highlight.map { (i.flow.id, $0) } }),
                        numbers: Dictionary(uniqueKeysWithValues: items.map { ($0.flow.id, $0.number) }), to: url)
                }
            }.value
            // Tools ▸ Auto open the Export Directory after exporting.
            if settings.autoOpenExportDirectory { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } catch {
            systemError = String(localized: "내보내지 못했습니다: \(error.localizedDescription)")
        }
    }

    /// Flow ▸ Save Requests…: 선택 중 보이는 행만 Prog 세션으로(Export ▸ as Prog Session과 같되 그런 행이 없으면 하지 않는다).
    func saveRequests() async {
        refreshVisibleRows()
        let ids = visibleSelectedFlowIDs
        guard !ids.isEmpty else { return }
        await export(.session, scope: ids)
    }

    /// File ▸ 세션 열기의 HAR 경로(스펙 §8.5): 현재 세션을 교체. 번호·코멘트·Highlight를 복원하고 프로세스 귀속은 비운다.
    /// 클라이언트 문자열은 이번엔 복원하지 않는다(기기 앱 귀속과 함께 다음 묶음).
    func importHAR(from url: URL) async throws {
        let imported = try await Task.detached { try FlowImport.har(Data(contentsOf: url)) }.value
        session.replace(
            flows: imported.map(\.flow),
            comments: Dictionary(uniqueKeysWithValues: imported.compactMap { i in i.comment.map { (i.flow.id, $0) } }),
            highlights: Dictionary(uniqueKeysWithValues: imported.compactMap { i in i.highlight.map { (i.flow.id, $0) } }),
            numbers: Dictionary(uniqueKeysWithValues: imported.compactMap { i in i.number.map { (i.flow.id, $0) } }))
        processes.replace([:])
    }

    /// Info.plist의 UTImportedTypeDeclarations와 일치해야 한다.
    nonisolated static let harType = UTType(importedAs: "com.tv.eyeproxy.har", conformingTo: .json)
    /// 저장·열기 패널용. .har는 다른 앱(Proxyman 등)이 선언한 UTI로 풀릴 수 있어 확장자 .har를 주장하는 타입을 모두 넣는다.
    nonisolated static var harTypes: [UTType] { [harType] + UTType.types(tag: "har", tagClass: .filenameExtension, conformingTo: nil) }
}
