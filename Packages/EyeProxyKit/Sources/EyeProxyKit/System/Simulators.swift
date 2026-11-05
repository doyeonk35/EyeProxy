import Foundation

public struct SimulatorDevice: Identifiable, Equatable, Sendable {
    public let udid: String
    public let name: String
    public let runtime: String  // "iOS 18.1" | "tvOS 18.1"
    public var id: String { udid }
    public init(udid: String, name: String, runtime: String) { self.udid = udid; self.name = name; self.runtime = runtime }
}

public enum SimulatorsError: Error { case failed(String) }

public enum Simulators {
    private struct Raw: Decodable {
        struct Dev: Decodable { let udid: String; let name: String; let state: String; let isAvailable: Bool? }
        let devices: [String: [Dev]]
    }

    public static func parseBooted(json: Data) throws -> [SimulatorDevice] {
        let raw = try JSONDecoder().decode(Raw.self, from: json)
        return raw.devices.flatMap { key, devs in
            let rt = runtimeName(key)
            return devs.filter { $0.state == "Booted" && $0.isAvailable != false }
                .map { SimulatorDevice(udid: $0.udid, name: $0.name, runtime: rt) }
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.tvOS-18-1" → "tvOS 18.1"
    private static func runtimeName(_ key: String) -> String {
        let s = key.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
        guard let i = s.firstIndex(of: "-") else { return s }
        return s[..<i] + " " + s[s.index(after: i)...].replacingOccurrences(of: "-", with: ".")
    }

    public static func listBooted() async throws -> [SimulatorDevice] {
        let r = try await Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "booted", "-j"])
        guard r.status == 0 else { throw SimulatorsError.failed(r.stderr) }
        return try parseBooted(json: Data(r.stdout.utf8))
    }

    public static func installRootCert(udid: String, pemURL: URL) async throws {
        let r = try await Shell.run("/usr/bin/xcrun", ["simctl", "keychain", udid, "add-root-cert", pemURL.path])
        guard r.status == 0 else { throw SimulatorsError.failed(r.stderr) }
    }
}
