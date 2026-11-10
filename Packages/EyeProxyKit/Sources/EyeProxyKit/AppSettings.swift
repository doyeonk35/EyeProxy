import EyeProxyCore
import Foundation
import Observation

public enum FlowLayout: String, Codable, Sendable { case classic, sideBySide }

/// 앱 외관. `system`은 macOS 설정을 따른다.
public enum Appearance: String, Codable, Sendable, CaseIterable { case system, light, dark }

/// 목록 말줄임 위치(General ▸ Truncation Style).
public enum TruncationStyle: String, Codable, Sendable, CaseIterable { case head, middle, tail }

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
    /// View ▸ Auto Select the Latest Request(스펙 §6). 사용자가 목록에서 다른 행을 고르면 꺼진다.
    public var autoSelectLatest: Bool { didSet { defaults.set(autoSelectLatest, forKey: "eyeproxy.autoSelectLatest") } }
    /// 마지막 필터 막대 규칙과 AND/OR(Proxyman "remembers your last filter settings"). `FlowFilter`는 이 둘만 저장된다.
    public var filterRules: FlowFilter {
        didSet { defaults.set(try? JSONEncoder().encode(filterRules), forKey: "eyeproxy.filterRules") }
    }
    /// 저장하지 않는다. 실행할 때 `autoStartRecording`으로 시작한다.
    public var isRecording: Bool

    // 설정 창 General·Appearance(스펙 §11). 기본값은 지금 동작을 바꾸지 않는 쪽.
    /// General ▸ Truncation Style: 목록 URL·Client 열 말줄임 위치.
    public var truncationStyle: TruncationStyle { didSet { defaults.set(truncationStyle.rawValue, forKey: "eyeproxy.truncationStyle") } }
    /// General ▸ Auto Override System Proxy Settings at Launch: 실행 시 "이 Mac 캡처"를 켠다.
    public var autoOverrideSystemProxy: Bool { didSet { defaults.set(autoOverrideSystemProxy, forKey: "eyeproxy.autoOverrideSystemProxy") } }
    /// General ▸ Auto Start Recording Traffic at Launch.
    public var autoStartRecording: Bool { didSet { defaults.set(autoStartRecording, forKey: "eyeproxy.autoStartRecording") } }
    /// Appearance ▸ Font Size(11~16): 상세 패널 본문·표.
    public var fontSize: Int { didSet { defaults.set(fontSize, forKey: "eyeproxy.fontSize") } }
    /// Appearance ▸ Tab Width(2·4): JSON Pretty 들여쓰기.
    public var tabWidth: Int { didSet { defaults.set(tabWidth, forKey: "eyeproxy.tabWidth") } }
    /// Appearance ▸ Use Monospaced Font: 목록 표.
    public var useMonospacedFont: Bool { didSet { defaults.set(useMonospacedFont, forKey: "eyeproxy.useMonospacedFont") } }
    /// Appearance ▸ Show Invisibles: 본문 텍스트의 공백·탭·줄바꿈 표시.
    public var showInvisibles: Bool { didSet { defaults.set(showInvisibles, forKey: "eyeproxy.showInvisibles") } }
    /// Appearance ▸ Alternative Rows Background Colors: 목록 줄무늬.
    public var alternativeRowBackgrounds: Bool { didSet { defaults.set(alternativeRowBackgrounds, forKey: "eyeproxy.alternativeRowBackgrounds") } }

    // 설정 창 Tools·Advanced(스펙 §11). Use No-Caching on Repeated Requests는 `toolSwitches.repeatNoCache`(옛 키 그대로).
    /// Tools ▸ Request Timeout(초, 0 = 없음): Compose 기본값·Repeat.
    public var requestTimeout: Int { didSet { defaults.set(requestTimeout, forKey: "eyeproxy.requestTimeout") } }
    /// Tools ▸ Add --proxy flag into cURL command.
    public var curlProxyFlag: Bool { didSet { defaults.set(curlProxyFlag, forKey: "eyeproxy.curlProxyFlag") } }
    /// Tools ▸ Auto open the Export Directory after exporting: 내보낸 파일을 Finder에서 보여 준다.
    public var autoOpenExportDirectory: Bool { didSet { defaults.set(autoOpenExportDirectory, forKey: "eyeproxy.autoOpenExportDirectory") } }
    /// Advanced ▸ Use 24-Hour Time: 목록 Time 열.
    public var use24HourTime: Bool { didSet { defaults.set(use24HourTime, forKey: "eyeproxy.use24HourTime") } }
    /// Advanced ▸ Display Full Time Format: Time 열에 날짜·시간대까지.
    public var displayFullTimeFormat: Bool { didSet { defaults.set(displayFullTimeFormat, forKey: "eyeproxy.displayFullTimeFormat") } }
    /// Advanced ▸ Show Alert when quitting the app.
    public var showQuitAlert: Bool { didSet { defaults.set(showQuitAlert, forKey: "eyeproxy.showQuitAlert") } }
    /// Advanced ▸ Show Resource Usage in Bottom Bar: 하단 바 메모리·속도.
    public var showResourceUsage: Bool { didSet { defaults.set(showResourceUsage, forKey: "eyeproxy.showResourceUsage") } }
    /// Advanced ▸ Hide Unnecessary Apple Requests from iOS Simulators(`SimulatorNoise`).
    public var hideAppleSimulatorRequests: Bool { didSet { defaults.set(hideAppleSimulatorRequests, forKey: "eyeproxy.hideAppleSimulatorRequests") } }
    /// Advanced ▸ Stay On Top: Prog 창 항상 위.
    public var stayOnTop: Bool { didSet { defaults.set(stayOnTop, forKey: "eyeproxy.stayOnTop") } }
    /// Advanced ▸ Show Invisible Characters: 헤더 탭(요청·응답) 값의 공백을 `·`로(보이기만, 복사는 원래 값).
    public var showInvisibleCharacters: Bool { didSet { defaults.set(showInvisibleCharacters, forKey: "eyeproxy.showInvisibleCharacters") } }

    /// Compose·Repeat에 넘기는 타임아웃. 0이면 nil(제한 없음).
    public var requestTimeoutInterval: TimeInterval? { requestTimeout > 0 ? TimeInterval(requestTimeout) : nil }

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
        autoSelectLatest = defaults.bool(forKey: "eyeproxy.autoSelectLatest")
        filterRules = defaults.data(forKey: "eyeproxy.filterRules").flatMap { try? JSONDecoder().decode(FlowFilter.self, from: $0) } ?? FlowFilter()
        toolSwitches = defaults.data(forKey: "eyeproxy.toolSwitches").flatMap { try? JSONDecoder().decode(ToolSwitches.self, from: $0) } ?? ToolSwitches()
        truncationStyle = defaults.string(forKey: "eyeproxy.truncationStyle").flatMap(TruncationStyle.init(rawValue:)) ?? .tail
        autoOverrideSystemProxy = defaults.bool(forKey: "eyeproxy.autoOverrideSystemProxy")
        let startRecording = defaults.object(forKey: "eyeproxy.autoStartRecording") as? Bool ?? true
        autoStartRecording = startRecording
        isRecording = startRecording
        // 손으로 고친 값도 고르기 칸 범위로(탭 폭 0 이하는 JSON 들여쓰기에서 멈춘다).
        fontSize = min(max(defaults.object(forKey: "eyeproxy.fontSize") as? Int ?? 13, 11), 16)
        tabWidth = defaults.object(forKey: "eyeproxy.tabWidth") as? Int == 4 ? 4 : 2
        useMonospacedFont = defaults.bool(forKey: "eyeproxy.useMonospacedFont")
        showInvisibles = defaults.bool(forKey: "eyeproxy.showInvisibles")
        alternativeRowBackgrounds = defaults.object(forKey: "eyeproxy.alternativeRowBackgrounds") as? Bool ?? true
        requestTimeout = max(defaults.object(forKey: "eyeproxy.requestTimeout") as? Int ?? 30, 0)
        curlProxyFlag = defaults.bool(forKey: "eyeproxy.curlProxyFlag")
        autoOpenExportDirectory = defaults.bool(forKey: "eyeproxy.autoOpenExportDirectory")
        use24HourTime = defaults.object(forKey: "eyeproxy.use24HourTime") as? Bool ?? true
        displayFullTimeFormat = defaults.bool(forKey: "eyeproxy.displayFullTimeFormat")
        showQuitAlert = defaults.bool(forKey: "eyeproxy.showQuitAlert")
        showResourceUsage = defaults.object(forKey: "eyeproxy.showResourceUsage") as? Bool ?? true
        hideAppleSimulatorRequests = defaults.bool(forKey: "eyeproxy.hideAppleSimulatorRequests")
        stayOnTop = defaults.bool(forKey: "eyeproxy.stayOnTop")
        showInvisibleCharacters = defaults.bool(forKey: "eyeproxy.showInvisibleCharacters")
    }

    /// Appearance ▸ Restore Defaults: Appearance 탭 값만 기본으로.
    public func restoreAppearanceDefaults() {
        (fontSize, tabWidth, useMonospacedFont, wrapLongLines) = (13, 2, false, true)
        (showInvisibles, alternativeRowBackgrounds, appearance) = (false, true, .system)
    }

    public func togglePin(_ host: String) {
        if let i = pinnedHosts.firstIndex(of: host) { pinnedHosts.remove(at: i) } else { pinnedHosts.append(host) }
    }
}
