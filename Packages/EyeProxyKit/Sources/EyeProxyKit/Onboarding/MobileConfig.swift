import CryptoKit
import Foundation

public enum WiFiSecurity: String, CaseIterable, Sendable {
    case none = "None", wpa = "WPA", wpa2 = "WPA2", wpa3 = "WPA3"
}

public enum MobileConfig {
    /// Wi-Fi(com.apple.wifi.managed) + 수동 프록시. 반환은 XML plist Data.
    public static func wifiProxyProfile(ssid: String, security: WiFiSecurity, password: String?, proxyHost: String, proxyPort: Int, organization: String = "EyeProxy") -> Data {
        let id = "com.tv.eyeproxy.wifi.\(ssid)"
        let name = "EyeProxy 프록시 (\(ssid))"
        let seed = "\(id)|\(proxyHost):\(proxyPort)"
        var wifi = payload(type: "com.apple.wifi.managed", identifier: id + ".payload", name: name, seed: seed + "|payload")
        wifi["SSID_STR"] = ssid
        wifi["EncryptionType"] = security.rawValue
        if security != .none, let password, !password.isEmpty { wifi["Password"] = password }
        wifi["AutoJoin"] = true
        wifi["ProxyType"] = "Manual"
        wifi["ProxyServer"] = proxyHost
        wifi["ProxyServerPort"] = proxyPort
        return profile(identifier: id, name: name, organization: organization, seed: seed, content: wifi)
    }

    /// 루트 CA(com.apple.security.root). displayName "EyeProxy CA (<commonName>)".
    public static func caProfile(certificateDER: [UInt8], commonName: String) -> Data {
        let id = "com.tv.eyeproxy.ca"
        let name = "EyeProxy CA (\(commonName))"
        let seed = id + "|" + certificateDER.map { String($0, radix: 16) }.joined()
        var ca = payload(type: "com.apple.security.root", identifier: id + ".payload", name: name, seed: seed + "|payload")
        ca["PayloadContent"] = Data(certificateDER)
        ca["PayloadCertificateFileName"] = "EyeProxy-CA.cer"
        return profile(identifier: id, name: name, organization: "EyeProxy", seed: seed, content: ca)
    }

    private static func payload(type: String, identifier: String, name: String, seed: String) -> [String: Any] {
        ["PayloadType": type, "PayloadVersion": 1, "PayloadIdentifier": identifier,
         "PayloadUUID": stableUUID(seed), "PayloadDisplayName": name]
    }

    private static func profile(identifier: String, name: String, organization: String, seed: String, content: [String: Any]) -> Data {
        let top: [String: Any] = [
            "PayloadType": "Configuration", "PayloadVersion": 1, "PayloadIdentifier": identifier,
            "PayloadUUID": stableUUID(seed), "PayloadDisplayName": name,
            "PayloadOrganization": organization, "PayloadContent": [content],
        ]
        // 값이 모두 plist 타입이라 실패하지 않는다.
        return try! PropertyListSerialization.data(fromPropertyList: top, format: .xml, options: 0)
    }

    /// 같은 입력 → 같은 UUID. 프로파일이 재현 가능하고 기기에서 재설치 시 같은 항목으로 갱신된다.
    private static func stableUUID(_ seed: String) -> String {
        let b = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])).uuidString
    }
}
