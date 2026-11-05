import Testing
@testable import EyeProxyKit

@Test func parsesLsofFieldsDedupingByPid() {
    let out = "p3646\ncProxyman\nn*:9090\nn[::1]:9090\np4000\ncEyeProxy\nn*:9090\np3646\ncProxyman\nn*:9090\n"
    let r = PortOwner.parseLsofFields(out)
    #expect(r.map(\.pid) == [3646, 4000]); #expect(r.map(\.name) == ["Proxyman", "EyeProxy"])
}
