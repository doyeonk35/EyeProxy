import AppKit
import EyeProxyCore
import EyeProxyKit
import Foundation
import UniformTypeIdentifiers

/// Flow ▸ Export·Save Requests(스펙 §8.4). 직렬화는 Kit(`FlowExport`·`SessionDocument`), 앱은 범위와 저장 패널만.
extension AppModel {
    enum ExportFormat {
        case har, csv, session

        var type: UTType {
            switch self {
            case .har: AppModel.harType
            case .csv: .commaSeparatedText
            case .session: AppModel.sessionType
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

    /// 내보낼 항목. `scope`가 비어 있지 않으면 그중 보이는 행, 비었거나 nil이면 보이는 행 전체.
    /// 순서는 안정 번호 오름차순 — 목록 정렬 상태에 따라 파일 내용이 달라지지 않게.
    func exportItems(scope: Set<FlowID>?) -> [ExportItem] {
        let runtimes = simulatorRuntimes
        let deviceNames = Dictionary(devices.devices.map { ($0.address, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        // 목록 Client 열과 같은 문자열: 프로세스 귀속 → (루프백이 아니면) 기기 이름 → 주소.
        func client(_ flow: Flow) -> String? {
            if let identity = processes.attribution[flow.id] { return identity.displayName(runtimes: runtimes) }
            return FlowFilter.isLoopback(flow.clientAddress) ? nil : deviceNames[flow.clientAddress] ?? flow.clientAddress
        }
        let scope = scope?.isEmpty == false ? scope : nil
        return visibleFlows.filter { scope?.contains($0.id) ?? true }
            .map { ExportItem(flow: $0, number: session.number($0.id) ?? 0, comment: session.comments[$0.id],
                              highlight: session.highlights[$0.id], client: client($0)) }
            .sorted { $0.number < $1.number }
    }

    /// Flow ▸ Export ▸ … 와 우클릭 ▸ Export ▸ …. 범위는 `exportItems(scope:)`.
    func export(_ format: ExportFormat, scope: Set<FlowID>?) async {
        let items = exportItems(scope: scope)
        guard !items.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
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
                case .csv: try Data(FlowExport.csv(items).utf8).write(to: url, options: .atomic)
                case .session:
                    try SessionDocument.save(
                        flows: items.map(\.flow), connectionLog: log, processes: attribution,
                        comments: Dictionary(uniqueKeysWithValues: items.compactMap { i in i.comment.map { (i.flow.id, $0) } }),
                        highlights: Dictionary(uniqueKeysWithValues: items.compactMap { i in i.highlight.map { (i.flow.id, $0) } }),
                        numbers: Dictionary(uniqueKeysWithValues: items.map { ($0.flow.id, $0.number) }), to: url)
                }
            }.value
        } catch {
            systemError = String(localized: "내보내지 못했습니다: \(error.localizedDescription)")
        }
    }

    /// Flow ▸ Save Requests…: 선택한 행만 Prog 세션으로(Export ▸ as Prog Session과 같되 선택이 없으면 하지 않는다).
    func saveRequests() async {
        guard !selectedFlowIDs.isEmpty else { return }
        await export(.session, scope: selectedFlowIDs)
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
}
