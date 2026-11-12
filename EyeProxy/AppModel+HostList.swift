import AppKit
import EyeProxyKit
import Foundation
import UniformTypeIdentifiers

/// 호스트 목록 파일(스펙 §4.5) 가져오기·내보내기. 설정·그룹 시트에서도 보이게 결과·실패는 `showAlert`(모달 알림)로 낸다.
extension AppModel {
    /// 설정 ▸ SSL Proxying ▸ 가져오기…: 확인 알림 뒤 SSL Proxying List에 더하고, 고르면 호스트 그룹으로도 저장.
    func importSSLList() async {
        guard case let (url, list)? = await pickHostListFile() else { return }
        let added = HostList.merge(list.patterns, into: settings.sslPatterns).added.count
        var notes: [String] = []
        if list.rejected > 0 { notes.append(String(localized: "형식이 맞지 않는 줄 \(list.rejected)개는 버렸습니다.")) }
        if let note = Self.allHTTPSNote(list.patterns) { notes.append(note) }
        let alert = NSAlert()
        alert.messageText = String(localized: "호스트 패턴 \(list.patterns.count)개(새로 \(added)개)를 SSL Proxying List에 더할까요?")
        alert.informativeText = notes.joined(separator: "\n")
        let saveAsGroup = NSButton(checkboxWithTitle: String(localized: "호스트 그룹으로도 저장"), target: nil, action: nil)
        saveAsGroup.state = .on
        alert.accessoryView = saveAsGroup
        alert.addButton(withTitle: String(localized: "추가"))
        alert.addButton(withTitle: String(localized: "취소"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        await enableSSLProxying(forHosts: list.patterns)
        if saveAsGroup.state == .on {
            settings.saveGroup(HostGroup(name: url.deletingPathExtension().lastPathComponent, hostPatterns: list.patterns, apps: []))
        }
        Self.showAlert(String(localized: "SSL Proxying List에 \(added)개를 더했습니다."))
    }

    /// `*`·`?`·`.`로만 된 패턴(`*`, `*.*` 등)이 있으면 모든 HTTPS를 복호화한다는 안내(가져오기·그룹 켜기 공용). 없으면 nil.
    static func allHTTPSNote(_ patterns: [String]) -> String? {
        HostList.decryptsAllHTTPS(patterns) ? String(localized: "*가 있어 모든 HTTPS를 복호화합니다.") : nil
    }

    /// 이 흐름의 결과·오류 알림. 메인 창의 오류·안내 알림은 설정 창이나 시트 위에서는 보이지 않는다.
    static func showAlert(_ message: String, error: Bool = false) {
        let alert = NSAlert()
        alert.alertStyle = error ? .warning : .informational
        alert.messageText = error ? String(localized: "오류") : String(localized: "안내")
        alert.informativeText = message
        alert.runModal()
    }

    /// 그룹 우클릭 Enable SSL Proxying: `allHTTPSNote`에 걸리는 패턴이 있으면 확인을 받은 뒤에만 더한다.
    func enableSSLProxyingConfirmingAllHTTPS(forHosts hosts: [String]) async {
        if let note = Self.allHTTPSNote(hosts) {
            let alert = NSAlert()
            alert.messageText = String(localized: "호스트 패턴 \(hosts.count)개를 SSL Proxying List에 더할까요?")
            alert.informativeText = note
            alert.addButton(withTitle: String(localized: "추가"))
            alert.addButton(withTitle: String(localized: "취소"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        await enableSSLProxying(forHosts: hosts)
    }

    /// 열기 패널로 호스트 목록 파일을 골라 읽는다. 취소면 nil, 읽지 못하거나 쓸 호스트가 없으면 오류 알림을 띄우고 nil.
    func pickHostList() async -> HostList.Parsed? { await pickHostListFile()?.list }

    private func pickHostListFile() async -> (url: URL, list: HostList.Parsed)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .json] + [UTType(filenameExtension: "config")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            // 매핑으로 읽어 1 MB 넘는 파일도 통째로 메모리에 올리지 않고 parse가 거절한다.
            let list = try await Task.detached { try HostList.parse(Data(contentsOf: url, options: .mappedIfSafe)) }.value
            guard !list.patterns.isEmpty else {
                Self.showAlert(String(localized: "목록에 쓸 호스트가 없습니다"), error: true)
                return nil
            }
            return (url, list)
        } catch HostListError.tooLarge {
            Self.showAlert(String(localized: "파일이 너무 큽니다(1 MB 초과)"), error: true)
        } catch HostListError.notText {
            Self.showAlert(String(localized: "텍스트 파일이 아닙니다"), error: true)
        } catch HostListError.invalidJSON {
            Self.showAlert(String(localized: "Proxyman 목록을 읽지 못했습니다"), error: true)
        } catch {
            Self.showAlert(String(localized: "호스트 목록을 읽지 못했습니다: \(error.localizedDescription)"), error: true)
        }
        return nil
    }

    /// 설정 ▸ SSL Proxying ▸ 내보내기…·그룹 우클릭 Export…: `<suggestedName>.txt`로 저장.
    func exportHostList(_ patterns: [String], suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(suggestedName).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try HostList.serialize(patterns).write(to: url, options: .atomic)
            if settings.autoOpenExportDirectory { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } catch {
            Self.showAlert(String(localized: "호스트 목록을 저장하지 못했습니다: \(error.localizedDescription)"), error: true)
        }
    }
}
