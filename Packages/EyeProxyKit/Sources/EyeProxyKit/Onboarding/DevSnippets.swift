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

/// 플랫폼별로 Prog CA를 신뢰하고 프록시를 타게 하는 안내를 만든다.
public enum DevSnippets {
    /// `pemPath`(CA PEM)와 `proxyHost:proxyPort`를 넣은 안내. Docker는 호스트를 `host.docker.internal`로 바꾼다.
    public static func guide(for platform: DevPlatform, pemPath pem: String, proxyHost host: String, proxyPort port: Int) -> DevGuide {
        let proxy = "http://\(host):\(port)"
        let nodeEnv = "export NODE_EXTRA_CA_CERTS=\"\(pem)\" HTTPS_PROXY=\(proxy) HTTP_PROXY=\(proxy)"
        let sslList = "복호화할 호스트를 Tools ▸ SSL Proxying List…에 먼저 추가합니다(도구 규칙이 가리키는 호스트는 자동 복호화). 목록에 없는 HTTPS는 원래 인증서로 그대로 지나갑니다."
        // SSL_CERT_FILE·REQUESTS_CA_BUNDLE·--cacert는 시스템 신뢰 저장소를 대체하므로 시스템 번들과 합친 파일을 가리킨다.
        let bundle = "\"$HOME/prog-bundle.pem\""
        let makeBundle = "cat /etc/ssl/cert.pem \"\(pem)\" > \(bundle)"
        let bundleMemo = "이 변수들은 시스템 신뢰 저장소를 대체하므로 Prog CA만 넣으면 목록 밖 HTTPS가 실패합니다. macOS 시스템 번들(/etc/ssl/cert.pem)과 Prog CA를 합친 ~/prog-bundle.pem을 만들어 가리킵니다."
        let fetchMemo = "Node 20 이상의 내장 fetch는 프록시 환경변수를 무시합니다. 앱 시작 시 undici의 setGlobalDispatcher(new EnvHttpProxyAgent())를 호출하거나 global-agent를 사용합니다."
        switch platform {
        case .httpClients:
            return DevGuide(steps: [
                sslList,
                "터미널에서 아래 환경변수를 설정하면 이후 실행하는 도구가 \(host):\(port) 프록시와 결합 번들을 사용합니다.",
                bundleMemo,
                "curl만 쓸 때는 --proxy와 --cacert 옵션을 직접 지정해도 됩니다.",
                "wget은 --ca-certificate=\(bundle) 옵션으로 같은 번들을 지정합니다.",
            ], snippet: """
            \(makeBundle)
            export HTTPS_PROXY=\(proxy) HTTP_PROXY=\(proxy) SSL_CERT_FILE=\(bundle)
            curl --proxy \(proxy) --cacert \(bundle) https://example.com
            """)
        case .nodeJS:
            return DevGuide(steps: [
                sslList,
                "Node 프로세스를 띄우기 전에 아래 환경변수를 설정합니다. NODE_EXTRA_CA_CERTS로 Prog CA를 추가로 신뢰합니다.",
                fetchMemo,
            ], snippet: nodeEnv)
        case .python:
            return DevGuide(steps: [
                sslList,
                "requests는 REQUESTS_CA_BUNDLE, 표준 ssl·urllib과 httpx는 SSL_CERT_FILE을 읽습니다. 둘 다 설정합니다.",
                bundleMemo,
            ], snippet: "\(makeBundle)\nexport REQUESTS_CA_BUNDLE=\(bundle) SSL_CERT_FILE=\(bundle) HTTPS_PROXY=\(proxy) HTTP_PROXY=\(proxy)")
        case .ruby:
            return DevGuide(steps: [
                sslList,
                "Ruby의 OpenSSL은 SSL_CERT_FILE을 읽고, Net::HTTP는 HTTPS_PROXY 환경변수를 따릅니다.",
                bundleMemo,
            ], snippet: "\(makeBundle)\nexport SSL_CERT_FILE=\(bundle) HTTPS_PROXY=\(proxy) HTTP_PROXY=\(proxy)")
        case .java:
            return DevGuide(steps: [
                sslList,
                "keytool로 Prog CA를 JDK의 cacerts에 넣습니다(JDK 9 이상의 -cacerts, 기본 비밀번호 changeit). JDK 키스토어를 고치므로 권한 오류가 나면 sudo를 붙입니다.",
                "JDK 8은 -cacerts 대신 -keystore \"$JAVA_HOME/jre/lib/security/cacerts\"를 씁니다.",
                "JVM 옵션으로 프록시 \(host):\(port)를 지정해 실행합니다.",
            ], snippet: """
            keytool -importcert -noprompt -cacerts -alias prog -file "\(pem)" -storepass changeit
            java -Dhttps.proxyHost=\(host) -Dhttps.proxyPort=\(port) -Dhttp.proxyHost=\(host) -Dhttp.proxyPort=\(port) -jar app.jar
            """)
        case .docker:
            let dockerProxy = "http://host.docker.internal:\(port)"
            return DevGuide(steps: [
                sslList,
                "컨테이너 안에서는 127.0.0.1이 컨테이너 자신이므로 host.docker.internal:\(port)로 Mac의 Prog에 접속합니다.",
                "CA를 마운트하고 컨테이너에서 update-ca-certificates를 실행해 시스템 CA로 등록합니다(Debian·Ubuntu 계열 이미지).",
            ], snippet: """
            docker run --rm \\
              -e HTTPS_PROXY=\(dockerProxy) -e HTTP_PROXY=\(dockerProxy) \\
              -v "\(pem):/usr/local/share/ca-certificates/prog.crt:ro" \\
              <image> sh -c 'update-ca-certificates && <command>'
            """)
        case .electron:
            return DevGuide(steps: [
                sslList,
                "렌더러(Chromium)는 --proxy-server로, 메인 프로세스(Node)는 NODE_EXTRA_CA_CERTS로 Prog CA를 신뢰합니다.",
                "Chromium은 Mac 키체인의 CA를 따르므로 \"이 Mac\" 섹션에서 CA를 신뢰해 둡니다.",
                "개발용으로만 app.commandLine.appendSwitch('ignore-certificate-errors')로 인증서 검사를 끌 수도 있습니다.",
            ], snippet: "NODE_EXTRA_CA_CERTS=\"\(pem)\" npx electron . --proxy-server=\(host):\(port)")
        case .reactNative:
            return DevGuide(steps: [
                sslList,
                "iOS 시뮬레이터는 Mac 시스템 프록시(\(host):\(port))를 따릅니다. \"iOS 시뮬레이터\" 섹션에서 CA를 설치합니다.",
                "Android 에뮬레이터·실기기는 \"Android\" 섹션의 안내대로 프록시와 CA를 설정하고, 디버그 빌드에 network_security_config를 넣습니다.",
                "Metro 번들러(JS 번들·HMR) 트래픽은 프록시를 타지 않습니다. 앱이 보내는 API 요청만 보입니다.",
            ], snippet: "")
        case .flutter:
            return DevGuide(steps: [
                sslList,
                "Dart HttpClient는 시스템 프록시와 CA를 따르지 않으므로 앱 코드에서 지정합니다(디버그 빌드에서만).",
                "파일 경로는 macOS 앱과 iOS 시뮬레이터에서만 읽힙니다. 실기기는 PEM을 에셋으로 넣고 setTrustedCertificatesBytes를 쓰며, Android 에뮬레이터는 호스트를 10.0.2.2로 바꿉니다.",
                "개발용으로만 badCertificateCallback = (cert, host, port) => true로 인증서 검사를 끌 수도 있습니다.",
            ], snippet: """
            class ProgOverrides extends HttpOverrides {
              @override
              HttpClient createHttpClient(SecurityContext? context) =>
                  super.createHttpClient(context)..findProxy = (uri) => "PROXY \(host):\(port);";
            }

            void main() {
              SecurityContext.defaultContext.setTrustedCertificates("\(pem)");
              HttpOverrides.global = ProgOverrides();
              runApp(const MyApp());
            }
            """)
        case .nextJS:
            return DevGuide(steps: [
                sslList,
                "next dev를 띄우기 전에 아래 환경변수를 설정합니다. 서버 쪽 fetch·API 라우트 요청이 Prog를 거칩니다.",
                fetchMemo + " instrumentation.ts의 register()에서 호출하면 됩니다.",
            ], snippet: nodeEnv + "\nnpx next dev")
        case .firefox:
            return DevGuide(steps: [
                sslList,
                "about:config에서 security.enterprise_roots.enabled를 true로 바꾸면 Mac 키체인에서 신뢰한 CA를 따릅니다(\"이 Mac\" 섹션 참고).",
                "또는 설정 ▸ 개인 정보 및 보안 ▸ 인증서 보기 ▸ 인증 기관 ▸ 가져오기에서 \(pem)을 선택합니다.",
                "설정 ▸ 네트워크 설정 ▸ 수동 프록시 설정에 HTTP 프록시 \(host):\(port)를 입력하고 \"HTTPS에도 이 프록시 사용\"을 켭니다.",
            ], snippet: "security.enterprise_roots.enabled = true")
        }
    }
}
