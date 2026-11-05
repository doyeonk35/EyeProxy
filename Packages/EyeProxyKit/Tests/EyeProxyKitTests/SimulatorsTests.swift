import Foundation
import Testing
@testable import EyeProxyKit

@Test func parsesBootedSimulators() throws {
    let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.tvOS-18-1":[{"udid":"U1","name":"Apple TV 4K (3rd generation)","state":"Booted"}],"com.apple.CoreSimulator.SimRuntime.iOS-18-1":[{"udid":"U2","name":"iPhone 16","state":"Booted"}]}}"#
    let d = try Simulators.parseBooted(json: Data(json.utf8))
    #expect(d.map(\.udid).sorted() == ["U1", "U2"]); #expect(d.first { $0.udid == "U1" }?.runtime == "tvOS 18.1")
}
