import Foundation

/// Android 실기기·에뮬레이터·TV에 프록시와 CA를 넣는 adb 명령 생성과 adb 탐색.
public enum AndroidSetup {
    static let deviceCRTPath = "/sdcard/Download/Prog-CA.crt"

    /// 후보: $ANDROID_HOME/platform-tools/adb, $ANDROID_SDK_ROOT/platform-tools/adb, ~/Library/Android/sdk/platform-tools/adb, PATH의 adb. 처음 실행 가능한 것.
    public static func locateADB(environment: [String: String] = ProcessInfo.processInfo.environment,
                                 home: URL = .homeDirectory,
                                 fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> URL? {
        let sdks = [environment["ANDROID_HOME"], environment["ANDROID_SDK_ROOT"]]
            .compactMap { $0 }.filter { !$0.isEmpty }
            .map { "\($0)/platform-tools/adb" }
        let homeSDK = home.appending(path: "Library/Android/sdk/platform-tools/adb").path
        let path = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/adb" }
        return (sdks + [homeSDK] + path).first(where: fileExists).map { URL(fileURLWithPath: $0) }
    }

    /// `adb shell settings put global http_proxy <host>:<port>` 인자.
    public static func proxyArguments(host: String, port: Int) -> [String] {
        ["shell", "settings", "put", "global", "http_proxy", "\(host):\(port)"]
    }

    /// 프록시 해제(`http_proxy :0`) 인자.
    public static let clearProxyArguments = ["shell", "settings", "put", "global", "http_proxy", ":0"]

    /// CA 파일을 기기의 다운로드 폴더로 push하는 인자.
    public static func pushArguments(crt: URL) -> [String] {
        ["push", crt.path, deviceCRTPath]
    }

    /// 복사용 두 줄: 프록시 설정, CA push.
    public static func commandLines(adb: String, host: String, port: Int, crt: URL) -> String {
        [proxyArguments(host: host, port: port), pushArguments(crt: crt)]
            .map { ([adb] + $0).joined(separator: " ") }.joined(separator: "\n")
    }

    /// 네트워크 디버깅으로 TV에 붙는 `adb connect` 인자. 입력에 ":"가 있으면 그대로, 없으면 ":5555"를 붙인다.
    public static func connectArguments(_ ip: String) -> [String] {
        ["connect", ip.contains(":") ? ip : "\(ip):5555"]
    }

    /// 복사용 두 줄: connect, 프록시 설정.
    public static func tvCommandLines(adb: String, tvIP: String, host: String, port: Int) -> String {
        [connectArguments(tvIP), proxyArguments(host: host, port: port)]
            .map { ([adb] + $0).joined(separator: " ") }.joined(separator: "\n")
    }

    /// 프록시 해제 한 줄.
    public static func clearProxyCommand(adb: String) -> String {
        ([adb] + clearProxyArguments).joined(separator: " ")
    }

    /// 앱 프로젝트 안에서 번들한 CA의 위치.
    public static let bundledCAPath = "app/src/debug/res/raw/proxy_ca.crt"

    /// 앱 프로젝트에서 실행하는, CA를 번들 위치로 복사하는 명령.
    public static func copyCACommand(caPEMPath: String) -> String {
        "mkdir -p app/src/debug/res/raw && cp \"\(caPEMPath)\" \(bundledCAPath)"
    }

    /// 번들한 CA의 SHA-256 지문을 찍는 명령.
    public static let fingerprintCommand = "openssl x509 -in \(bundledCAPath) -noout -fingerprint -sha256"

    /// 앱이 CA를 못 믿을 때 로그를 보는 명령.
    public static let trustAnchorLogcatCommand = "adb logcat | grep -i \"trust anchor\""

    /// 디버그 빌드가 시스템·사용자·번들 CA를 신뢰하게 하는 network_security_config.xml.
    public static let bundledNetworkSecurityConfigXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <!-- app/src/debug/res/xml/network_security_config.xml -->
        <!-- 앱에 이미 config가 있으면 debug-overrides의 trust-anchors에 @raw/proxy_ca만 더한다 -->
        <network-security-config>
            <base-config>
                <trust-anchors>
                    <certificates src="system"/>
                    <certificates src="user"/>
                    <certificates src="@raw/proxy_ca"/>
                </trust-anchors>
            </base-config>
        </network-security-config>
        """

    /// 디버그 소스셋의 AndroidManifest.xml. main에 같은 속성이 없으면 tools:replace는 지워도 된다.
    public static let debugManifestXML = """
        <!-- app/src/debug/AndroidManifest.xml: main에 같은 속성이 없으면 tools:replace는 지워도 된다 -->
        <manifest xmlns:android="http://schemas.android.com/apk/res/android"
            xmlns:tools="http://schemas.android.com/tools">
            <application
                android:networkSecurityConfig="@xml/network_security_config"
                tools:replace="android:networkSecurityConfig" />
        </manifest>
        """

    /// adb를 실행해 종료 코드와 stdout(+stderr)을 돌려준다.
    public static func runADB(_ adb: URL, _ args: [String]) async throws -> (status: Int32, output: String) {
        let r = try await Shell.run(adb.path, args)
        return (r.status, r.stderr.isEmpty ? r.stdout : r.stdout + "\n" + r.stderr)
    }
}
