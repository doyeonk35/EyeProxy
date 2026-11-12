import Foundation
import Testing
import EyeProxyCore
@testable import EyeProxyKit

@Test @MainActor func registryTracksDevicesAndCounts() throws {
    let r = DeviceRegistry(storageURL: nil)
    r.observe(.requestStarted(.fixture(client: "192.168.0.21", decrypted: true)))
    r.observe(.requestStarted(.fixture(client: "192.168.0.21", decrypted: false)))
    r.observe(.requestStarted(.fixture(client: "127.0.0.1", decrypted: false)))
    r.observe(.connectionLog(.init(id: .init(), date: .now, clientAddress: "192.168.0.21", host: "h", port: 443, message: "기기가 Prog 인증서를 신뢰하지 않습니다")))
    let tv = try #require(r.devices.first { $0.address == "192.168.0.21" })
    #expect(tv.flowCount == 2 && tv.decryptedCount == 1 && tv.tlsFailureCount == 1 && tv.kind == .unknown)
    #expect(r.devices.first { $0.address == "127.0.0.1" }?.kind == .thisMac)
    #expect(r.devices.first { $0.address == "127.0.0.1" }?.displayName == "이 Mac")
    r.rename("192.168.0.21", name: "거실 Apple TV", kind: .appleTV)
    let renamed = try #require(r.devices.first { $0.address == "192.168.0.21" })
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
    r.observe(.requestStarted(.fixture(client: "192.168.0.21", decrypted: true)))
    r.rename("192.168.0.21", name: "TV", kind: .appleTV)
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
    r.rename("192.0.2.10", name: "내 기기", kind: .unknown)
    #expect(r.applyDiscovered(.init(address: "192.0.2.10", name: "거실 Apple TV", kind: nil)))
    #expect(r.devices.first?.displayName == "내 기기")
    r.rename("192.0.2.10", name: nil, kind: .unknown)
    #expect(r.devices.first?.displayName == "거실 Apple TV")
}

@Test @MainActor func autoKindOnlyFillsUnknown() throws {
    let r = DeviceRegistry(storageURL: nil)
    r.observe(.requestStarted(.fixture(client: "192.0.2.11", decrypted: false)))
    r.observe(.requestStarted(.fixture(client: "192.0.2.12", decrypted: false)))
    r.rename("192.0.2.11", name: nil, kind: .iPad)
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
