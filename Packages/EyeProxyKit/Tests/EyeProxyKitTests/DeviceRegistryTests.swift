import Foundation
import Testing
import EyeProxyCore
@testable import EyeProxyKit

@Test @MainActor func registryTracksDevicesAndCounts() throws {
    let r = DeviceRegistry(storageURL: nil)
    r.observe(.requestStarted(.fixture(client: "192.0.2.21", decrypted: true)))
    r.observe(.requestStarted(.fixture(client: "192.0.2.21", decrypted: false)))
    r.observe(.requestStarted(.fixture(client: "127.0.0.1", decrypted: false)))
    r.observe(.connectionLog(.init(id: .init(), date: .now, clientAddress: "192.0.2.21", host: "h", port: 443, message: "기기가 Prog 인증서를 신뢰하지 않습니다")))
    let tv = try #require(r.devices.first { $0.address == "192.0.2.21" })
    #expect(tv.flowCount == 2 && tv.decryptedCount == 1 && tv.tlsFailureCount == 1 && tv.kind == .unknown)
    #expect(r.devices.first { $0.address == "127.0.0.1" }?.kind == .thisMac)
    #expect(r.devices.first { $0.address == "127.0.0.1" }?.displayName == "이 Mac")
    r.rename(id: "192.0.2.21", name: "거실 Apple TV", kind: .appleTV)
    let renamed = try #require(r.devices.first { $0.address == "192.0.2.21" })
    #expect(renamed.displayName == "거실 Apple TV" && renamed.flowCount == 2)
}

@Test @MainActor func registrySortsByLastSeenDescending() {
    let r = DeviceRegistry(storageURL: nil)
    r.observe(.requestStarted(.fixture(client: "a", decrypted: false)))
    r.observe(.requestStarted(.fixture(client: "b", decrypted: false)))
    #expect(r.devices.map(\.address) == ["b", "a"])
    r.observe(.requestStarted(.fixture(client: "a", decrypted: false)))
    #expect(r.devices.map(\.address) == ["a", "b"])
}

@Test @MainActor func registryPersists() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let r = DeviceRegistry(storageURL: url)
    r.observe(.requestStarted(.fixture(client: "192.0.2.21", decrypted: true)))
    r.rename(id: "192.0.2.21", name: "TV", kind: .appleTV)
    try r.save()
    let loaded = DeviceRegistry(storageURL: url).devices
    #expect(loaded.count == 1)
    var expected = r.devices[0]
    expected.lastSeen = loaded[0].lastSeen  // iso8601은 초 미만을 버린다
    #expect(loaded[0] == expected && abs(loaded[0].lastSeen.timeIntervalSince(r.devices[0].lastSeen)) < 1)
}

@Test @MainActor func corruptFileIsMovedAsideNotOverwritten() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("devices.json")
    try Data("{not json".utf8).write(to: url)
    let r = DeviceRegistry(storageURL: url)
    #expect(r.devices.isEmpty)
    try r.save()
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    let corrupt = try #require(names.first { $0.hasPrefix("devices.corrupt-") && $0.hasSuffix(".json") })
    #expect(try Data(contentsOf: dir.appendingPathComponent(corrupt)) == Data("{not json".utf8))
}

@Test @MainActor func autoNameNeverOverridesManualName() throws {
    let r = DeviceRegistry(storageURL: nil)
    r.observe(.requestStarted(.fixture(client: "192.0.2.10", decrypted: false)))
    r.rename(id: "192.0.2.10", name: "내 기기", kind: .unknown)
    #expect(r.applyDiscovered(.init(address: "192.0.2.10", name: "거실 Apple TV", kind: nil)))
    #expect(r.devices.first?.displayName == "내 기기")
    r.rename(id: "192.0.2.10", name: nil, kind: .unknown)
    #expect(r.devices.first?.displayName == "거실 Apple TV")
}

@Test @MainActor func autoKindOnlyFillsUnknown() throws {
    let r = DeviceRegistry(storageURL: nil)
    r.observe(.requestStarted(.fixture(client: "192.0.2.11", decrypted: false)))
    r.observe(.requestStarted(.fixture(client: "192.0.2.12", decrypted: false)))
    r.rename(id: "192.0.2.11", name: nil, kind: .iPad)
    r.applyDiscovered(.init(address: "192.0.2.11", name: "a", kind: .appleTV))
    r.applyDiscovered(.init(address: "192.0.2.12", name: "b", kind: .appleTV))
    #expect(r.devices.first { $0.address == "192.0.2.11" }?.kind == .iPad)
    #expect(r.devices.first { $0.address == "192.0.2.12" }?.kind == .appleTV)
}

@Test @MainActor func discoveryBeforeTrafficIsApplied() throws {
    let r = DeviceRegistry(storageURL: nil)
    #expect(r.applyDiscovered(.init(address: "192.0.2.20", name: "안방 TV", kind: nil)) == false)
    r.observe(.requestStarted(.fixture(client: "192.0.2.20", decrypted: false)))
    #expect(r.devices.first?.displayName == "안방 TV")
}

@Test @MainActor func autoNamePersistsAndOldFileLoads() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "devices-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let r = DeviceRegistry(storageURL: url)
    r.observe(.requestStarted(.fixture(client: "192.0.2.30", decrypted: false)))
    r.applyDiscovered(.init(address: "192.0.2.30", name: "거실 Apple TV", kind: nil))
    try r.save()
    #expect(DeviceRegistry(storageURL: url).devices.first?.autoName == "거실 Apple TV")
    let old = #"[{"address":"192.0.2.31","kind":"unknown","lastSeen":"2026-01-01T00:00:00Z","flowCount":1,"decryptedCount":0,"tlsFailureCount":0}]"#
    try old.write(to: url, atomically: true, encoding: .utf8)
    #expect(DeviceRegistry(storageURL: url).devices.first?.autoName == nil)
}

@Test @MainActor func loopbackDiscoveryKeepsThisMacName() throws {
    let r = DeviceRegistry(storageURL: nil)
    r.observe(.requestStarted(.fixture(client: "127.0.0.1", decrypted: false)))
    #expect(r.applyDiscovered(.init(address: "127.0.0.1", name: "테스트 Mac", kind: nil)) == false)
    #expect(r.devices.first?.displayName == "이 Mac")
}

@Test @MainActor func remoteDeviceExcludesUnknownAndOwnAddresses() throws {
    let r = DeviceRegistry(storageURL: nil)
    var asked = false
    r.observe(.requestStarted(.fixture(client: "127.0.0.1", decrypted: false)))
    #expect(r.hasRemoteDevice(ownAddresses: { asked = true; return [] }) == false)
    #expect(asked == false)
    r.observe(.requestStarted(.fixture(client: "unknown", decrypted: false)))
    r.observe(.requestStarted(.fixture(client: "192.0.2.5", decrypted: false)))
    #expect(r.hasRemoteDevice(ownAddresses: { ["192.0.2.5"] }) == false)
    r.observe(.requestStarted(.fixture(client: "192.0.2.6", decrypted: false)))
    #expect(r.hasRemoteDevice(ownAddresses: { ["192.0.2.5"] }))
}

private func tempDevicesURL() throws -> (dir: URL, url: URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (dir, dir.appendingPathComponent("devices.json"))
}

@Test @MainActor func androidKindIsWrittenCompatibly() throws {
    let (dir, url) = try tempDevicesURL()
    defer { try? FileManager.default.removeItem(at: dir) }
    let r = DeviceRegistry(storageURL: url)
    r.observe(.requestStarted(.fixture(client: "192.0.2.30", decrypted: false)))
    r.rename(id: "192.0.2.30", name: nil, kind: .googleTV)
    try r.save()
    let objects = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    #expect(objects[0]["kind"] as? String == "unknown")
    #expect(objects[0]["extendedKind"] as? String == "googleTV")
    #expect(DeviceRegistry(storageURL: url).devices.first?.kind == .googleTV)
}

@Test @MainActor func legacyKindsHaveNoExtendedKey() throws {
    let (dir, url) = try tempDevicesURL()
    defer { try? FileManager.default.removeItem(at: dir) }
    let r = DeviceRegistry(storageURL: url)
    r.observe(.requestStarted(.fixture(client: "192.0.2.32", decrypted: false)))
    r.rename(id: "192.0.2.32", name: nil, kind: .appleTV)
    try r.save()
    let objects = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    #expect(objects[0]["extendedKind"] == nil)
    #expect(objects[0]["kind"] as? String == "appleTV")
}

@Test @MainActor func unknownKindValueDoesNotCorruptFile() throws {
    let (dir, url) = try tempDevicesURL()
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data(#"[{"address":"192.0.2.31","kind":"smartFridge","lastSeen":"2026-11-13T00:00:00Z","flowCount":1,"decryptedCount":0,"tlsFailureCount":0}]"#.utf8).write(to: url)
    let r = DeviceRegistry(storageURL: url)
    #expect(r.devices.count == 1 && r.devices[0].kind == .unknown)
    #expect(try !FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.contains("corrupt") })
}

// MARK: - MAC으로 알아보기

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let m1 = "00:00:5e:00:53:01"
private let m2 = "00:00:5e:00:53:02"

@MainActor private func request(_ r: DeviceRegistry, _ client: String, at date: Date) {
    r.observe(.requestStarted(Flow(id: FlowID(), clientAddress: client, startedAt: date,
                                   request: FlowRequest(method: "GET", scheme: "https", host: "example.com", port: 443, path: "/", headers: [], body: Data()))))
}

/// 테스트의 사전을 읽는 ARP 표 대역.
@MainActor private final class FakeARP {
    var table: [String: String] = [:]
    var calls = 0
    func lookup(_ address: String) -> String? { calls += 1; return table[address] }
}

@Test @MainActor func macFollowsDeviceToNewAddress() throws {
    let arp = FakeARP()
    let r = DeviceRegistry(storageURL: nil, macLookup: arp.lookup)
    arp.table = ["192.0.2.20": m1]
    request(r, "192.0.2.20", at: t0)
    r.rename(id: m1, name: "거실 TV", kind: .googleTV)
    arp.table = ["192.0.2.21": m1]
    request(r, "192.0.2.21", at: t0 + 120)
    let moved = try #require(r.device(at: "192.0.2.21"))
    #expect(moved.displayName == "거실 TV" && moved.kind == .googleTV && moved.flowCount == 2)
    #expect(r.devices.count == 1)
    #expect(r.device(at: "192.0.2.20") == nil)
}

@Test @MainActor func reassignedAddressKeepsOldNameAsPrevious() throws {
    let arp = FakeARP()
    let r = DeviceRegistry(storageURL: nil, macLookup: arp.lookup)
    arp.table = ["192.0.2.20": m1]
    request(r, "192.0.2.20", at: t0)
    r.rename(id: m1, name: "거실 TV", kind: .unknown)
    arp.table = ["192.0.2.20": m2]
    request(r, "192.0.2.20", at: t0 + 120)
    let current = try #require(r.device(at: "192.0.2.20"))
    #expect(current.mac == m2 && current.displayName == "192.0.2.20")
    #expect(r.devices.count == 2)
    let previous = try #require(r.devices.first { $0.id == m1 })
    #expect(!r.isCurrent(previous) && previous.name == "거실 TV")
    arp.table = ["192.0.2.22": m1]
    request(r, "192.0.2.22", at: t0 + 240)
    let back = try #require(r.device(at: "192.0.2.22"))
    #expect(back.displayName == "거실 TV" && r.isCurrent(back))
}

/// R1: 한 주소에서 M1→M2→M1이어도 기록 id가 겹치지 않는다.
@Test @MainActor func macReturningToSameAddressKeepsIdsUnique() throws {
    let arp = FakeARP()
    let r = DeviceRegistry(storageURL: nil, macLookup: arp.lookup)
    arp.table = ["192.0.2.20": m1]
    request(r, "192.0.2.20", at: t0)
    r.rename(id: m1, name: "거실 TV", kind: .unknown)
    arp.table = ["192.0.2.20": m2]
    request(r, "192.0.2.20", at: t0 + 120)
    arp.table = ["192.0.2.20": m1]
    request(r, "192.0.2.20", at: t0 + 240)
    #expect(r.devices.count == 2)
    #expect(Set(r.devices.map(\.id)).count == r.devices.count)
    let current = try #require(r.device(at: "192.0.2.20"))
    #expect(current.id == m1 && current.displayName == "거실 TV" && current.flowCount == 2)
}

@Test @MainActor func oldRecordLearnsMAC() throws {
    let (dir, url) = try tempDevicesURL()
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data(#"[{"address":"192.0.2.20","name":"내 기기","kind":"unknown","lastSeen":"2027-01-15T08:00:00Z","flowCount":1,"decryptedCount":0,"tlsFailureCount":0}]"#.utf8).write(to: url)
    let arp = FakeARP()
    let r = DeviceRegistry(storageURL: url, macLookup: arp.lookup)
    arp.table = ["192.0.2.20": m1]
    request(r, "192.0.2.20", at: t0)
    let learned = try #require(r.device(at: "192.0.2.20"))
    #expect(learned.mac == m1 && learned.name == "내 기기")
    arp.table = ["192.0.2.21": m1]
    request(r, "192.0.2.21", at: t0 + 120)
    #expect(r.device(at: "192.0.2.21")?.displayName == "내 기기")
    #expect(r.devices.count == 1)
}

@Test @MainActor func macLookupIsRateLimited() {
    let arp = FakeARP()
    let r = DeviceRegistry(storageURL: nil, macLookup: arp.lookup)
    for offset in [0.0, 10, 30] { request(r, "192.0.2.20", at: t0 + offset) }
    #expect(arp.calls == 1)
    request(r, "192.0.2.20", at: t0 + 61)
    #expect(arp.calls == 2)
    request(r, "127.0.0.1", at: t0 + 62)
    #expect(arp.calls == 2)
}

@Test @MainActor func markThisMacSetsKindAndAutoName() throws {
    let r = DeviceRegistry(storageURL: nil)
    request(r, "192.0.2.5", at: t0)
    #expect(r.markThisMac("192.0.2.5", name: "테스트 Mac"))
    let mac = try #require(r.device(at: "192.0.2.5"))
    #expect(mac.kind == .thisMac && mac.displayName == "테스트 Mac")
    #expect(r.markThisMac("192.0.2.5", name: "테스트 Mac") == false)

    request(r, "192.0.2.6", at: t0)
    r.rename(id: "192.0.2.6", name: "내 Mac", kind: .unknown)
    r.markThisMac("192.0.2.6", name: "테스트 Mac")
    #expect(r.device(at: "192.0.2.6")?.displayName == "내 Mac")

    request(r, "192.0.2.7", at: t0)
    r.rename(id: "192.0.2.7", name: nil, kind: .iPad)
    r.markThisMac("192.0.2.7", name: "테스트 Mac")
    #expect(r.device(at: "192.0.2.7")?.kind == .iPad)

    request(r, "127.0.0.1", at: t0)
    #expect(r.markThisMac("127.0.0.1", name: "테스트 Mac") == false)
}

@Test @MainActor func macPersists() throws {
    let (dir, url) = try tempDevicesURL()
    defer { try? FileManager.default.removeItem(at: dir) }
    let arp = FakeARP()
    arp.table = ["192.0.2.20": m1]
    let r = DeviceRegistry(storageURL: url, macLookup: arp.lookup)
    request(r, "192.0.2.20", at: t0)
    try r.save()
    let objects = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    #expect(objects[0]["mac"] as? String == m1 && objects[0]["address"] as? String == "192.0.2.20")
    #expect(DeviceRegistry(storageURL: url).devices.first?.mac == m1)
    try Data(#"[{"address":"192.0.2.31","kind":"unknown","lastSeen":"2026-11-13T00:00:00Z","flowCount":1,"decryptedCount":0,"tlsFailureCount":0}]"#.utf8).write(to: url)
    let old = DeviceRegistry(storageURL: url).devices
    #expect(old.count == 1 && old[0].mac == nil && old[0].id == "192.0.2.31")
}
