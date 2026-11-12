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

@Test func draftPrefillsFromSidebarSelection() {
    #expect(HostGroup.draft(from: .host("API.example.com")).hostPatterns == ["api.example.com"])
    #expect(HostGroup.draft(from: .path(host: "api.example.com", prefix: "/v1")).hostPatterns == ["api.example.com"])
    let scoped = HostGroup.draft(from: .scope(FlowScope(device: "127.0.0.1", process: "com.example.app", host: "api.example.com")))
    #expect(scoped.hostPatterns == ["api.example.com"] && scoped.apps.isEmpty)
    let app = HostGroup.draft(from: .scope(FlowScope(device: "127.0.0.1", process: "com.example.app")))
    #expect(app.apps == ["com.example.app"] && app.hostPatterns.isEmpty)
    #expect(HostGroup.draft(from: .scope(FlowScope(device: "127.0.0.1", process: FlowFilter.unknownProcessKey))).isEmpty)
    #expect(HostGroup.draft(from: .scope(FlowScope(device: "192.0.2.10"))).isEmpty)
    #expect(HostGroup.draft(from: .allFlows).isEmpty)
    #expect(HostGroup.draft(from: nil).isEmpty)
    let g = HostGroup(name: "g", hostPatterns: ["*.example.com"], apps: ["com.example.app"])
    let copy = HostGroup.draft(from: .group(g))
    #expect(copy.id != g.id && copy.name == g.name && copy.hostPatterns == g.hostPatterns && copy.apps == g.apps)
}
