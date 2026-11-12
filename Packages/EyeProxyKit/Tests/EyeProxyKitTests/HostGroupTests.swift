import Foundation
import Testing
@testable import EyeProxyKit

@Test func groupMatchesDomainPatternOrApp() {
    let m = HostGroupMatcher(HostGroup(name: "g", hostPatterns: ["*.example.com"], apps: ["com.example.app"]))
    #expect(m.matches(host: "api.example.com", process: nil))
    #expect(m.matches(host: "other.net", process: "com.example.app"))
    #expect(!m.matches(host: "other.net", process: nil))
    #expect(!m.matches(host: "example.com", process: nil))
}

@Test func groupDisplayNameFallsBack() {
    #expect(HostGroup(name: " ", hostPatterns: ["api.example.com", "*.example.org"], apps: []).displayName == "api.example.com 외 1")
    #expect(HostGroup(name: "우리 서버", hostPatterns: ["api.example.com"], apps: []).displayName == "우리 서버")
}

@Test func sidebarItemCodableRoundTrip() throws {
    let g = HostGroup(name: "g", hostPatterns: ["*.example.com"], apps: ["com.example.app"])
    let items: [SidebarItem] = [.allFlows, .host("api.example.com"), .scope(FlowScope(device: "192.0.2.10", host: "api.example.com")),
                                .path(host: "api.example.com", prefix: "/v1"), .group(g)]
    let back = try JSONDecoder().decode([SidebarItem].self, from: JSONEncoder().encode(items))
    #expect(back == items)
}
