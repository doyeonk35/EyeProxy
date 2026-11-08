import EyeProxyCore
import Foundation
import Observation

public enum FlowLayout: String, Codable, Sendable { case classic, sideBySide }

/// 앱 외관. `system`은 macOS 설정을 따른다.
public enum Appearance: String, Codable, Sendable, CaseIterable { case system, light, dark }

@Observable @MainActor
public final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    public var port: Int { didSet { defaults.set(port, forKey: "eyeproxy.port") } }
    public var sslEnabled: Bool { didSet { defaults.set(sslEnabled, forKey: "eyeproxy.sslEnabled") } }
    public var sslPatterns: [String] { didSet { defaults.set(sslPatterns, forKey: "eyeproxy.sslPatterns") } }
    public var bypassHosts: [String] { didSet { defaults.set(bypassHosts, forKey: "eyeproxy.bypassHosts") } }
    public var layout: FlowLayout { didSet { defaults.set(layout.rawValue, forKey: "eyeproxy.layout") } }
    public var pinnedHosts: [String] { didSet { defaults.set(pinnedHosts, forKey: "eyeproxy.pinnedHosts") } }
    public var wrapLongLines: Bool { didSet { defaults.set(wrapLongLines, forKey: "eyeproxy.wrapLongLines") } }
    public var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "eyeproxy.appearance") } }
    public var toolSwitches: ToolSwitches {
        didSet { defaults.set(try? JSONEncoder().encode(toolSwitches), forKey: "eyeproxy.toolSwitches") }
    }
    /// Map Local 응답 파일 폴더(More ▸ Default Local File Folder). nil이면 기본 폴더.
    public var mapLocalDefaultFolder: String? { didSet { defaults.set(mapLocalDefaultFolder, forKey: "eyeproxy.mapLocalDefaultFolder") } }
    /// 메뉴 막대 상태 아이콘 표시.
    public var showStatusItem: Bool { didSet { defaults.set(showStatusItem, forKey: "eyeproxy.showStatusItem") } }
    /// 저장하지 않는다 (실행할 때마다 기록 중으로 시작).
    public var isRecording = true

    public var sslPolicy: SSLProxyingPolicy { SSLProxyingPolicy(isEnabled: sslEnabled, patterns: sslPatterns) }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        port = defaults.object(forKey: "eyeproxy.port") as? Int ?? 9090
        sslEnabled = defaults.object(forKey: "eyeproxy.sslEnabled") as? Bool ?? true
        sslPatterns = defaults.stringArray(forKey: "eyeproxy.sslPatterns") ?? []
        bypassHosts = defaults.stringArray(forKey: "eyeproxy.bypassHosts") ?? ["localhost", "127.0.0.1", "*.local"]
        layout = defaults.string(forKey: "eyeproxy.layout").flatMap(FlowLayout.init(rawValue:)) ?? .classic
        pinnedHosts = defaults.stringArray(forKey: "eyeproxy.pinnedHosts") ?? []
        wrapLongLines = defaults.object(forKey: "eyeproxy.wrapLongLines") as? Bool ?? true
        appearance = defaults.string(forKey: "eyeproxy.appearance").flatMap(Appearance.init(rawValue:)) ?? .system
        mapLocalDefaultFolder = defaults.string(forKey: "eyeproxy.mapLocalDefaultFolder")
        showStatusItem = defaults.object(forKey: "eyeproxy.showStatusItem") as? Bool ?? true
        toolSwitches = defaults.data(forKey: "eyeproxy.toolSwitches").flatMap { try? JSONDecoder().decode(ToolSwitches.self, from: $0) } ?? ToolSwitches()
    }

    public func togglePin(_ host: String) {
        if let i = pinnedHosts.firstIndex(of: host) { pinnedHosts.remove(at: i) } else { pinnedHosts.append(host) }
    }
}
