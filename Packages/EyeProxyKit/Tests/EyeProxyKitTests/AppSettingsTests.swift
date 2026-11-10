import Foundation
import Testing
@testable import EyeProxyKit

@Test @MainActor func settingsDefaultsAndPersistence() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    let s = AppSettings(defaults: d)
    #expect(s.port == 9090 && s.layout == .classic && s.bypassHosts == ["localhost", "127.0.0.1", "*.local"])
    #expect(s.sslEnabled && s.isRecording)
    s.port = 9191; s.sslPatterns = ["*.example.com"]; s.layout = .sideBySide; s.isRecording = false
    let again = AppSettings(defaults: d)
    #expect(again.port == 9191 && again.layout == .sideBySide)
    #expect(again.sslPolicy.shouldDecrypt(host: "a.example.com"))
    #expect(again.isRecording)  // 저장하지 않음
    #expect(s.pinnedHosts.isEmpty && s.wrapLongLines)
    s.togglePin("api.example.com"); s.togglePin("gw.example.com"); s.togglePin("api.example.com"); s.wrapLongLines = false
    #expect(AppSettings(defaults: d).pinnedHosts == ["gw.example.com"] && !AppSettings(defaults: d).wrapLongLines)
    #expect(s.appearance == .system)
    s.appearance = .dark
    #expect(AppSettings(defaults: d).appearance == .dark)
}

@Test @MainActor func toolSwitchesPersist() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    let s = AppSettings(defaults: d)
    #expect(s.toolSwitches == ToolSwitches())
    #expect(![s.toolSwitches.breakpoint, s.toolSwitches.mapLocal, s.toolSwitches.mapRemote, s.toolSwitches.blockList,
              s.toolSwitches.allowList, s.toolSwitches.networkConditions, s.toolSwitches.noCaching, s.toolSwitches.repeatNoCache].contains(true))
    s.toolSwitches.mapLocal = true
    #expect(AppSettings(defaults: d).toolSwitches.mapLocal)
    #expect(!AppSettings(defaults: d).toolSwitches.mapRemote)
    d.set(Data("x".utf8), forKey: "eyeproxy.toolSwitches")
    #expect(AppSettings(defaults: d).toolSwitches == ToolSwitches())
}

@Test @MainActor func mapLocalDefaultFolderPersists() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    let s = AppSettings(defaults: d)
    #expect(s.mapLocalDefaultFolder == nil)
    s.mapLocalDefaultFolder = "/tmp/maps"
    #expect(AppSettings(defaults: d).mapLocalDefaultFolder == "/tmp/maps")
    s.mapLocalDefaultFolder = nil
    #expect(AppSettings(defaults: d).mapLocalDefaultFolder == nil)
}

@Test @MainActor func showStatusItemPersists() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    let s = AppSettings(defaults: d)
    #expect(s.showStatusItem)
    s.showStatusItem = false
    #expect(!AppSettings(defaults: d).showStatusItem)
}

@Test @MainActor func settingPersists() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    let s = AppSettings(defaults: d)
    #expect(!s.autoSelectLatest)
    s.autoSelectLatest = true
    #expect(AppSettings(defaults: d).autoSelectLatest)
    #expect(d.bool(forKey: "eyeproxy.autoSelectLatest"))
}

@Test @MainActor func filterRulesPersist() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    let s = AppSettings(defaults: d)
    #expect(s.filterRules.rules.isEmpty && !s.filterRules.combineWithOr)
    var f = FlowFilter(host: "not-saved")
    f.rules = [FilterRule(key: .responseBody, match: .matchWildcard, text: "*tok?n*"), FilterRule(isEnabled: false, text: "a")]
    f.combineWithOr = true
    s.filterRules = f
    let again = AppSettings(defaults: d).filterRules
    #expect(again.rules == f.rules && again.combineWithOr && again.host == nil)
    d.set(Data("x".utf8), forKey: "eyeproxy.filterRules")
    #expect(AppSettings(defaults: d).filterRules.rules.isEmpty)
}

/// 스펙 §11 General·Appearance 새 항목의 기본값은 지금 동작을 바꾸지 않는다. 새 키는 `eyeproxy.` 접두로 저장된다.
@Test @MainActor func newSettingsHaveSpecDefaults() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    let s = AppSettings(defaults: d)
    #expect(s.truncationStyle == .tail)
    #expect(!s.autoOverrideSystemProxy && s.autoStartRecording && s.isRecording)
    #expect(s.fontSize == 13 && s.tabWidth == 2)
    #expect(!s.useMonospacedFont && !s.showInvisibles && s.alternativeRowBackgrounds)
    s.truncationStyle = .head; s.autoOverrideSystemProxy = true; s.autoStartRecording = false
    s.fontSize = 15; s.tabWidth = 4; s.useMonospacedFont = true; s.showInvisibles = true; s.alternativeRowBackgrounds = false
    #expect(d.string(forKey: "eyeproxy.truncationStyle") == "head" && d.bool(forKey: "eyeproxy.autoOverrideSystemProxy"))
    #expect(d.integer(forKey: "eyeproxy.fontSize") == 15 && d.integer(forKey: "eyeproxy.tabWidth") == 4)
    let again = AppSettings(defaults: d)
    #expect(again.truncationStyle == .head && again.autoOverrideSystemProxy && !again.autoStartRecording)
    #expect(again.fontSize == 15 && again.tabWidth == 4 && again.useMonospacedFont && again.showInvisibles && !again.alternativeRowBackgrounds)
    // Auto Start Recording을 끄면 기록 멈춤으로 시작한다.
    #expect(!again.isRecording)
}

/// 손으로 고친 범위 밖 값은 읽을 때 고정한다(탭 폭 0 이하는 들여쓰기에서 멈춘다, 글꼴 크기는 고르기 칸이 빈다).
@Test @MainActor func outOfRangeFontSizeAndTabWidthReadClamped() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    for (font, tab, wantFont, wantTab) in [(0, 0, 11, 2), (-5, -1, 11, 2), (99, 3, 16, 2), (14, 4, 14, 4), (16, 8, 16, 2)] {
        d.set(font, forKey: "eyeproxy.fontSize")
        d.set(tab, forKey: "eyeproxy.tabWidth")
        let s = AppSettings(defaults: d)
        #expect(s.fontSize == wantFont && s.tabWidth == wantTab, "font \(font) tab \(tab)")
    }
}

/// 옛 설정(외관·포트·상태 막대 아이콘·줄바꿈·레이아웃)은 키를 바꾸지 않고 그대로 읽는다.
@Test @MainActor func existingKeysAreReadUnchanged() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    d.set("dark", forKey: "eyeproxy.appearance")
    d.set(9191, forKey: "eyeproxy.port")
    d.set(false, forKey: "eyeproxy.showStatusItem")
    d.set(false, forKey: "eyeproxy.wrapLongLines")
    d.set("sideBySide", forKey: "eyeproxy.layout")
    let s = AppSettings(defaults: d)
    #expect(s.appearance == .dark && s.port == 9191 && !s.showStatusItem && !s.wrapLongLines && s.layout == .sideBySide)
}

/// Restore Defaults는 Appearance 탭 값만 되돌린다.
@Test @MainActor func restoreAppearanceDefaultsResetsOnlyAppearance() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    let s = AppSettings(defaults: d)
    s.fontSize = 16; s.tabWidth = 4; s.useMonospacedFont = true; s.wrapLongLines = false
    s.showInvisibles = true; s.alternativeRowBackgrounds = false; s.appearance = .dark
    s.port = 9191; s.layout = .sideBySide; s.showStatusItem = false; s.truncationStyle = .middle
    s.autoOverrideSystemProxy = true; s.autoStartRecording = false
    s.restoreAppearanceDefaults()
    for x in [s, AppSettings(defaults: d)] {
        #expect(x.fontSize == 13 && x.tabWidth == 2 && !x.useMonospacedFont && x.wrapLongLines)
        #expect(!x.showInvisibles && x.alternativeRowBackgrounds && x.appearance == .system)
        #expect(x.port == 9191 && x.layout == .sideBySide && !x.showStatusItem && x.truncationStyle == .middle)
        #expect(x.autoOverrideSystemProxy && !x.autoStartRecording)
    }
}
