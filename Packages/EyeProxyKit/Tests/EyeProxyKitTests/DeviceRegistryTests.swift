import Foundation
import Testing
import EyeProxyCore
@testable import EyeProxyKit

@Test @MainActor func registryTracksDevicesAndCounts() throws {
    let r = DeviceRegistry(storageURL: nil)
    r.observe(.requestStarted(.fixture(client: "192.168.0.21", decrypted: true)))
    r.observe(.requestStarted(.fixture(client: "192.168.0.21", decrypted: false)))
    r.observe(.requestStarted(.fixture(client: "127.0.0.1", decrypted: false)))
    r.observe(.connectionLog(.init(id: .init(), date: .now, clientAddress: "192.168.0.21", host: "h", port: 443, message: "기기가 EyeProxy 인증서를 신뢰하지 않습니다")))
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
