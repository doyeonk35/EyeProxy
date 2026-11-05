import Foundation
import Testing
@testable import EyeProxyKit

@Test func enableCommandsSetBothProxiesAndBypass() {
    let c = SystemProxyCommands.enable(service: "Wi-Fi", host: "127.0.0.1", port: 9090, bypass: ["localhost", "*.local"])
    #expect(c.contains(["-setwebproxy", "Wi-Fi", "127.0.0.1", "9090"]))
    #expect(c.contains(["-setsecurewebproxy", "Wi-Fi", "127.0.0.1", "9090"]))
    #expect(c.contains(["-setproxybypassdomains", "Wi-Fi", "localhost", "*.local"]))
}
@Test func restoreDisablesWhenBackupWasOff() {
    let b = SystemProxyBackup(service: "Wi-Fi", httpEnabled: false, httpHost: "", httpPort: 0, httpsEnabled: false, httpsHost: "", httpsPort: 0, bypass: [])
    #expect(SystemProxyCommands.restore(b).contains(["-setwebproxystate", "Wi-Fi", "off"]))
}
@Test func parsesGetWebProxy() { #expect(SystemProxyCommands.parseGetWebProxy("Enabled: Yes\nServer: 10.0.0.1\nPort: 8080\nAuthenticated Proxy Enabled: 0\n") == (true, "10.0.0.1", 8080)) }
@Test func pendingRestoreReadsLeftoverBackup() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
    let b = SystemProxyBackup(service: "Wi-Fi", httpEnabled: true, httpHost: "1", httpPort: 1, httpsEnabled: true, httpsHost: "1", httpsPort: 1, bypass: [])
    try JSONEncoder().encode(b).write(to: url)
    #expect(SystemProxy(backupURL: url).pendingRestore() == b)
}
