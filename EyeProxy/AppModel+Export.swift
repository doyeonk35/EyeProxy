import AppKit
import EyeProxyCore
import EyeProxyKit
import Foundation
import UniformTypeIdentifiers

/// 내보내기 형식과 HAR 가져오기. 범위·저장 패널은 `SessionTab+Export`(스펙 §8.4).
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

    /// File ▸ 세션 열기의 HAR 경로(스펙 §8.5): 탭의 세션을 교체. 번호·코멘트·Highlight를 복원하고 프로세스 귀속은 비운다.
    func importHAR(from url: URL, into tab: SessionTab) async throws {
        let imported = try await Task.detached { try FlowImport.har(Data(contentsOf: url)) }.value
        tab.session.replace(
            flows: imported.map(\.flow),
            comments: Dictionary(uniqueKeysWithValues: imported.compactMap { i in i.comment.map { (i.flow.id, $0) } }),
            highlights: Dictionary(uniqueKeysWithValues: imported.compactMap { i in i.highlight.map { (i.flow.id, $0) } }),
            numbers: Dictionary(uniqueKeysWithValues: imported.compactMap { i in i.number.map { (i.flow.id, $0) } }))
        tab.processes.replace([:])
    }

    /// Info.plist의 UTImportedTypeDeclarations와 일치해야 한다.
    nonisolated static let harType = UTType(importedAs: "com.tv.eyeproxy.har", conformingTo: .json)
    /// 저장·열기 패널용. .har는 다른 앱(Proxyman 등)이 선언한 UTI로 풀릴 수 있어 확장자 .har를 주장하는 타입을 모두 넣는다.
    nonisolated static var harTypes: [UTType] { [harType] + UTType.types(tag: "har", tagClass: .filenameExtension, conformingTo: nil) }
}
