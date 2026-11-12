import EyeProxyCore
import Foundation
import Observation

public struct DiscoveredDevice: Equatable, Sendable {
    public var address: String
    public var name: String
    public var kind: DeviceKind?
    public init(address: String, name: String, kind: DeviceKind?) {
        self.address = address
        self.name = name
        self.kind = kind
    }
}

public enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case thisMac, appleTV, iPhone, iPad, androidTV, googleTV, androidPhone, unknown

    /// 모르는 값은 `.unknown`으로 읽는다(옛·새 앱이 같은 파일을 쓴다).
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DeviceKind(rawValue: raw) ?? .unknown
    }

    /// 옛 앱(1.3.0)이 읽을 수 있는 `kind` 값.
    public var legacy: DeviceKind {
        switch self {
        case .androidTV, .googleTV, .androidPhone: .unknown
        default: self
        }
    }
}

public struct Device: Identifiable, Codable, Equatable, Sendable {
    public var id: String { address }
    public let address: String
    public var name: String?
    /// Bonjour 광고에서 찾은 이름. 직접 붙인 `name`이 없을 때만 보인다.
    public var autoName: String?
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

    private enum CodingKeys: String, CodingKey {
        case address, name, autoName, kind, extendedKind, lastSeen, flowCount, decryptedCount, tlsFailureCount
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decode(String.self, forKey: .address)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        autoName = try c.decodeIfPresent(String.self, forKey: .autoName)
        let legacyKind = try c.decodeIfPresent(DeviceKind.self, forKey: .kind) ?? .unknown
        kind = try c.decodeIfPresent(DeviceKind.self, forKey: .extendedKind) ?? legacyKind
        lastSeen = try c.decode(Date.self, forKey: .lastSeen)
        flowCount = try c.decodeIfPresent(Int.self, forKey: .flowCount) ?? 0
        decryptedCount = try c.decodeIfPresent(Int.self, forKey: .decryptedCount) ?? 0
        tlsFailureCount = try c.decodeIfPresent(Int.self, forKey: .tlsFailureCount) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(address, forKey: .address)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(autoName, forKey: .autoName)
        try c.encode(kind.legacy, forKey: .kind)
        if kind != kind.legacy { try c.encode(kind, forKey: .extendedKind) }
        try c.encode(lastSeen, forKey: .lastSeen)
        try c.encode(flowCount, forKey: .flowCount)
        try c.encode(decryptedCount, forKey: .decryptedCount)
        try c.encode(tlsFailureCount, forKey: .tlsFailureCount)
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let autoName, !autoName.isEmpty { return autoName }
        return kind == .thisMac ? "이 Mac" : address
    }
}

@Observable @MainActor
public final class DeviceRegistry {
    public private(set) var devices: [Device] = []
    @ObservationIgnored private var storageURL: URL?
    /// 트래픽보다 먼저 온 광고를 기억해 둔다(저장하지 않는다).
    @ObservationIgnored private var discovered: [String: DiscoveredDevice] = [:]

    public init(storageURL: URL?) {
        self.storageURL = storageURL
        guard let storageURL, let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            devices = try decoder.decode([Device].self, from: data)
        } catch {
            // 손상된 파일을 덮어쓰지 않도록 옆으로 치워 둔다. 실패하면 save()를 막아 원본을 보존한다.
            let fm = FileManager.default
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            let base = storageURL.deletingPathExtension()
            let first = base.appendingPathExtension("corrupt-\(stamp).json")
            let second = base.appendingPathExtension("corrupt-\(stamp)-\(UUID().uuidString).json")
            if (try? fm.moveItem(at: storageURL, to: first)) == nil, (try? fm.moveItem(at: storageURL, to: second)) == nil {
                self.storageURL = nil
            }
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

    /// 광고를 기억하고, 그 주소의 기기가 있으면 자동 이름·종류를 붙인다. 기기 정보가 바뀌면 true.
    @discardableResult
    public func applyDiscovered(_ found: DiscoveredDevice) -> Bool {
        // 이 Mac(루프백)은 "이 Mac"으로 둔다.
        guard !FlowFilter.isLoopback(found.address) else { return false }
        discovered[found.address] = found
        guard let i = devices.firstIndex(where: { $0.address == found.address }) else { return false }
        return applyDiscovery(found, to: &devices[i])
    }

    private func applyDiscovery(_ found: DiscoveredDevice, to device: inout Device) -> Bool {
        let before = device
        device.autoName = found.name
        if device.kind == .unknown, let kind = found.kind { device.kind = kind }
        return device != before
    }

    /// 다른 기기에서 온 트래픽이 있었는지(기기 찾기 시작 조건, 스펙 §3).
    /// 루프백·주소 없음(`unknown`)·이 Mac의 주소는 빼고, 이 Mac의 주소는 후보가 있을 때만 묻는다.
    public func hasRemoteDevice(ownAddresses: () -> [String]) -> Bool {
        let candidates = devices.filter { !FlowFilter.isLoopback($0.address) && !$0.address.isEmpty && $0.address != "unknown" }
        guard !candidates.isEmpty else { return false }
        let own = Set(ownAddresses())
        return candidates.contains { !own.contains($0.address) }
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
            var device = Device(address: address, kind: isLocal ? .thisMac : .unknown, lastSeen: date)
            if let found = discovered[address] { _ = applyDiscovery(found, to: &device) }
            devices.append(device)
            return devices.count - 1
        }()
        devices[i].lastSeen = max(devices[i].lastSeen, date)
        change(&devices[i])
        devices.sort { $0.lastSeen > $1.lastSeen }
    }
}
