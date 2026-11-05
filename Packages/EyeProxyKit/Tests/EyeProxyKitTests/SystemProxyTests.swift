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

private let serviceOrderSample = """
An asterisk (*) denotes that a network service is disabled.
(1) Wi-Fi
(Hardware Port: Wi-Fi, Device: en1)

(*) Thunderbolt Bridge
(Hardware Port: Thunderbolt Bridge, Device: bridge0)

(3) USB 10/100/1000 LAN
(Hardware Port: USB 10/100/1000 LAN, Device: en10)

"""
@Test func parsesServiceOrderWithDisabledEntry() {
    let s = SystemProxyCommands.parseServiceOrder(serviceOrderSample)
    #expect(s.map(\.name) == ["Wi-Fi", "Thunderbolt Bridge", "USB 10/100/1000 LAN"])
    #expect(s.map(\.device) == ["en1", "bridge0", "en10"])
    #expect(s.map(\.enabled) == [true, false, true])
}
@Test func restoreKeepsHostWhenOriginallyOff() {
    let b = SystemProxyBackup(service: "Wi-Fi", httpEnabled: false, httpHost: "1.2.3.4", httpPort: 80, httpsEnabled: false, httpsHost: "", httpsPort: 0, bypass: [])
    let c = SystemProxyCommands.restore(b)
    #expect(c.contains(["-setwebproxy", "Wi-Fi", "1.2.3.4", "80"]) && c.contains(["-setwebproxystate", "Wi-Fi", "off"]))
    #expect(!c.contains { $0.first == "-setsecurewebproxy" })
}
@Test func existingBackupIsNeverOverwritten() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
    let a = SystemProxyBackup(service: "Wi-Fi", httpEnabled: true, httpHost: "orig", httpPort: 1, httpsEnabled: false, httpsHost: "", httpsPort: 0, bypass: [])
    let b = SystemProxyBackup(service: "Wi-Fi", httpEnabled: true, httpHost: "127.0.0.1", httpPort: 9090, httpsEnabled: true, httpsHost: "127.0.0.1", httpsPort: 9090, bypass: [])
    let p = SystemProxy(backupURL: url)
    #expect(try p.saveBackupIfAbsent(a)); let before = try Data(contentsOf: url)
    #expect(try !p.saveBackupIfAbsent(b)); #expect(try Data(contentsOf: url) == before)
    #expect(p.pendingRestore() == a)
}
