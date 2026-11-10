import Foundation
import Testing
@testable import EyeProxyKit

@Test func parsesBootedSimulators() throws {
    let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.tvOS-18-1":[{"udid":"U1","name":"Apple TV 4K (3rd generation)","state":"Booted"}],"com.apple.CoreSimulator.SimRuntime.iOS-18-1":[{"udid":"U2","name":"iPhone 16","state":"Booted"}]}}"#
    let d = try Simulators.parseBooted(json: Data(json.utf8))
    #expect(d.map(\.udid).sorted() == ["U1", "U2"]); #expect(d.first { $0.udid == "U1" }?.runtime == "tvOS 18.1")
}

/// Advanced ▸ Hide Unnecessary Apple Requests from iOS Simulators: 시뮬레이터 클라이언트의 `*.apple.com`·`*.icloud.com`만.
@Test func appleNoiseHostsDetectedOnlyForSimulators() {
    for host in ["gateway.icloud.com", "init.ess.apple.com", "APPLE.COM", "icloud.com", "p32-Contacts.iCloud.com"] {
        #expect(SimulatorNoise.isAppleNoise(host: host, clientIsSimulator: true), "\(host)")
        #expect(!SimulatorNoise.isAppleNoise(host: host, clientIsSimulator: false), "\(host)")
    }
    for host in ["example.com", "notapple.com", "apple.com.example.com", "myicloud.com", ""] {
        #expect(!SimulatorNoise.isAppleNoise(host: host, clientIsSimulator: true), "\(host)")
    }
}
