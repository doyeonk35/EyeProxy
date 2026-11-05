import Foundation

public struct SystemProxyBackup: Codable, Equatable, Sendable {
    public let service: String
    public let httpEnabled: Bool; public let httpHost: String; public let httpPort: Int
    public let httpsEnabled: Bool; public let httpsHost: String; public let httpsPort: Int
    public let bypass: [String]
    public init(service: String, httpEnabled: Bool, httpHost: String, httpPort: Int, httpsEnabled: Bool, httpsHost: String, httpsPort: Int, bypass: [String]) {
        self.service = service
        self.httpEnabled = httpEnabled; self.httpHost = httpHost; self.httpPort = httpPort
        self.httpsEnabled = httpsEnabled; self.httpsHost = httpsHost; self.httpsPort = httpsPort
        self.bypass = bypass
    }
}

public enum SystemProxyError: Error { case noActiveService, commandFailed(String) }

public enum SystemProxyCommands {
    private static func bypassCmd(_ svc: String, _ bypass: [String]) -> [String] {
        ["-setproxybypassdomains", svc] + (bypass.isEmpty ? ["Empty"] : bypass)
    }

    public static func enable(service svc: String, host: String, port: Int, bypass: [String]) -> [[String]] {
        [["-setwebproxy", svc, host, "\(port)"],
         ["-setsecurewebproxy", svc, host, "\(port)"],
         bypassCmd(svc, bypass),
         ["-setwebproxystate", svc, "on"],
         ["-setsecurewebproxystate", svc, "on"]]
    }

    /// 백업이 다른 서비스의 것이면(그 사이 기본 네트워크가 바뀜) 그 서비스를 먼저 되돌릴 명령. 아니면 [].
    public static func restoreStale(_ backup: SystemProxyBackup?, currentService: String) -> [[String]] {
        guard let backup, backup.service != currentService else { return [] }
        return restore(backup)
    }

    public static func restore(_ b: SystemProxyBackup) -> [[String]] {
        var c: [[String]] = []
        // 꺼져 있던 경우에도 host/port를 되돌려 EyeProxy 주소가 설정 화면에 남지 않게 한다.
        if !b.httpHost.isEmpty { c.append(["-setwebproxy", b.service, b.httpHost, "\(b.httpPort)"]) }
        c.append(["-setwebproxystate", b.service, b.httpEnabled ? "on" : "off"])
        if !b.httpsHost.isEmpty { c.append(["-setsecurewebproxy", b.service, b.httpsHost, "\(b.httpsPort)"]) }
        c.append(["-setsecurewebproxystate", b.service, b.httpsEnabled ? "on" : "off"])
        c.append(bypassCmd(b.service, b.bypass))
        return c
    }

    /// 백업의 서비스가 서비스 목록에 없으면(삭제·이름 변경) 되돌릴 곳이 없다. 목록을 못 읽었으면(빈 출력) false.
    public static func isOrphaned(_ backup: SystemProxyBackup, serviceOrder output: String) -> Bool {
        let names = parseServiceOrder(output).map(\.name)
        return !names.isEmpty && !names.contains(backup.service)
    }

    /// EyeProxy 자신의 주소(127.0.0.1:<port>)인 프록시만 끄는 명령. 127.0.0.1의 다른 포트(Cntlm 등)는 사용자의 것이다. 다른 프록시는 건드리지 않는다.
    /// 이름이 바뀐 서비스는 설정을 그대로 가지므로, 백업을 잃은 뒤에도 남은 EyeProxy 설정을 치우는 데 쓴다.
    public static func turnOffOwn(service svc: String,
                                  http: (enabled: Bool, host: String, port: Int),
                                  https: (enabled: Bool, host: String, port: Int),
                                  port: Int) -> [[String]] {
        var c: [[String]] = []
        if http.enabled, http.host == ownHost, http.port == port { c.append(["-setwebproxystate", svc, "off"]) }
        if https.enabled, https.host == ownHost, https.port == port { c.append(["-setsecurewebproxystate", svc, "off"]) }
        return c
    }

    /// 원본으로 기록할 프록시 값. 127.0.0.1은 EyeProxy 잔여물이므로 원본이 아니라 "꺼짐·주소 없음"으로 기록한다.
    public static func originalProxy(_ p: (enabled: Bool, host: String, port: Int), ownPort port: Int) -> (enabled: Bool, host: String, port: Int) {
        p.host == ownHost && p.port == port ? (false, "", 0) : p
    }

    static let ownHost = "127.0.0.1"

    /// `-listnetworkserviceorder` 출력 → 서비스 목록. `(*) Name` 헤더는 비활성.
    public static func parseServiceOrder(_ output: String) -> [(name: String, device: String, enabled: Bool)] {
        var result: [(name: String, device: String, enabled: Bool)] = []
        var cur: (name: String, enabled: Bool)?
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("("), let r = line.range(of: ") "), !line.hasPrefix("(Hardware") {
                let tag = line[line.index(after: line.startIndex)..<r.lowerBound]
                cur = (String(line[r.upperBound...]), tag != "*")
            } else if line.hasPrefix("(Hardware Port:"), let c = cur, let r = line.range(of: "Device: ") {
                let dev = line[r.upperBound...].prefix { $0 != ")" }
                result.append((c.name, dev.trimmingCharacters(in: .whitespaces), c.enabled))
                cur = nil
            }
        }
        return result
    }

    public static func parseGetWebProxy(_ output: String) -> (enabled: Bool, host: String, port: Int) {
        var r = (enabled: false, host: "", port: 0)
        for line in output.split(whereSeparator: \.isNewline) {
            guard let i = line.firstIndex(of: ":") else { continue }
            let k = line[..<i].trimmingCharacters(in: .whitespaces)
            let v = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            switch k {
            case "Enabled": r.enabled = v == "Yes"
            case "Server": r.host = v
            case "Port": r.port = Int(v) ?? 0
            default: break
            }
        }
        return r
    }
}

public final class SystemProxy: Sendable {
    private static let networksetup = "/usr/sbin/networksetup"
    private let backupURL: URL
    public init(backupURL: URL) { self.backupURL = backupURL }

    public func activeService() async throws -> String {
        let route = try await Shell.run("/sbin/route", ["-n", "get", "default"]).stdout
        let iface = route.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("interface:") }.map { $0.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces) } ?? ""
        let order = SystemProxyCommands.parseServiceOrder(try await Shell.run(Self.networksetup, ["-listnetworkserviceorder"]).stdout)
        let tunnel = ["utun", "ipsec", "ppp"].contains { iface.hasPrefix($0) }
        if !tunnel, let m = order.first(where: { $0.enabled && $0.device == iface }) { return m.name }
        // VPN 등으로 기본 인터페이스가 서비스와 맞지 않으면 IPv4 주소를 가진 첫 활성 서비스.
        for s in order where s.enabled && !s.device.isEmpty {
            let ip = try await Shell.run("/usr/sbin/ipconfig", ["getifaddr", s.device]).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !ip.isEmpty && !ip.hasPrefix("169.254.") { return s.name }  // 링크로컬(DHCP 실패)은 인터넷 경로가 아니다
        }
        throw SystemProxyError.noActiveService
    }

    /// 서비스가 사라진 백업은 영원히 복원에 실패하므로 지운다. 지웠으면 true.
    /// 이름만 바뀐 서비스는 EyeProxy 프록시 설정이 그대로이므로, 지우기 전에 현재 활성 서비스의 127.0.0.1 프록시를 끈다
    /// (실패하면 백업을 남겨 다음에 다시 시도한다).
    @discardableResult
    private func dropOrphanedBackup(ownPort: Int) async throws -> Bool {
        guard let b = pendingRestore(),
              let order = try? await Shell.run(Self.networksetup, ["-listnetworkserviceorder"]), order.status == 0,
              SystemProxyCommands.isOrphaned(b, serviceOrder: order.stdout) else { return false }
        if let svc = try? await activeService() {
            try await apply(SystemProxyCommands.turnOffOwn(service: svc, http: readProxy("-getwebproxy", svc), https: readProxy("-getsecurewebproxy", svc), port: ownPort))
        }
        try? FileManager.default.removeItem(at: backupURL)
        return true
    }

    private func readProxy(_ action: String, _ svc: String) async throws -> (enabled: Bool, host: String, port: Int) {
        let r = try await Shell.run(Self.networksetup, [action, svc])
        guard r.status == 0 else { throw SystemProxyError.commandFailed(action) }
        return SystemProxyCommands.parseGetWebProxy(r.stdout)
    }

    public func enable(host: String, port: Int, bypass: [String]) async throws {
        try await dropOrphanedBackup(ownPort: port)
        let svc = try await activeService()
        // 다른 서비스에 남은 EyeProxy 프록시를 되돌리고 백업을 지워야 현재 서비스의 원본을 새로 백업할 수 있다.
        let stale = SystemProxyCommands.restoreStale(pendingRestore(), currentService: svc)
        if !stale.isEmpty {
            try await apply(stale)
            try FileManager.default.removeItem(at: backupURL)
        }
        if pendingRestore() == nil {  // 기존 백업(원본 설정)은 절대 덮어쓰지 않는다.
            func read(_ a: String) async throws -> String {
                let r = try await Shell.run(Self.networksetup, [a, svc])
                guard r.status == 0 else { throw SystemProxyError.commandFailed(a) }
                return r.stdout
            }
            let http = SystemProxyCommands.parseGetWebProxy(try await read("-getwebproxy"))
            let https = SystemProxyCommands.parseGetWebProxy(try await read("-getsecurewebproxy"))
            // 127.0.0.1이 이미 켜져 있으면 EyeProxy 잔여물(백업을 잃음)이다. 원본으로 기록하지 말고 끈 뒤 꺼짐으로 기록한다.
            try await apply(SystemProxyCommands.turnOffOwn(service: svc, http: http, https: https, port: port))
            let (http0, https0) = (SystemProxyCommands.originalProxy(http, ownPort: port), SystemProxyCommands.originalProxy(https, ownPort: port))
            let by = try await read("-getproxybypassdomains")
                .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("There aren't any") }
            try saveBackupIfAbsent(SystemProxyBackup(service: svc, httpEnabled: http0.enabled, httpHost: http0.host, httpPort: http0.port,
                                                     httpsEnabled: https0.enabled, httpsHost: https0.host, httpsPort: https0.port, bypass: by))
        }
        try await apply(SystemProxyCommands.enable(service: svc, host: host, port: port, bypass: bypass))
    }

    /// 백업이 이미 있으면 그대로 두고 false.
    @discardableResult
    func saveBackupIfAbsent(_ b: SystemProxyBackup) throws -> Bool {
        guard pendingRestore() == nil else { return false }
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(b).write(to: backupURL, options: .atomic)
        return true
    }

    /// ownPort: EyeProxy의 포트. 백업이 없을 때 127.0.0.1:ownPort 프록시만 끈다(사용자의 다른 프록시는 건드리지 않는다).
    public func disable(ownPort: Int) async throws {
        // 서비스가 사라졌으면 되돌릴 곳도 없다. 다른(현재) 서비스의 사용자 프록시를 끄지 않는다.
        if try await dropOrphanedBackup(ownPort: ownPort) { return }
        if let b = pendingRestore() {
            try await apply(SystemProxyCommands.restore(b))
        } else {
            let svc = try await activeService()
            try await apply(SystemProxyCommands.turnOffOwn(service: svc, http: readProxy("-getwebproxy", svc),
                                                           https: readProxy("-getsecurewebproxy", svc), port: ownPort))
        }
        try? FileManager.default.removeItem(at: backupURL)
    }

    public func pendingRestore() -> SystemProxyBackup? {
        (try? Data(contentsOf: backupURL)).flatMap { try? JSONDecoder().decode(SystemProxyBackup.self, from: $0) }
    }

    /// 일반 권한으로 실행, 하나라도 실패하면 전체를 관리자 권한 스크립트로 1회 재시도.
    private func apply(_ cmds: [[String]]) async throws {
        var failed = false
        for c in cmds where try await Shell.run(Self.networksetup, c).status != 0 { failed = true; break }
        guard failed else { return }
        let quote = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = cmds.map { ([Self.networksetup] + $0).map(quote).joined(separator: " ") }.joined(separator: "; ")
        do { _ = try await PrivilegedShell.run(script) }
        catch ShellError.privilegedFailed(let stderr) { throw SystemProxyError.commandFailed(stderr) }  // 취소 시 "User canceled. (-128)"
        catch { throw SystemProxyError.commandFailed(error.localizedDescription) }
    }
}
