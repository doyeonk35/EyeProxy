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
            if !(try await Shell.run("/usr/sbin/ipconfig", ["getifaddr", s.device]).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty { return s.name }
        }
        throw SystemProxyError.noActiveService
    }

    public func enable(host: String, port: Int, bypass: [String]) async throws {
        let svc = try await activeService()
        if pendingRestore() == nil {  // 기존 백업(원본 설정)은 절대 덮어쓰지 않는다.
            func read(_ a: String) async throws -> String {
                let r = try await Shell.run(Self.networksetup, [a, svc])
                guard r.status == 0 else { throw SystemProxyError.commandFailed(a) }
                return r.stdout
            }
            let http = SystemProxyCommands.parseGetWebProxy(try await read("-getwebproxy"))
            let https = SystemProxyCommands.parseGetWebProxy(try await read("-getsecurewebproxy"))
            let by = try await read("-getproxybypassdomains")
                .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("There aren't any") }
            try saveBackupIfAbsent(SystemProxyBackup(service: svc, httpEnabled: http.enabled, httpHost: http.host, httpPort: http.port,
                                                     httpsEnabled: https.enabled, httpsHost: https.host, httpsPort: https.port, bypass: by))
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

    public func disable() async throws {
        if let b = pendingRestore() {
            try await apply(SystemProxyCommands.restore(b))
        } else {
            let svc = try await activeService()
            try await apply([["-setwebproxystate", svc, "off"], ["-setsecurewebproxystate", svc, "off"]])
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
        catch { throw SystemProxyError.commandFailed("\(error)") }
    }
}
