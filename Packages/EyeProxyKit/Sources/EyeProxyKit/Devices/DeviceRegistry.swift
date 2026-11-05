import EyeProxyCore
import Foundation
import Observation

public enum DeviceKind: String, Codable, CaseIterable, Sendable { case thisMac, appleTV, iPhone, iPad, unknown }

public struct Device: Identifiable, Codable, Equatable, Sendable {
    public var id: String { address }
    public let address: String
    public var name: String?
    public var kind: DeviceKind
    public var lastSeen: Date
    public var flowCount: Int
    public var decryptedCount: Int
    public var tlsFailureCount: Int

    public init(address: String, name: String? = nil, kind: DeviceKind, lastSeen: Date, flowCount: Int = 0, decryptedCount: Int = 0, tlsFailureCount: Int = 0) {
        self.address = address
        self.name = name
        self.kind = kind
        self.lastSeen = lastSeen
        self.flowCount = flowCount
        self.decryptedCount = decryptedCount
        self.tlsFailureCount = tlsFailureCount
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return kind == .thisMac ? "이 Mac" : address
    }
}

@Observable @MainActor
public final class DeviceRegistry {
    public private(set) var devices: [Device] = []
    @ObservationIgnored private let storageURL: URL?

    public init(storageURL: URL?) {
        self.storageURL = storageURL
        guard let storageURL, let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            devices = try decoder.decode([Device].self, from: data)
        } catch {
            // 손상된 파일을 덮어쓰지 않도록 옆으로 치워 둔다.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = storageURL.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: storageURL, to: aside)
        }
    }

    public func observe(_ event: FlowEvent) {
        switch event {
        case .requestStarted(let flow):
            update(flow.clientAddress, at: flow.startedAt) {
                $0.flowCount += 1
                if flow.isDecrypted { $0.decryptedCount += 1 }
            }
        case .connectionLog(let entry) where entry.message.contains("신뢰"):
            update(entry.clientAddress, at: entry.date) { $0.tlsFailureCount += 1 }
        default:
            break
        }
    }

    public func rename(_ address: String, name: String?, kind: DeviceKind) {
        guard let i = devices.firstIndex(where: { $0.address == address }) else { return }
        devices[i].name = name
        devices[i].kind = kind
    }

    public func save() throws {
        guard let storageURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(devices).write(to: storageURL, options: .atomic)
    }

    private func update(_ address: String, at date: Date, _ change: (inout Device) -> Void) {
        let i = devices.firstIndex { $0.address == address } ?? {
            let isLocal = address == "127.0.0.1" || address == "::1"
            devices.append(Device(address: address, kind: isLocal ? .thisMac : .unknown, lastSeen: date))
            return devices.count - 1
        }()
        devices[i].lastSeen = max(devices[i].lastSeen, date)
        change(&devices[i])
        devices.sort { $0.lastSeen > $1.lastSeen }
    }
}
