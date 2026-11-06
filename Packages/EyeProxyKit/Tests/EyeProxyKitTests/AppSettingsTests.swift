import Foundation
import Testing
@testable import EyeProxyKit

@Test @MainActor func settingsDefaultsAndPersistence() {
    let d = UserDefaults(suiteName: UUID().uuidString)!
    let s = AppSettings(defaults: d)
    #expect(s.port == 9090 && s.layout == .classic && s.bypassHosts == ["localhost", "127.0.0.1", "*.local"])
    #expect(s.sslEnabled && s.isRecording)
    s.port = 9191; s.sslPatterns = ["*.tving.com"]; s.layout = .sideBySide; s.isRecording = false
    let again = AppSettings(defaults: d)
    #expect(again.port == 9191 && again.layout == .sideBySide)
    #expect(again.sslPolicy.shouldDecrypt(host: "a.tving.com"))
    #expect(again.isRecording)  // 저장하지 않음
    #expect(s.pinnedHosts.isEmpty && s.wrapLongLines)
    s.togglePin("api.tving.com"); s.togglePin("gw.tving.com"); s.togglePin("api.tving.com"); s.wrapLongLines = false
    #expect(AppSettings(defaults: d).pinnedHosts == ["gw.tving.com"] && !AppSettings(defaults: d).wrapLongLines)
}
