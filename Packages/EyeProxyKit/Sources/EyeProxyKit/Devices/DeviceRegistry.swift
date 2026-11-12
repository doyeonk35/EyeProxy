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
    /// 같은 주소에 기록이 여럿이어도 겹치지 않는다(MAC 규칙, 스펙 §4.3.1).
    public var id: String { mac ?? address }
    /// MAC이 같은 기록이 새 주소에서 보이면 바뀐다.
    public var address: String
    /// ARP 표에서 읽은 MAC. 같은 L2 망이 아니면 없다.
    public var mac: String?
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
        case address, mac, name, autoName, kind, extendedKind, lastSeen, flowCount, decryptedCount, tlsFailureCount
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decode(String.self, forKey: .address)
        mac = try c.decodeIfPresent(String.self, forKey: .mac)
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
        try c.encodeIfPresent(mac, forKey: .mac)  // 새 키: 1.3.0은 모르는 키를 무시한다
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
    @ObservationIgnored private let macLookup: @MainActor (String) -> String?
    /// 주소마다 마지막으로 ARP 표를 읽은 시각(이벤트 날짜, 저장하지 않는다).
    @ObservationIgnored private var macCheckedAt: [String: Date] = [:]
    public static let macCheckInterval: TimeInterval = 60

    public init(storageURL: URL?, macLookup: @escaping @MainActor (String) -> String? = { _ in nil }) {
        self.storageURL = storageURL
        self.macLookup = macLookup
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

    /// 그 주소의 lastSeen이 가장 늦은 기록(그 주소를 대표한다). `devices`는 lastSeen 내림차순이다.
    public func device(at address: String) -> Device? {
        devices.first { $0.address == address }
    }

    /// 그 주소를 대표하는 기록인지. 아니면 "이전" 기록이다.
    public func isCurrent(_ device: Device) -> Bool {
        self.device(at: device.address)?.id == device.id
    }

    public func rename(id: String, name: String?, kind: DeviceKind) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
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

    /// 이 Mac의 LAN 주소 기록에 종류(알 수 없음일 때만)와 컴퓨터 이름을 넣는다(스펙 §4.3.2). 바뀌면 true.
    @discardableResult
    public func markThisMac(_ address: String, name: String?) -> Bool {
        guard !FlowFilter.isLoopback(address), let i = devices.firstIndex(where: { $0.address == address }) else { return false }
        let before = devices[i]
        if devices[i].kind == .unknown { devices[i].kind = .thisMac }
        if let name, !name.isEmpty { devices[i].autoName = name }
        return devices[i] != before
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
        var current = devices.firstIndex { $0.address == address }
        if let mac = lookUpMAC(address, at: date) {
            if let i = current, devices[i].mac == mac {
                // 1. 그대로 둔다
            } else if let j = devices.firstIndex(where: { $0.mac == mac }) {
                // 2. 그 MAC의 기록(다른 주소, 또는 같은 주소의 "이전" 기록)이 이 주소로 옮겨 온다
                devices[j].address = address
                devices[j].lastSeen = date
                current = j
            } else if let i = current, devices[i].mac == nil {
                devices[i].mac = mac  // 3. 옛 기록이 MAC을 배운다
            } else {
                current = append(address, mac: mac, at: date)  // 4. 이 주소를 다른 기기가 받았다
            }
        }
        let i = current ?? append(address, mac: nil, at: date)
        devices[i].lastSeen = max(devices[i].lastSeen, date)
        change(&devices[i])
        devices.sort { $0.lastSeen > $1.lastSeen }
    }

    private func append(_ address: String, mac: String?, at date: Date) -> Int {
        let isLocal = address == "127.0.0.1" || address == "::1"
        var device = Device(address: address, kind: isLocal ? .thisMac : .unknown, lastSeen: date)
        device.mac = mac
        if let found = discovered[address] { _ = applyDiscovery(found, to: &device) }
        devices.append(device)
        return devices.count - 1
    }

    /// 루프백·주소 없음이 아니고, 그 주소를 `macCheckInterval` 안에 읽지 않았을 때만 ARP 표를 읽는다.
    private func lookUpMAC(_ address: String, at date: Date) -> String? {
        guard !FlowFilter.isLoopback(address), !address.isEmpty, address != "unknown" else { return nil }
        if let last = macCheckedAt[address], date.timeIntervalSince(last) < Self.macCheckInterval { return nil }
        macCheckedAt[address] = date
        return macLookup(address)
    }
}
