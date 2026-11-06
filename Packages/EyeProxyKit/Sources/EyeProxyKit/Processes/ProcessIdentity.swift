import Foundation

public struct SimulatorRef: Codable, Hashable, Sendable {
    public let udid: String
    public let appName: String
}

/// 로컬 클라이언트 소켓을 연 프로세스(또는 그 책임 앱).
public struct ProcessIdentity: Codable, Hashable, Sendable {
    public let pid: Int32
    public let name: String
    public let path: String?
    public let simulator: SimulatorRef?

    public init(pid: Int32, path: String?) {
        self.pid = pid
        self.path = path
        let sim = path.flatMap(Self.simulatorRef(fromPath:))
        simulator = sim
        name = path.map(Self.name(fromPath:)) ?? "pid \(pid)"
    }

    public var groupKey: String {
        if let simulator { return "sim:\(simulator.udid):\(simulator.appName)" }
        return path ?? name
    }

    /// runtimes: udid → "tvOS 18.1".
    public func displayName(runtimes: [String: String]) -> String {
        guard let simulator else { return name }
        let platform = runtimes[simulator.udid]?.split(separator: " ").first.map(String.init)
        return "\(simulator.appName) (\(platform.map { $0 + " " } ?? "")시뮬레이터)"
    }

    static func name(fromPath path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        if let app = parts.first(where: { $0.hasSuffix(".app") }) { return String(app.dropLast(4)) }
        return parts.last ?? path
    }

    static func simulatorRef(fromPath path: String) -> SimulatorRef? {
        let parts = path.split(separator: "/").map(String.init)
        guard let i = parts.firstIndex(of: "Devices"), i > 0, parts[i - 1] == "CoreSimulator", i + 1 < parts.count else { return nil }
        return SimulatorRef(udid: parts[i + 1], appName: name(fromPath: path))
    }
}
