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
    #expect(AndroidSetup.pushArguments(crt: URL(fileURLWithPath: "/tmp/EyeProxy-CA.crt")) == ["push", "/tmp/EyeProxy-CA.crt", "/sdcard/Download/EyeProxy-CA.crt"])
    #expect(AndroidSetup.connectArguments("192.168.0.20") == ["connect", "192.168.0.20:5555"])
    #expect(AndroidSetup.installIntentArguments == ["shell", "am", "start", "-a", "android.intent.action.VIEW", "-t", "application/x-x509-ca-cert", "-d", "file:///sdcard/Download/EyeProxy-CA.crt"])
}

@Test func commandLinesContainBoth() {
    let text = AndroidSetup.commandLines(adb: "adb", host: "10.0.2.2", port: 9090, crt: URL(fileURLWithPath: "/tmp/EyeProxy-CA.crt"))
    let lines = text.split(separator: "\n").map(String.init)
    #expect(lines == ["adb shell settings put global http_proxy 10.0.2.2:9090",
                      "adb push /tmp/EyeProxy-CA.crt /sdcard/Download/EyeProxy-CA.crt"])
}

@Test func tvCommandLinesContainConnectAndIntent() {
    let text = AndroidSetup.tvCommandLines(adb: "adb", tvIP: "192.168.0.20", host: "192.168.0.5", port: 9090, crt: URL(fileURLWithPath: "/tmp/EyeProxy-CA.crt"))
    let lines = text.split(separator: "\n").map(String.init)
    #expect(lines.count == 4)
    #expect(lines[0] == "adb connect 192.168.0.20:5555")
    #expect(lines[1] == "adb shell settings put global http_proxy 192.168.0.5:9090")
    #expect(lines[2].hasPrefix("adb push "))
    #expect(lines[3].contains("android.intent.action.VIEW"))
    #expect(!text.contains("10.0.2.2"))
}
