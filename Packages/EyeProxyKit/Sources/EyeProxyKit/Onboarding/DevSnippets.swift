import Foundation

/// 개발 환경 섹션에서 고르는 런타임·도구.
public enum DevPlatform: String, CaseIterable, Identifiable, Sendable {
    case httpClients, nodeJS, python, ruby, java, docker, electron, reactNative, flutter, nextJS, firefox

    public var id: Self { self }

    /// 목록에 보이는 이름.
    public var title: String {
        switch self {
        case .httpClients: "HTTP Clients (curl·wget)"
        case .nodeJS: "NodeJS"
        case .python: "Python"
        case .ruby: "Ruby"
        case .java: "Java"
        case .docker: "Docker"
        case .electron: "Electron App"
        case .reactNative: "React Native"
        case .flutter: "Flutter"
        case .nextJS: "NextJS (fetch)"
        case .firefox: "Firefox Browsers"
        }
    }
}

/// 한 플랫폼의 설정 안내: 순서대로 읽는 단계와 복사할 스니펫(없으면 빈 문자열).
public struct DevGuide: Sendable {
    public let steps: [String]
    public let snippet: String
}

/// 플랫폼별로 EyeProxy CA를 신뢰하고 프록시를 타게 하는 안내를 만든다.
public enum DevSnippets {
    /// `pemPath`(CA PEM)와 `proxyHost:proxyPort`를 넣은 안내. Docker는 호스트를 `host.docker.internal`로 바꾼다.
    public static func guide(for platform: DevPlatform, pemPath pem: String, proxyHost host: String, proxyPort port: Int) -> DevGuide {
        let proxy = "http://\(host):\(port)"
        let nodeEnv = "export NODE_EXTRA_CA_CERTS=\"\(pem)\" HTTPS_PROXY=\(proxy) HTTP_PROXY=\(proxy)"
        let fetchMemo = "Node 20 이상의 내장 fetch는 프록시 환경변수를 무시합니다. 앱 시작 시 undici의 setGlobalDispatcher(new EnvHttpProxyAgent())를 호출하거나 global-agent를 사용합니다."
        switch platform {
        case .httpClients:
            return DevGuide(steps: [
                "터미널에서 아래 환경변수를 설정하면 이후 실행하는 도구가 \(host):\(port) 프록시와 EyeProxy CA를 사용합니다.",
                "curl만 쓸 때는 --proxy와 --cacert 옵션을 직접 지정해도 됩니다.",
                "wget은 --ca-certificate=\"\(pem)\" 옵션으로 같은 CA를 지정합니다.",
            ], snippet: """
            export HTTPS_PROXY=\(proxy) HTTP_PROXY=\(proxy) SSL_CERT_FILE="\(pem)"
            curl --proxy \(proxy) --cacert "\(pem)" https://example.com
            """)
        case .nodeJS:
            return DevGuide(steps: [
                "Node 프로세스를 띄우기 전에 아래 환경변수를 설정합니다. NODE_EXTRA_CA_CERTS로 EyeProxy CA를 추가로 신뢰합니다.",
                fetchMemo,
            ], snippet: nodeEnv)
        case .python:
            return DevGuide(steps: [
                "requests는 REQUESTS_CA_BUNDLE, 표준 ssl·urllib과 httpx는 SSL_CERT_FILE을 읽습니다. 둘 다 설정합니다.",
            ], snippet: "export REQUESTS_CA_BUNDLE=\"\(pem)\" SSL_CERT_FILE=\"\(pem)\" HTTPS_PROXY=\(proxy) HTTP_PROXY=\(proxy)")
        case .ruby:
            return DevGuide(steps: [
                "Ruby의 OpenSSL은 SSL_CERT_FILE을 읽고, Net::HTTP는 HTTPS_PROXY 환경변수를 따릅니다.",
            ], snippet: "export SSL_CERT_FILE=\"\(pem)\" HTTPS_PROXY=\(proxy) HTTP_PROXY=\(proxy)")
        case .java:
            return DevGuide(steps: [
                "keytool로 EyeProxy CA를 JDK의 cacerts에 넣습니다(기본 비밀번호 changeit, 권한 오류가 나면 sudo).",
                "JVM 옵션으로 프록시 \(host):\(port)를 지정해 실행합니다.",
            ], snippet: """
            keytool -importcert -trustcacerts -alias eyeproxy -file "\(pem)" -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit
            java -Dhttps.proxyHost=\(host) -Dhttps.proxyPort=\(port) -Dhttp.proxyHost=\(host) -Dhttp.proxyPort=\(port) -jar app.jar
            """)
        case .docker:
            let dockerProxy = "http://host.docker.internal:\(port)"
            return DevGuide(steps: [
                "컨테이너 안에서는 127.0.0.1이 컨테이너 자신이므로 host.docker.internal:\(port)로 Mac의 EyeProxy에 접속합니다.",
                "CA를 마운트하고 컨테이너에서 update-ca-certificates를 실행해 시스템 CA로 등록합니다(Debian·Ubuntu 계열 이미지).",
            ], snippet: """
            docker run --rm \\
              -e HTTPS_PROXY=\(dockerProxy) -e HTTP_PROXY=\(dockerProxy) \\
              -v "\(pem):/usr/local/share/ca-certificates/eyeproxy.crt:ro" \\
              <image> sh -c 'update-ca-certificates && <command>'
            """)
        case .electron:
            return DevGuide(steps: [
                "렌더러(Chromium)는 --proxy-server로, 메인 프로세스(Node)는 NODE_EXTRA_CA_CERTS로 EyeProxy CA를 신뢰합니다.",
                "Chromium은 Mac 키체인의 CA를 따르므로 \"이 Mac\" 섹션에서 CA를 신뢰해 둡니다.",
                "개발용으로만 app.commandLine.appendSwitch('ignore-certificate-errors')로 인증서 검사를 끌 수도 있습니다.",
            ], snippet: "NODE_EXTRA_CA_CERTS=\"\(pem)\" npx electron . --proxy-server=\(host):\(port)")
        case .reactNative:
            return DevGuide(steps: [
                "iOS 시뮬레이터는 Mac 시스템 프록시(\(host):\(port))를 따릅니다. \"iOS 시뮬레이터\" 섹션에서 CA를 설치합니다.",
                "Android 에뮬레이터·실기기는 \"Android\" 섹션의 안내대로 프록시와 CA를 설정하고, 디버그 빌드에 network_security_config를 넣습니다.",
                "Metro 번들러(JS 번들·HMR) 트래픽은 프록시를 타지 않습니다. 앱이 보내는 API 요청만 보입니다.",
            ], snippet: "")
        case .flutter:
            return DevGuide(steps: [
                "Dart HttpClient는 시스템 프록시와 CA를 따르지 않으므로 앱 코드에서 지정합니다(디버그 빌드에서만).",
                "파일 경로는 macOS 앱과 iOS 시뮬레이터에서만 읽힙니다. 실기기는 PEM을 에셋으로 넣고 setTrustedCertificatesBytes를 쓰며, Android 에뮬레이터는 호스트를 10.0.2.2로 바꿉니다.",
                "개발용으로만 badCertificateCallback = (cert, host, port) => true로 인증서 검사를 끌 수도 있습니다.",
            ], snippet: """
            class EyeProxyOverrides extends HttpOverrides {
              @override
              HttpClient createHttpClient(SecurityContext? context) =>
                  super.createHttpClient(context)..findProxy = (uri) => "PROXY \(host):\(port);";
            }

            void main() {
              SecurityContext.defaultContext.setTrustedCertificates("\(pem)");
              HttpOverrides.global = EyeProxyOverrides();
              runApp(const MyApp());
            }
            """)
        case .nextJS:
            return DevGuide(steps: [
                "next dev를 띄우기 전에 아래 환경변수를 설정합니다. 서버 쪽 fetch·API 라우트 요청이 EyeProxy를 거칩니다.",
                fetchMemo + " instrumentation.ts의 register()에서 호출하면 됩니다.",
            ], snippet: nodeEnv + "\nnpx next dev")
        case .firefox:
            return DevGuide(steps: [
                "about:config에서 security.enterprise_roots.enabled를 true로 바꾸면 Mac 키체인에서 신뢰한 CA를 따릅니다(\"이 Mac\" 섹션 참고).",
                "또는 설정 ▸ 개인 정보 및 보안 ▸ 인증서 보기 ▸ 인증 기관 ▸ 가져오기에서 \(pem)을 선택합니다.",
                "설정 ▸ 네트워크 설정 ▸ 수동 프록시 설정에 HTTP 프록시 \(host):\(port)를 입력하고 \"HTTPS에도 이 프록시 사용\"을 켭니다.",
            ], snippet: "security.enterprise_roots.enabled = true")
        }
    }
}
