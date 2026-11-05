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

@Test func wifiProfileStripsInvalidXMLCharacters() throws {
    let data = MobileConfig.wifiProxyProfile(ssid: "A\u{0001}B", security: .wpa2, password: "p\u{0002}w", proxyHost: "1.2.3.4", proxyPort: 1)
    let wifi = try #require((try parse(data)["PayloadContent"] as? [[String: Any]])?.first)
    #expect(wifi["SSID_STR"] as? String == "AB" && wifi["Password"] as? String == "pw")
}

@Test func caProfileSeedDistinguishesLowBytes() throws {
    // 0x01,0x23 vs 0x12,0x03 는 패딩 없는 hex로는 같은 문자열 "123"이 된다.
    func uuids(_ der: [UInt8]) throws -> [String] {
        let top = try parse(MobileConfig.caProfile(certificateDER: der, commonName: "x"))
        let inner = try #require((top["PayloadContent"] as? [[String: Any]])?.first)
        return [top["PayloadUUID"] as? String ?? "", inner["PayloadUUID"] as? String ?? ""]
    }
    let a = try uuids([0x01, 0x23]), b = try uuids([0x12, 0x03])
    #expect(a[0] != b[0] && a[1] != b[1] && !a[0].isEmpty)
}

@Test func otherStringsAreSanitized() throws {
    let wifi = MobileConfig.wifiProxyProfile(ssid: "s", security: .none, password: nil, proxyHost: "h\u{0001}\u{FFFF}", proxyPort: 1, organization: "o\u{0003}")
    #expect(try parse(wifi)["PayloadOrganization"] as? String == "o")
    _ = try parse(MobileConfig.caProfile(certificateDER: [1], commonName: "c\u{0004}"))
}
