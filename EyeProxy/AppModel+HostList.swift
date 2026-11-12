import AppKit
import EyeProxyKit
import Foundation
import UniformTypeIdentifiers

/// 호스트 목록 파일(스펙 §4.5) 가져오기·내보내기. 실패는 `systemError`, 결과는 `infoMessage`.
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
        infoMessage = String(localized: "SSL Proxying List에 \(added)개를 더했습니다.")
    }

    /// `*`만으로 된 패턴이 있으면 모든 HTTPS를 복호화한다는 안내(가져오기·그룹 켜기 공용). 없으면 nil.
    static func allHTTPSNote(_ patterns: [String]) -> String? {
        patterns.contains(where: { $0.allSatisfy { $0 == "*" } }) ? String(localized: "*가 있어 모든 HTTPS를 복호화합니다.") : nil
    }

    /// 그룹 우클릭 Enable SSL Proxying: `*`가 있으면 확인을 받은 뒤에만 더한다.
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

    /// 열기 패널로 호스트 목록 파일을 골라 읽는다. 취소면 nil, 읽지 못하거나 쓸 호스트가 없으면 `systemError`를 쓰고 nil.
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
                systemError = String(localized: "목록에 쓸 호스트가 없습니다")
                return nil
            }
            return (url, list)
        } catch HostListError.tooLarge {
            systemError = String(localized: "파일이 너무 큽니다(1 MB 초과)")
        } catch HostListError.notText {
            systemError = String(localized: "텍스트 파일이 아닙니다")
        } catch HostListError.invalidJSON {
            systemError = String(localized: "Proxyman 목록을 읽지 못했습니다")
        } catch {
            systemError = String(localized: "호스트 목록을 읽지 못했습니다: \(error.localizedDescription)")
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
            systemError = String(localized: "호스트 목록을 저장하지 못했습니다: \(error.localizedDescription)")
        }
    }
}
