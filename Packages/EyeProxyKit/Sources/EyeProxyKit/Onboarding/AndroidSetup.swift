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

    /// 네트워크 디버깅으로 TV에 붙는 `adb connect <ip>:5555` 인자.
    public static let connectArguments: @Sendable (String) -> [String] = { ip in ["connect", "\(ip):5555"] }

    /// 기기에 push한 CA로 인증서 설치 화면을 띄우는 인텐트 인자.
    public static let installIntentArguments = ["shell", "am", "start", "-a", "android.intent.action.VIEW",
                                                "-t", "application/x-x509-ca-cert", "-d", "file://\(deviceCRTPath)"]

    /// 복사용 네 줄: connect, 프록시, push, 설치 인텐트.
    public static func tvCommandLines(adb: String, tvIP: String, host: String, port: Int, crt: URL) -> String {
        [connectArguments(tvIP), proxyArguments(host: host, port: port), pushArguments(crt: crt), installIntentArguments]
            .map { ([adb] + $0).joined(separator: " ") }.joined(separator: "\n")
    }

    /// 디버그 빌드가 사용자 CA를 신뢰하게 하는 res/xml/network_security_config.xml(매니페스트 android:networkSecurityConfig로 연결).
    public static let networkSecurityConfigXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <!-- res/xml/network_security_config.xml, AndroidManifest <application android:networkSecurityConfig="@xml/network_security_config"> -->
        <network-security-config>
            <base-config>
                <trust-anchors>
                    <certificates src="system"/>
                    <certificates src="user"/>
                </trust-anchors>
            </base-config>
        </network-security-config>
        """

    /// adb를 실행해 종료 코드와 stdout(+stderr)을 돌려준다.
    public static func runADB(_ adb: URL, _ args: [String]) async throws -> (status: Int32, output: String) {
        let r = try await Shell.run(adb.path, args)
        return (r.status, r.stderr.isEmpty ? r.stdout : r.stdout + "\n" + r.stderr)
    }
}
