import Foundation
import Testing
@testable import EyeProxyKit

private func parse(_ data: Data) throws -> [String: Any] {
    try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

@Test func wifiProfileHasProxyKeys() throws {
    let data = MobileConfig.wifiProxyProfile(ssid: "TVING-5G", security: .wpa2, password: "pw", proxyHost: "192.168.0.10", proxyPort: 9090)
    let plist = try parse(data)
    #expect(plist["PayloadType"] as? String == "Configuration")
    let wifi = try #require((plist["PayloadContent"] as? [[String: Any]])?.first)
    #expect(wifi["PayloadType"] as? String == "com.apple.wifi.managed")
    #expect(wifi["SSID_STR"] as? String == "TVING-5G")
    #expect(wifi["EncryptionType"] as? String == "WPA2")
    #expect(wifi["Password"] as? String == "pw")
    #expect(wifi["ProxyType"] as? String == "Manual")
    #expect(wifi["ProxyServer"] as? String == "192.168.0.10")
    #expect(wifi["ProxyServerPort"] as? Int == 9090)
    #expect(wifi["AutoJoin"] as? Bool == true)
}

@Test func openNetworkOmitsPassword() throws {
    let data = MobileConfig.wifiProxyProfile(ssid: "Open", security: .none, password: "ignored", proxyHost: "10.0.0.1", proxyPort: 8080)
    let wifi = try #require((try parse(data)["PayloadContent"] as? [[String: Any]])?.first)
    #expect(wifi["Password"] == nil)
    #expect(wifi["EncryptionType"] as? String == "None")
}

@Test func caProfileEmbedsDER() throws {
    let der: [UInt8] = [1, 2, 3, 4]
    let data = MobileConfig.caProfile(certificateDER: der, commonName: "Test CA")
    let plist = try parse(data)
    #expect(plist["PayloadDisplayName"] as? String == "EyeProxy CA (Test CA)")
    let ca = try #require((plist["PayloadContent"] as? [[String: Any]])?.first)
    #expect(ca["PayloadType"] as? String == "com.apple.security.root")
    #expect(ca["PayloadContent"] as? Data == Data(der))
    #expect(data == MobileConfig.caProfile(certificateDER: der, commonName: "Test CA"))  // 결정적 UUID
}
