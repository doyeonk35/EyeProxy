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
@Test func staleBackupFromOtherServiceIsRestoredFirst() {
    let b = SystemProxyBackup(service: "Wi-Fi", httpEnabled: false, httpHost: "", httpPort: 0, httpsEnabled: false, httpsHost: "", httpsPort: 0, bypass: [])
    #expect(SystemProxyCommands.restoreStale(b, currentService: "Ethernet") == SystemProxyCommands.restore(b))
    #expect(SystemProxyCommands.restoreStale(b, currentService: "Wi-Fi").isEmpty)
    #expect(SystemProxyCommands.restoreStale(nil, currentService: "Wi-Fi").isEmpty)
}
@Test func backupForMissingServiceIsOrphaned() {
    let b = SystemProxyBackup(service: "Gone", httpEnabled: false, httpHost: "", httpPort: 0, httpsEnabled: false, httpsHost: "", httpsPort: 0, bypass: [])
    #expect(SystemProxyCommands.isOrphaned(b, serviceOrder: serviceOrderSample))
    #expect(!SystemProxyCommands.isOrphaned(SystemProxyBackup(service: "Wi-Fi", httpEnabled: false, httpHost: "", httpPort: 0, httpsEnabled: false, httpsHost: "", httpsPort: 0, bypass: []), serviceOrder: serviceOrderSample))
    #expect(!SystemProxyCommands.isOrphaned(b, serviceOrder: ""))  // 목록을 못 읽으면 지우지 않는다
}

@Test func turnOffOwnTouchesOnlyOurPort() {
    let own = (enabled: true, host: "127.0.0.1", port: 9090)
    let other = (enabled: true, host: "10.0.0.1", port: 8080)
    let cntlm = (enabled: true, host: "127.0.0.1", port: 3128)
    #expect(SystemProxyCommands.turnOffOwn(service: "Wi-Fi", http: own, https: other, port: 9090) == [["-setwebproxystate", "Wi-Fi", "off"]])
    #expect(SystemProxyCommands.turnOffOwn(service: "Wi-Fi", http: other, https: own, port: 9090) == [["-setsecurewebproxystate", "Wi-Fi", "off"]])
    #expect(SystemProxyCommands.turnOffOwn(service: "Wi-Fi", http: other, https: other, port: 9090).isEmpty)
    #expect(SystemProxyCommands.turnOffOwn(service: "Wi-Fi", http: cntlm, https: cntlm, port: 9090).isEmpty)
    #expect(SystemProxyCommands.turnOffOwn(service: "Wi-Fi", http: (false, "127.0.0.1", 9090), https: (false, "", 0), port: 9090).isEmpty)
}
@Test func ownProxyIsNeverRecordedAsOriginal() {
    let o = SystemProxyCommands.originalProxy((enabled: true, host: "127.0.0.1", port: 9090), ownPort: 9090)
    #expect(!o.enabled && o.host.isEmpty && o.port == 0)
    let keep = SystemProxyCommands.originalProxy((enabled: true, host: "10.0.0.1", port: 8080), ownPort: 9090)
    #expect(keep.enabled && keep.host == "10.0.0.1" && keep.port == 8080)
    let cntlm = SystemProxyCommands.originalProxy((enabled: true, host: "127.0.0.1", port: 3128), ownPort: 9090)
    #expect(cntlm.enabled && cntlm.host == "127.0.0.1" && cntlm.port == 3128)  // 다른 포트의 로컬 프록시는 사용자의 것
}

// MARK: - VPN(GlobalProtect) 서비스가 복사한 프록시

private let vpnProxiesOurs = """
<dictionary> {
  ExceptionsList : <array> {
    0 : dns.google
    1 : one.one.one.one
  }
  FTPPassive : 1
  HTTPEnable : 1
  HTTPPort : 9090
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 9090
  HTTPSProxy : 127.0.0.1
  ProxyAutoConfigEnable : 0
  SOCKSEnable : 0
}
"""
@Test func parsesScutilProxy() {
    let p = SystemProxyCommands.parseScutilProxy(vpnProxiesOurs)
    #expect(p.httpEnabled && p.httpHost == "127.0.0.1" && p.httpPort == 9090)
    #expect(p.httpsEnabled && p.httpsHost == "127.0.0.1" && p.httpsPort == 9090)
    let off = SystemProxyCommands.parseScutilProxy("<dictionary> {\n  FTPPassive : 1\n  HTTPEnable : 0\n  HTTPSEnable : 0\n}\n")
    #expect(off == SystemProxyCommands.EffectiveProxy())
}
@Test func parsesPrimaryService() {
    #expect(SystemProxyCommands.parsePrimaryService("<dictionary> {\n  PrimaryInterface : utun6\n  PrimaryService : gpd.pan\n  Router : 172.29.0.162\n}\n") == "gpd.pan")
    #expect(SystemProxyCommands.parsePrimaryService("  No such key\n") == nil)
}
@Test func parsesProxyDictionaryKeepingOtherScalars() {
    let d = SystemProxyCommands.parseScutilProxyDictionary(vpnProxiesOurs)
    #expect(d.exceptions == ["dns.google", "one.one.one.one"])
    #expect(d.ftpPassive)
    #expect(d.other.map(\.key) == ["ProxyAutoConfigEnable", "SOCKSEnable"] && d.other.map(\.value) == ["0", "0"])
}
@Test func disableScriptTurnsOffHTTPAndKeepsRest() {
    let d = SystemProxyCommands.parseScutilProxyDictionary(vpnProxiesOurs)
    let s = SystemProxyCommands.scutilDisableProxyScript(serviceID: "gpd.pan", exceptions: d.exceptions, ftpPassive: d.ftpPassive,
                                                         other: d.other.map { ($0.key, $0.value) })
    #expect(s == """
    d.init
    d.add FTPPassive # 1
    d.add HTTPEnable # 0
    d.add HTTPSEnable # 0
    d.add ExceptionsList * dns.google one.one.one.one
    d.add ProxyAutoConfigEnable # 0
    d.add SOCKSEnable # 0
    set State:/Network/Service/gpd.pan/Proxies
    quit
    """)
    let bare = SystemProxyCommands.scutilDisableProxyScript(serviceID: "gpd.pan", exceptions: [], ftpPassive: false, other: [])
    #expect(bare?.contains("ExceptionsList") == false && bare?.contains("d.add FTPPassive # 0") == true)
    #expect(SystemProxyCommands.scutilDisableProxyScript(serviceID: "gpd.pan", exceptions: ["*.local", "169.254/16"], ftpPassive: true, other: []) != nil)
}
@Test func disableScriptRejectsUntrustedText() {
    #expect(SystemProxyCommands.scutilDisableProxyScript(serviceID: "gpd.pan\nremove State:/x", exceptions: [], ftpPassive: true, other: []) == nil)
    #expect(SystemProxyCommands.scutilDisableProxyScript(serviceID: "a b", exceptions: [], ftpPassive: true, other: []) == nil)
    #expect(SystemProxyCommands.scutilDisableProxyScript(serviceID: "gpd.pan", exceptions: ["a b"], ftpPassive: true, other: []) == nil)
    #expect(SystemProxyCommands.scutilDisableProxyScript(serviceID: "gpd.pan", exceptions: ["x'; rm"], ftpPassive: true, other: []) == nil)
    #expect(SystemProxyCommands.scutilDisableProxyScript(serviceID: "gpd.pan", exceptions: [], ftpPassive: true, other: [("K\nquit", "1")]) == nil)
    #expect(SystemProxyCommands.scutilDisableProxyScript(serviceID: "gpd.pan", exceptions: [], ftpPassive: true, other: [("K", "a b")]) == nil)
}
@Test func isOursMatchesOnlyOwnPort() {
    var p = SystemProxyCommands.EffectiveProxy()
    #expect(!SystemProxyCommands.isOurs(p, ownPort: 9090))
    p.httpsEnabled = true; p.httpsHost = "127.0.0.1"; p.httpsPort = 9090
    #expect(SystemProxyCommands.isOurs(p, ownPort: 9090))
    #expect(!SystemProxyCommands.isOurs(p, ownPort: 3128))  // Cntlm 등 다른 로컬 프록시
    p.httpsEnabled = false
    #expect(!SystemProxyCommands.isOurs(p, ownPort: 9090))  // 꺼져 있으면 주소가 남아도 우리 것이 아니다
}
