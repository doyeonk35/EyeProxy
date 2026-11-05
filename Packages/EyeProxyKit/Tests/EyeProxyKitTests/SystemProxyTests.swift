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
/// `scutil --proxy`: 최상위 값 뒤에 정렬되는 `__SCOPED__`의 인터페이스별 값이 최상위를 덮어쓰면 안 된다.
private func scopedSample(top: (String, Int), scoped: (String, Int)) -> String { """
<dictionary> {
  ExceptionsList : <array> {
    0 : dns.google
  }
  FTPPassive : 1
  HTTPEnable : 1
  HTTPPort : \(top.1)
  HTTPProxy : \(top.0)
  HTTPSEnable : 1
  HTTPSPort : \(top.1)
  HTTPSProxy : \(top.0)
  __SCOPED__ : <dictionary> {
    en0 : <dictionary> {
      ExceptionsList : <array> {
        0 : localhost
      }
      HTTPEnable : 1
      HTTPPort : \(scoped.1)
      HTTPProxy : \(scoped.0)
      HTTPSEnable : 1
      HTTPSPort : \(scoped.1)
      HTTPSProxy : \(scoped.0)
    }
    utun6 : <dictionary> {
      HTTPEnable : 0
      HTTPSEnable : 0
    }
  }
}
""" }
@Test func parsesScutilProxy() {
    let p = SystemProxyCommands.parseScutilProxy(vpnProxiesOurs)
    #expect(p.httpEnabled && p.httpHost == "127.0.0.1" && p.httpPort == 9090)
    #expect(p.httpsEnabled && p.httpsHost == "127.0.0.1" && p.httpsPort == 9090)
    let off = SystemProxyCommands.parseScutilProxy("<dictionary> {\n  FTPPassive : 1\n  HTTPEnable : 0\n  HTTPSEnable : 0\n}\n")
    #expect(off == SystemProxyCommands.EffectiveProxy())
}
@Test func scopedValuesDoNotOverrideTopLevel() {
    let ours = SystemProxyCommands.parseScutilProxy(scopedSample(top: ("127.0.0.1", 9090), scoped: ("10.0.0.1", 8080)))
    #expect(ours.httpHost == "127.0.0.1" && ours.httpPort == 9090 && SystemProxyCommands.isOurs(ours, ownPort: 9090))
    let notOurs = SystemProxyCommands.parseScutilProxy(scopedSample(top: ("10.0.0.1", 8080), scoped: ("127.0.0.1", 9090)))
    #expect(notOurs.httpsHost == "10.0.0.1" && notOurs.httpsPort == 8080 && !SystemProxyCommands.isOurs(notOurs, ownPort: 9090))
    #expect(SystemProxyCommands.parseScutilProxyDictionary(scopedSample(top: ("127.0.0.1", 9090), scoped: ("1", 1))).exceptions == ["dns.google"])
}
@Test func parsesPrimaryService() {
    #expect(SystemProxyCommands.parsePrimaryService("<dictionary> {\n  PrimaryInterface : utun6\n  PrimaryService : gpd.pan\n  Router : 172.29.0.162\n}\n") == "gpd.pan")
    #expect(SystemProxyCommands.parsePrimaryService("  No such key\n") == nil)
}
@Test func parsesProxyDictionaryKeepingOtherScalars() {
    let d = SystemProxyCommands.parseScutilProxyDictionary(vpnProxiesOurs)
    #expect(d.exceptions == ["dns.google", "one.one.one.one"])
    #expect(d.ftpPassive && !d.droppedContainer)
    #expect(d.other.map(\.key) == ["ProxyAutoConfigEnable", "SOCKSEnable"] && d.other.map(\.value) == ["0", "0"])
}
private func script(_ d: SystemProxyCommands.ProxyDictionary, id: String = "gpd.pan") -> String? {
    SystemProxyCommands.scutilDisableProxyScript(serviceID: id, d, ownPort: 9090)
}
private func dict(exceptions: [String] = [], other: [(key: String, value: String)] = []) -> SystemProxyCommands.ProxyDictionary {
    var d = SystemProxyCommands.ProxyDictionary(); d.ftpPassive = true; d.exceptions = exceptions; d.other = other; return d
}
@Test func disableScriptTurnsOffHTTPAndKeepsRest() {
    #expect(script(SystemProxyCommands.parseScutilProxyDictionary(vpnProxiesOurs)) == """
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
    var bare = SystemProxyCommands.ProxyDictionary(); bare.ftpPassive = false
    #expect(script(bare)?.contains("ExceptionsList") == false && script(bare)?.contains("d.add FTPPassive # 0") == true)
    #expect(script(dict(exceptions: ["*.local", "169.254/16", "fe80::1"])) != nil)
}
@Test func disableScriptKeepsSideThatIsNotOurs() {
    var d = dict()
    d.proxy = .init(httpEnabled: true, httpHost: "127.0.0.1", httpPort: 9090, httpsEnabled: true, httpsHost: "proxy.corp.example", httpsPort: 8080)
    let s = script(d) ?? ""
    #expect(s.contains("d.add HTTPEnable # 0"))
    #expect(s.contains("d.add HTTPSEnable # 1\nd.add HTTPSProxy proxy.corp.example\nd.add HTTPSPort # 8080"))
    d.proxy = .init(httpEnabled: true, httpHost: "127.0.0.1", httpPort: 3128, httpsEnabled: false, httpsHost: "127.0.0.1", httpsPort: 9090)
    let cntlm = script(d) ?? ""   // 다른 포트의 로컬 프록시는 사용자의 것, 꺼진 쪽은 꺼진 채
    #expect(cntlm.contains("d.add HTTPEnable # 1\nd.add HTTPProxy 127.0.0.1\nd.add HTTPPort # 3128") && cntlm.contains("d.add HTTPSEnable # 0"))
}
@Test func disableScriptTypesValues() {
    let s = script(dict(other: [("ExcludeSimpleHostnames", "TRUE"), ("SOCKSEnable", "0"), ("ProxyAutoConfigURLString", "http://wpad/x.pac?a=b")])) ?? ""
    #expect(s.contains("d.add ExcludeSimpleHostnames ? TRUE\n") && s.contains("d.add SOCKSEnable # 0\n"))
    #expect(s.contains("d.add ProxyAutoConfigURLString http://wpad/x.pac?a=b\n"))
}
@Test func disableScriptFailsClosedOnNestedContainer() {
    let d = SystemProxyCommands.parseScutilProxyDictionary(vpnProxiesOurs.replacingOccurrences(of: "  FTPPassive : 1\n",
        with: "  FTPPassive : 1\n  SupplementalMatchDomains : <array> {\n    0 : corp.example\n  }\n"))
    #expect(d.droppedContainer && d.exceptions == ["dns.google", "one.one.one.one"])
    #expect(script(d) == nil)
}
@Test func disableScriptRejectsUntrustedText() {
    #expect(script(dict(), id: "gpd.pan\nremove State:/x") == nil)
    #expect(script(dict(), id: "a b") == nil)
    #expect(script(dict(exceptions: ["a b"])) == nil)
    #expect(script(dict(exceptions: ["x'; rm"])) == nil)
    #expect(script(dict(exceptions: ["a#b"])) == nil)
    #expect(script(dict(exceptions: ["a\"b"])) == nil)
    #expect(script(dict(exceptions: ["a\nquit"])) == nil)
    for flag in ["*", "?", "%", "-", "#"] {
        #expect(script(dict(exceptions: [flag])) == nil)
        #expect(script(dict(other: [("K", flag)])) == nil)
    }
    #expect(script(dict(other: [("K\nquit", "1")])) == nil)
    #expect(script(dict(other: [("K", "a b")])) == nil)
    #expect(script(dict(other: [("K", "a\nset State:/x")])) == nil)
    var d = dict(); d.proxy = .init(httpEnabled: true, httpHost: "evil\nquit", httpPort: 80)
    #expect(script(d) == nil)
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
