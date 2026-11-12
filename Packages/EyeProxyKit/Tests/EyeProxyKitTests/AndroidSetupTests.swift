import Testing
import Foundation
@testable import EyeProxyKit

@Test func locateADBPrefersEnvThenHomeThenPath() {
    let home = URL(fileURLWithPath: "/fake/home")
    let env = ["ANDROID_HOME": "/sdk/a", "ANDROID_SDK_ROOT": "/sdk/b", "PATH": "/usr/bin:/opt/bin"]
    func locate(_ existing: Set<String>, _ env: [String: String] = env) -> String? {
        AndroidSetup.locateADB(environment: env, home: home, fileExists: { existing.contains($0) })?.path
    }
    let all: Set = ["/sdk/a/platform-tools/adb", "/sdk/b/platform-tools/adb",
                    "/fake/home/Library/Android/sdk/platform-tools/adb", "/opt/bin/adb"]
    #expect(locate(all) == "/sdk/a/platform-tools/adb")
    #expect(locate(all.subtracting(["/sdk/a/platform-tools/adb"])) == "/sdk/b/platform-tools/adb")
    #expect(locate(["/fake/home/Library/Android/sdk/platform-tools/adb", "/opt/bin/adb"]) == "/fake/home/Library/Android/sdk/platform-tools/adb")
    #expect(locate(["/opt/bin/adb"]) == "/opt/bin/adb")
    #expect(locate(["/usr/bin/adb", "/opt/bin/adb"]) == "/usr/bin/adb")
    #expect(locate(["/sdk/a/platform-tools/adb"], [:]) == nil)
    #expect(locate([]) == nil)
}

@Test func proxyAndPushArgumentsAreExact() {
    #expect(AndroidSetup.proxyArguments(host: "10.0.2.2", port: 9090) == ["shell", "settings", "put", "global", "http_proxy", "10.0.2.2:9090"])
    #expect(AndroidSetup.clearProxyArguments == ["shell", "settings", "put", "global", "http_proxy", ":0"])
    #expect(AndroidSetup.pushArguments(crt: URL(fileURLWithPath: "/tmp/Prog-CA.crt")) == ["push", "/tmp/Prog-CA.crt", "/sdcard/Download/Prog-CA.crt"])
    #expect(AndroidSetup.connectArguments("192.0.2.20") == ["connect", "192.0.2.20:5555"])
}

@Test func commandLinesContainBoth() {
    let text = AndroidSetup.commandLines(adb: "adb", host: "10.0.2.2", port: 9090, crt: URL(fileURLWithPath: "/tmp/Prog-CA.crt"))
    let lines = text.split(separator: "\n").map(String.init)
    #expect(lines == ["adb shell settings put global http_proxy 10.0.2.2:9090",
                      "adb push /tmp/Prog-CA.crt /sdcard/Download/Prog-CA.crt"])
}

@Test func tvCommandLinesAreConnectAndProxyOnly() {
    let lines = AndroidSetup.tvCommandLines(adb: "adb", tvIP: "192.0.2.20", host: "192.0.2.5", port: 9090).split(separator: "\n").map(String.init)
    #expect(lines == ["adb connect 192.0.2.20:5555", "adb shell settings put global http_proxy 192.0.2.5:9090"])
}

@Test func connectKeepsExplicitPort() {
    #expect(AndroidSetup.connectArguments("192.0.2.20:37199") == ["connect", "192.0.2.20:37199"])
}

@Test func clearProxyCommandIsExact() {
    #expect(AndroidSetup.clearProxyCommand(adb: "adb") == "adb shell settings put global http_proxy :0")
}

@Test func bundledConfigTrustsRawCA() {
    let xml = AndroidSetup.bundledNetworkSecurityConfigXML
    #expect(xml.contains("<certificates src=\"@raw/proxy_ca\""))
    #expect(xml.contains("src=\"system\""))
    #expect(xml.contains("src=\"user\""))
    #expect(xml.contains("app/src/debug/res/xml/network_security_config.xml"))
}

@Test func debugManifestPointsToConfig() {
    let xml = AndroidSetup.debugManifestXML
    #expect(xml.contains("android:networkSecurityConfig=\"@xml/network_security_config\""))
    #expect(xml.contains("tools:replace=\"android:networkSecurityConfig\""))
}

@Test func copyCACommandQuotesPath() {
    #expect(AndroidSetup.copyCACommand(caPEMPath: "/tmp/Prog CA/ca.pem")
            == "mkdir -p app/src/debug/res/raw && cp \"/tmp/Prog CA/ca.pem\" app/src/debug/res/raw/proxy_ca.crt")
}
