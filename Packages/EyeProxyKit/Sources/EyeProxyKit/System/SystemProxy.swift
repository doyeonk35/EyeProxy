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
        if b.httpEnabled { c += [["-setwebproxy", b.service, b.httpHost, "\(b.httpPort)"], ["-setwebproxystate", b.service, "on"]] }
        else { c.append(["-setwebproxystate", b.service, "off"]) }
        if b.httpsEnabled { c += [["-setsecurewebproxy", b.service, b.httpsHost, "\(b.httpsPort)"], ["-setsecurewebproxystate", b.service, "on"]] }
        else { c.append(["-setsecurewebproxystate", b.service, "off"]) }
        c.append(bypassCmd(b.service, b.bypass))
        return c
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
        guard let iface = route.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.hasPrefix("interface:") })
            .map({ $0.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces) })
        else { throw SystemProxyError.noActiveService }
        let order = try await Shell.run(Self.networksetup, ["-listnetworkserviceorder"]).stdout
        var name: String?
        for raw in order.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("("), let r = line.range(of: ") "), line[line.index(after: line.startIndex)...].first?.isNumber == true {
                name = String(line[r.upperBound...])
            } else if line.contains("Device: \(iface)"), let name { return name }
        }
        throw SystemProxyError.noActiveService
    }

    public func enable(host: String, port: Int, bypass: [String]) async throws {
        let svc = try await activeService()
        let http = SystemProxyCommands.parseGetWebProxy(try await Shell.run(Self.networksetup, ["-getwebproxy", svc]).stdout)
        let https = SystemProxyCommands.parseGetWebProxy(try await Shell.run(Self.networksetup, ["-getsecurewebproxy", svc]).stdout)
        let by = try await Shell.run(Self.networksetup, ["-getproxybypassdomains", svc]).stdout
            .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("There aren't any") }
        let backup = SystemProxyBackup(service: svc, httpEnabled: http.enabled, httpHost: http.host, httpPort: http.port,
                                       httpsEnabled: https.enabled, httpsHost: https.host, httpsPort: https.port, bypass: by)
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(backup).write(to: backupURL, options: .atomic)
        try await apply(SystemProxyCommands.enable(service: svc, host: host, port: port, bypass: bypass))
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
