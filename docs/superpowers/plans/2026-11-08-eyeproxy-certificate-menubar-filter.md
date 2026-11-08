# Certificate 메뉴·상태 막대·필터 바·Prog 아이콘 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "프록시" 메뉴를 Proxyman식 Certificate 메뉴와 Certificate 창으로 바꾸고, 메인 목록 위에 프로토콜·콘텐츠·상태 코드 필터 바를, 메뉴 막대에 상태 아이콘 메뉴를 더하고, 개구리 앱 아이콘과 함께 표시 이름을 Prog으로 바꾼다.

**Architecture:** 분류·필터·인증서 내보내기·안내 스니펫 같은 순수 로직은 `EyeProxyKit`에 두고 Swift Testing으로 고정한다. 앱은 `AppModel`에 섹션 상태(`certificateSection`)를 두고 Certificate 메뉴·상태 막대·창이 같은 모델 값을 바인딩해 어긋남이 없게 한다. 이름 변경은 마지막 기계적 커밋 하나다.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI(`MenuBarExtra`, `NavigationSplitView`), AppKit(`NSSavePanel`·`NSAlert`), swift-certificates/swift-crypto(Core), macOS 내장 `openssl`·`qlmanage`. 새 패키지 없음.

**Spec:** `docs/superpowers/specs/2026-11-08-eyeproxy-certificate-menubar-filter-design.md` — 번호(§)는 이 스펙을 가리킨다.

## Global Constraints

- Swift 6 strict concurrency, SwiftUI, macOS 15+. 외부 패키지는 CLAUDE.md 허용 목록만(swift-nio, swift-nio-ssl, swift-nio-extras, swift-certificates, swift-asn1, swift-crypto, Sparkle). 새 패키지 금지(brew 도구 의존도 금지).
- 모듈 방향 `EyeProxy` → `EyeProxyKit` → `EyeProxyCore`. 역방향 import 금지. Core는 UI 무관.
- 자동 테스트·에이전트는 `networksetup -set*`, `security add-trusted-cert`, `simctl keychain`, `adb`를 실행하지 않는다. 키체인·시스템 프록시·adb는 수동 점검 항목이다.
- 비밀값(CA 개인키 내용, 비밀번호)을 로그·클립보드·문서·프로세스 인자에 남기지 않는다. 개인키 파일은 0600.
- 공개 레포: 커밋 파일에 회사 내부 도메인·로컬 사용자 경로 금지.
- 메뉴 항목 이름은 영어(Proxyman과 동일 철자), 안내 문장·설명은 한국어.
- 커밋 메시지 `<type>(<scope>): <한국어 요약>`. 각 Task 끝에 `swift test --package-path Packages/EyeProxyKit`(Core를 건드렸으면 Core도)와 `xcodegen generate && xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates`가 통과해야 한다. 테스트 후 `git checkout -- Packages/*/Package.resolved`로 resolved 변경을 되돌린다.
- 기존 시뮬레이터 CA 설치는 창이 열린 뒤 버튼 한 번(§2 반목표).
- `http://eyeproxy/ssl`은 계속 동작한다(별칭 유지).

## Review Focus

1. `Content-Type: Application/JSON; charset=utf-8`처럼 대소문자·파라미터가 붙어도 JSON으로 분류된다 → Task 1 `contentKindIgnoresCaseAndParams`.
2. 응답이 아직 없는 행은 상태 코드 묶음이 비어 있을 때만 보이고, `2xx`를 고르면 사라진다 → Task 1 `statusFilterExcludesPendingRows`.
3. Android Chrome이 `/ssl`을 열면 `.crt`가, iOS Safari가 열면 mobileconfig가 내려온다 → Task 3 `sslServesPEMForAndroidUserAgent`.
4. 같은 경로에 이미 파일이 있을 때 개인키 내보내기는 덮어쓰면서도 0600으로 끝난다 → Task 4 `privateKeyExportOverwritesWithMode600`.
5. 같은 초에 Reset을 두 번 해도 백업 폴더 이름이 충돌하지 않고 둘 다 남는다 → Task 5 `rotateTwiceInSameSecondKeepsBothBackups`.

---

### Task 1: 흐름 분류와 필터 필드 (Kit)

**Files:**
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/FlowClassification.swift`
- Modify: `Packages/EyeProxyKit/Sources/EyeProxyKit/FlowFilter.swift`
- Test: `Packages/EyeProxyKit/Tests/EyeProxyKitTests/FlowClassificationTests.swift`, `FlowFilterTests.swift`

**Interfaces:**
- Consumes: `Flow`, `FlowRequest.header(_:)`, `FlowResponse.header(_:)` (Core). 테스트 픽스처 `Flow.fixture(url:method:status:)`(`Tests/Support/Fixtures.swift`; 헤더가 필요하면 `f.request.headers`/`f.response?.headers`를 직접 넣는다).
- Produces:
  ```swift
  public enum FlowProtocol: String, CaseIterable, Sendable { case http = "HTTP", https = "HTTPS"
      public static func of(_ flow: Flow) -> FlowProtocol }
  public enum ContentKind: String, CaseIterable, Sendable {
      case json = "JSON", form = "Form", xml = "XML", js = "JS", css = "CSS", graphql = "GraphQL", document = "Document", media = "Media", other = "Other"
      public static func of(_ flow: Flow) -> ContentKind }
  // FlowFilter에 추가
  public var protocols: Set<FlowProtocol> = []
  public var contentKinds: Set<ContentKind> = []
  public var statusClasses: Set<Int> = []      // 1...5
  public var isBarEmpty: Bool                   // 세 묶음 모두 비었는가 (= All)
  public mutating func clearBar()
  ```
- `CaseIterable` 순서가 곧 필터 바 칩 순서다(§6.1).

- [ ] **Step 1: 분류 테스트 작성** — `FlowClassificationTests.swift`
  - `protocolFollowsScheme`: scheme `https` → `.https`, `http` → `.http`; `isTunnel == true`인 https 흐름도 `.https`.
  - `contentKindPriority`: §6.3 순서대로 한 건씩. 요청 path `/api/graphql?x=1` + 응답 `application/json` → `.graphql`; 요청 `Content-Type: multipart/form-data; boundary=x` + 응답 `application/json` → `.form`; 응답 `application/vnd.api+json` → `.json`; `application/rss+xml` → `.xml`; `text/javascript` → `.js`; `text/css` → `.css`; `text/html` → `.document`; `image/png`, `font/woff2`, `application/x-mpegurl` → `.media`; `application/octet-stream`, Content-Type 없음 → `.other`.
  - `contentKindIgnoresCaseAndParams`: `Application/JSON; charset=utf-8` → `.json`.
  - `contentKindFallsBackToRequestTypeWhenNoResponse`: 응답 없음 + 요청 `application/json` → `.json`.
- [ ] **Step 2: 실패 확인** — `swift test --package-path Packages/EyeProxyKit --filter FlowClassificationTests` → 컴파일 실패(타입 없음).
- [ ] **Step 3: `FlowClassification.swift` 구현** — `ContentKind.of`는 `type = (response?.header("Content-Type") ?? request.header("Content-Type"))?.split(separator: ";").first` 소문자·공백 제거. GraphQL은 `request.path.split(separator: "?").first`에 `graphql` 포함 또는 요청 Content-Type `application/graphql`.
- [ ] **Step 4: 필터 테스트 추가** — `FlowFilterTests.swift`
  - `barGroupsAreOrWithinAndAcrossGroups`: `protocols = [.https]`, `contentKinds = [.json, .xml]`, `statusClasses = [2]` → https+json+200 통과, http+json+200 탈락, https+css+200 탈락, https+json+404 탈락.
  - `statusFilterExcludesPendingRows`: 응답 없는 흐름은 `statusClasses` 비면 통과, `[2]`면 탈락.
  - `barFilterStacksWithTextAndHost`: `text: "search"`, `host: "api.example.com"`, `contentKinds: [.json]` 모두 만족할 때만 통과.
  - `clearBarKeepsOtherFields`: `clearBar()` 뒤 `isBarEmpty == true`이고 `text`·`host`는 그대로.
- [ ] **Step 5: `FlowFilter.matches(_:process:)`에 세 검사 추가** — `includeHidden`·device·process·host 검사 뒤, 텍스트 검사 앞. 상태 검사: `statusClasses` 비어 있지 않으면 `flow.response?.status` 없을 때 false, 있으면 `status / 100` 포함 여부.
- [ ] **Step 6: 통과 확인** — `swift test --package-path Packages/EyeProxyKit` 전체 PASS.
- [ ] **Step 7: 커밋** — `feat(filter): 프로토콜·콘텐츠·상태 코드 분류와 필터 필드`

### Task 2: 필터 바 뷰 (앱)

**Files:**
- Create: `EyeProxy/Views/FlowList/FilterBarView.swift`
- Modify: `EyeProxy/Views/MainWindow.swift:15-25`

**Interfaces:**
- Consumes: Task 1의 `FlowProtocol`, `ContentKind`, `FlowFilter.protocols/contentKinds/statusClasses/isBarEmpty/clearBar()`; `AppModel.filter`.
- Produces: `struct FilterBarView: View` (환경에서 `AppModel`을 읽어 `model.filter`를 직접 바인딩).

- [ ] **Step 1: `FilterBarView` 작성** — 한 줄 `ScrollView(.horizontal, showsIndicators: false)` 안 `HStack(spacing: 4)`: `All` 칩 → `Divider().frame(height: 14)` → `FlowProtocol.allCases` → Divider → `ContentKind.allCases` → Divider → `1xx…5xx`. 칩은 `Button`에 `.buttonStyle(.plain)`, 선택 시 `Capsule().fill(Color.accentColor)` + 흰 글자, 아니면 `.secondary` 글자. `All`은 `model.filter.isBarEmpty`일 때 선택 상태, 누르면 `clearBar()`. 칩 글자는 `.font(.caption)`, 높이 28, 좌우 패딩 8. `.help`에 §6.3 분류 기준 한 줄(예: JSON 칩 → "응답 Content-Type에 json 포함").
- [ ] **Step 2: `MainWindow`에 배치** — `detail:`의 두 레이아웃 분기 모두 `VStack(spacing: 0) { FilterBarView(); Divider(); <기존 VSplitView/HSplitView> }`로 감싼다. 필터 바는 `.background(.bar)`.
- [ ] **Step 3: 빌드·수동 확인** — Debug 빌드 후 앱 실행(이미 떠 있는 EyeProxy와 포트가 겹치면 `-eyeproxy.port <integer>19090</integer>` 형식의 launch 인자 대신 설정 창에서 포트를 바꾼다), 칩을 눌러 목록이 줄고 `All`로 돌아오는지, 검색어와 함께 적용되는지 확인. 스크린샷을 리포트에 첨부.
- [ ] **Step 4: 커밋** — `feat(ui): 목록 위 프로토콜·콘텐츠·상태 코드 필터 바`

### Task 3: `/ssl` 확장 — Android용 PEM·DER·`prog` 별칭·지문 (Kit)

**Files:**
- Modify: `Packages/EyeProxyKit/Sources/EyeProxyKit/Onboarding/CAProfileResponder.swift`
- Modify: `Packages/EyeProxyCore/Sources/EyeProxyCore/CertificateAuthority.swift` (지문 접근자)
- Test: `Packages/EyeProxyKit/Tests/EyeProxyKitTests/CAProfileResponderTests.swift`, `Packages/EyeProxyCore/Tests/EyeProxyCoreTests/CertificateAuthorityTests.swift`(있으면 추가, 없으면 생성)

**Interfaces:**
- Produces (Core): `public var sha256Fingerprint: String` — `certificateDER`의 SHA-256을 `AB:CD:…` 대문자 콜론 구분.
- Produces (Kit): `CAProfileResponder`가 host `eyeproxy` **또는** `prog`(대소문자 무시)에 응답. 경로: `/ssl`(UA에 `android` 포함 시 PEM, 아니면 mobileconfig), `/ssl.crt`·`/ssl.pem`(PEM, `Content-Type: application/x-x509-ca-cert`, `Content-Disposition: attachment; filename="EyeProxy-CA.crt"`), `/ssl.cer`(DER, `application/pkix-cert`, `EyeProxy-CA.cer`), `/`(링크 세 개 + 지문 텍스트). 생성자 시그니처는 그대로.

- [ ] **Step 1: 테스트 추가**
  - Core `fingerprintIsColonSeparatedSHA256`: 길이 95, 정규식 `^([0-9A-F]{2}:){31}[0-9A-F]{2}$`, 같은 CA는 같은 값.
  - Kit `sslServesPEMForAndroidUserAgent`: 헤더 `User-Agent: Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/120` → status 200, Content-Type `application/x-x509-ca-cert`, body == `Data(ca.certificatePEM.utf8)`; iOS UA(`… iPhone OS 17_0 … Safari`) → mobileconfig(기존 기대값).
  - `sslCrtPemCerPathsServeBytes`: `/ssl.crt`·`/ssl.pem` body == PEM, `/ssl.cer` body == `Data(ca.certificateDER)`, Content-Disposition 파일명 확인.
  - `progHostIsAlias`: host `prog`·`PROG`에 `/ssl` → 200; host `prog.example.com` → `.continue`.
  - `indexListsLinksAndFingerprint`: `/` body에 `/ssl`, `/ssl.crt`, `/ssl.cer`, `ca.sha256Fingerprint` 포함.
- [ ] **Step 2: 실패 확인** — Core·Kit 각각 `swift test --filter` 실패.
- [ ] **Step 3: 구현** — PEM·DER 응답은 각각 하나의 private 함수로. UA 검사는 `request.header("User-Agent")?.lowercased().contains("android") == true`.
- [ ] **Step 4: 통과 확인** — Core 55+1, Kit 전체 PASS.
- [ ] **Step 5: 커밋** — `feat(ca): /ssl이 Android엔 PEM, /ssl.crt·.cer 경로, prog 별칭, 지문 표시`

### Task 4: 인증서 내보내기 (Core 접근자 + Kit 내보내기)

**Files:**
- Modify: `Packages/EyeProxyCore/Sources/EyeProxyCore/CertificateAuthority.swift`
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Onboarding/CertificateExporter.swift`
- Test: `Packages/EyeProxyCore/Tests/EyeProxyCoreTests/CertificateAuthorityTests.swift`, `Packages/EyeProxyKit/Tests/EyeProxyKitTests/CertificateExporterTests.swift`

**Interfaces:**
- Produces (Core): `public var privateKeyPEM: String` (`key.pemRepresentation`, 기존 `save(to:)`가 쓰는 것과 같은 바이트).
- Produces (Kit):
  ```swift
  public enum CertificateExporter {
      public static func writePEM(_ ca: CertificateAuthority, to url: URL) throws
      public static func writeDER(_ ca: CertificateAuthority, to url: URL) throws
      /// 0600으로 생성. 기존 파일은 지우고 새로 만든다.
      public static func writePrivateKey(_ ca: CertificateAuthority, to url: URL) throws
      /// /usr/bin/openssl pkcs12 -export. 비밀번호는 환경 변수 P12PASS로만 전달(-passout env:P12PASS). 빈 비밀번호 허용.
      public static func writeP12(_ ca: CertificateAuthority, to url: URL, password: String) async throws
  }
  ```
- `Shell.run`은 Kit 내부 `enum Shell`(`System/Shell.swift`)에 있다. `Process`에 환경 변수를 넣어야 하므로 `Shell.run(_:_:stdin:environment:)` 오버로드를 추가한다(기존 호출은 그대로). 임시 키·인증서 파일은 `FileManager.default.temporaryDirectory` 아래 UUID 폴더(0700)에 쓰고 `defer`로 지운다.

- [ ] **Step 1: 테스트 작성**
  - Core `privateKeyPEMRoundTrips`: `P256.Signing.PrivateKey(pemRepresentation: ca.privateKeyPEM)`이 성공하고 공개키가 인증서의 것과 같다.
  - Kit `pemAndDerExportsMatchCA`: 쓴 파일 바이트 == `Data(ca.certificatePEM.utf8)` / `Data(ca.certificateDER)`.
  - `privateKeyExportOverwritesWithMode600`: 먼저 임의 내용·0644 파일을 만들어 두고 `writePrivateKey` → 내용이 `privateKeyPEM`이고 `posixPermissions == 0o600`.
  - `p12ExportIsReadableByOpenSSL`: `writeP12(password: "pw")` 뒤 `Shell.run("/usr/bin/openssl", ["pkcs12", "-in", path, "-info", "-nokeys", "-passin", "env:P12PASS"], environment: ["P12PASS": "pw"])` status 0, stdout에 `BEGIN CERTIFICATE` 포함. 빈 비밀번호도 한 번(`password: ""`, `-passin env:` 빈 값).
- [ ] **Step 2: 실패 확인.**
- [ ] **Step 3: 구현** — `writeP12`: 임시 폴더에 `key.pem`(0600)·`cert.pem` 쓰고 `openssl pkcs12 -export -inkey key.pem -in cert.pem -name "<ca.commonName>" -out <url> -passout env:P12PASS` 실행. status != 0이면 `CertificateExportError.openSSL(stderr)` throw. 출력 파일은 끝나고 0600으로 맞춘다.
- [ ] **Step 4: 통과 확인** — Core·Kit PASS.
- [ ] **Step 5: 커밋** — `feat(ca): PEM·DER·P12·개인키 내보내기`

### Task 5: CA 초기화(Reset) 회전 (Kit) + AppModel 적용

**Files:**
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Onboarding/CARotation.swift`
- Modify: `EyeProxy/AppModel.swift` (`certificateAuthority`를 `private(set) var`로, `resetCertificateAuthority()` 추가, `loadOrCreateCA`의 commonName 생성을 재사용 가능한 `static func defaultCommonName() -> String`으로 분리)
- Test: `Packages/EyeProxyKit/Tests/EyeProxyKitTests/CARotationTests.swift`

**Interfaces:**
- Produces (Kit):
  ```swift
  public enum CARotation {
      /// directory(…/ca)를 `ca-backup-<yyyyMMdd-HHmmss>[-n]`(형제 폴더)로 옮기고 새 CA를 생성·저장해 돌려준다. directory가 없으면 백업 없이 생성만.
      public static func rotate(directory: URL, commonName: String, now: Date = .now) throws -> (ca: CertificateAuthority, backup: URL?)
  }
  ```
- Produces (앱): `AppModel.resetCertificateAuthority() async` — `CARotation.rotate(directory: Self.caDirectory, commonName: Self.defaultCommonName())` → `certificateAuthority` 교체 → `await restartServer()` → `macCAInstalled` 갱신(`refreshMacCAInstalled`) → `systemError`가 아닌 별도 `var infoMessage: String?`에 "새 CA를 만들었습니다. 이전 CA는 <backup>에 있습니다. Mac·시뮬레이터·기기에 다시 설치하세요. 키체인의 이전 CA는 키체인 접근에서 지우세요." (`infoMessage`는 Task 6 창이 alert로 띄운다). 실패하면 `systemError`.
- `AppModel.startServer()`가 `certificateAuthority`를 어떻게 넘기는지 확인해(`ProxyServer`·`CAProfileResponder` 생성 지점) 재시작 때 새 CA가 들어가게 한다. 서버가 CA를 `let`으로 잡고 있어도 `restartServer()`가 새 `ProxyServer`를 만들면 된다 — 아니면 그렇게 고친다.

- [ ] **Step 1: 테스트 작성** — `CARotationTests.swift` (임시 폴더에서)
  - `rotateMovesOldAndCreatesNew`: 먼저 `CertificateAuthority.generate().save(to: dir)` → `rotate` → `backup`이 `dir`의 형제이고 안에 `ca.pem`·`ca-key.pem`; `dir`에 새 `ca.pem`이 있고 `CertificateAuthority.load(from: dir)?.certificateDER != 옛 DER`; 새 CA `commonName == 인자`.
  - `rotateWithoutExistingDirectoryJustCreates`: `backup == nil`, `dir`에 저장됨.
  - `rotateTwiceInSameSecondKeepsBothBackups`: 같은 `now`로 두 번 → 백업 두 개, 이름이 `…-HHmmss`와 `…-HHmmss-2`.
- [ ] **Step 2: 실패 확인.**
- [ ] **Step 3: 구현** — 백업 이름 충돌 시 `-2`, `-3`… 접미사. 키 파일 권한은 `save(to:)`가 보장.
- [ ] **Step 4: AppModel 변경** — 위 인터페이스대로. `certificateAuthority`를 읽는 곳(`grep -n certificateAuthority EyeProxy/`)이 모두 새 값을 보게 되는지 확인.
- [ ] **Step 5: 통과 확인 + 빌드.**
- [ ] **Step 6: 커밋** — `feat(ca): CA 초기화 — 백업 뒤 새 루트 CA 생성·서버 재시작`

### Task 6: Certificate 창 — 섹션 목록으로 재편

**Files:**
- Create: `EyeProxy/Views/Certificate/CertificateWindow.swift`, `EyeProxy/Views/Certificate/MacSection.swift`, `EyeProxy/Views/Certificate/SimulatorSection.swift`, `EyeProxy/Views/Certificate/AppleDevicesSections.swift`, `EyeProxy/Views/Certificate/ExportResetSection.swift`, `EyeProxy/AppModel+Certificate.swift`
- Modify: `EyeProxy/EyeProxyApp.swift:108`(`Window("기기", id: "devices")` → `Window("Certificate", id: "devices") { CertificateWindow() }`, `.defaultSize(width: 860, height: 600)`), `EyeProxy/AppModel.swift`(`certificateSection`), `project.yml` 불필요(sources는 폴더).
- Delete: `EyeProxy/Views/Devices/DevicesView.swift` (내용은 위 파일들로 이동). `ProfileFormView.swift`·`ConnectedDevicesSection.swift`는 그대로 두고 import해 쓴다.

**Interfaces:**
- Produces (앱):
  ```swift
  enum CertificateSection: String, CaseIterable, Identifiable {
      case mac, simulators, iosDevices, tvWatch, android, developments, exportReset, connectedDevices
      var title: LocalizedStringKey   // "이 Mac", "iOS 시뮬레이터", "iPhone·iPad", "Apple TV·Apple Watch", "Android", "개발 환경", "내보내기·초기화", "연결된 기기"
      var systemImage: String
  }
  // AppModel
  var certificateSection: CertificateSection = .mac
  var developmentPlatform: DevPlatform = .httpClients   // Task 8에서 타입이 생기면 그때 추가
  var infoMessage: String?                               // Task 5 참고
  // AppModel+Certificate.swift
  func installCAOnMacWithConfirmation()                  // NSAlert 확인 → installCAOnMac() → 결과는 infoMessage/systemError
  func exportCertificate(_ format: CertificateExportFormat)  // enum pem, der, p12, privateKey — NSSavePanel(기본 이름 EyeProxy-CA.pem/.cer/.p12, EyeProxy-CA-key.pem) → CertificateExporter
  func resetCertificatesWithConfirmation()               // NSAlert(§4.1 문구) → resetCertificateAuthority()
  ```
- P12는 비밀번호 입력이 필요하다: `NSAlert`에 `NSSecureTextField`를 `accessoryView`로 붙여 받는다(빈 값 허용). 개인키는 §4.1 경고 문구의 NSAlert 뒤에 저장 패널.
- `CertificateWindow`: `NavigationSplitView` 사이드바 `List(CertificateSection.allCases, selection: $model.certificateSection)`(폭 200), 상세는 `Form … .formStyle(.grouped)`에 섹션별 뷰. `.onAppear/.onDisappear`로 기존 `devicesWindowOpen`, `.task`로 기존 세 refresh, `.systemErrorAlert(model, presenting: true)`, `infoMessage` alert("확인" 누르면 nil). Android·개발 환경 섹션은 이 Task에서는 `ContentUnavailableView("준비 중")`을 두고 Task 7·8이 교체한다.
- `MacSection`/`SimulatorSection`은 기존 `DevicesView.macSection`/`simulatorSection` 본문 그대로 옮긴다(동작 변화 없음, `run` 헬퍼·`installedSimulators` 상태 포함).
- `AppleDevicesSections.swift`: `IOSDevicesSection`(ProfileFormView + iPhone·iPad 체크리스트 — 기존 문구에서 `http://eyeproxy/ssl` → `http://prog/ssl`), `TVWatchSection`(ProfileFormView + Apple TV 체크리스트 + "Apple Watch: 짝지은 iPhone에 프로필을 설치하면 Watch로 전달됩니다" 한 줄).
- `ExportResetSection`: 버튼 4개(PEM·DER·P12·개인키) + 구분선 + "Reset all EyeProxy Certificates…"(destructive). 현재 CA의 commonName과 `sha256Fingerprint`를 위에 표시.
- `연결된 기기` 섹션 = `ConnectedDevicesSection()` + `ConnectionLogSection()`.

- [ ] **Step 1: 파일 이동·창 작성** — 위 구조대로. `DevicesView` 삭제.
- [ ] **Step 2: 빌드** — `xcodegen generate` 후 Debug 빌드 성공.
- [ ] **Step 3: 수동 확인** — ⌘D로 창이 열리고 8개 섹션 전환, 시뮬레이터 섹션에서 부팅된 시뮬레이터가 보이면 버튼 하나로 설치되는 흐름이 그대로인지(설치 자체는 실행하지 않아도 됨 — 버튼이 있고 활성인지만). Export PEM을 실제로 저장해 바이트가 `ca.pem`과 같은지 `cmp`. 스크린샷 첨부.
- [ ] **Step 4: 커밋** — `feat(certificate): 기기 창을 Certificate 창(섹션 목록)으로 재편, 내보내기·초기화 UI`

### Task 7: Android 섹션 (Kit 명령 생성 + adb 탐색 + 뷰)

**Files:**
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Onboarding/AndroidSetup.swift`, `EyeProxy/Views/Certificate/AndroidSection.swift`
- Modify: `EyeProxy/Views/Certificate/CertificateWindow.swift`(준비 중 → `AndroidSection()`), `EyeProxy/AppModel+Certificate.swift`(실행 함수)
- Test: `Packages/EyeProxyKit/Tests/EyeProxyKitTests/AndroidSetupTests.swift`

**Interfaces:**
- Produces (Kit):
  ```swift
  public enum AndroidSetup {
      /// 후보: $ANDROID_HOME/platform-tools/adb, $ANDROID_SDK_ROOT/platform-tools/adb, ~/Library/Android/sdk/platform-tools/adb, PATH의 adb. 처음 실행 가능한 것.
      public static func locateADB(environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = .homeDirectory, fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> URL?
      public static func proxyArguments(host: String, port: Int) -> [String]   // ["shell","settings","put","global","http_proxy","<host>:<port>"]
      public static let clearProxyArguments: [String]                         // [... "http_proxy", ":0"]
      public static func pushArguments(crt: URL) -> [String]                   // ["push", crt.path, "/sdcard/Download/EyeProxy-CA.crt"]
      public static func commandLines(adb: String, host: String, port: Int, crt: URL) -> String  // 복사용 두 줄
      public static let connectArguments: (String) -> [String]                 // { ip in ["connect", "\(ip):5555"] }
      public static let installIntentArguments: [String]                       // ["shell","am","start","-a","android.intent.action.VIEW","-t","application/x-x509-ca-cert","-d","file:///sdcard/Download/EyeProxy-CA.crt"]
      public static func tvCommandLines(adb: String, tvIP: String, host: String, port: Int, crt: URL) -> String  // 복사용 네 줄: connect, 프록시, push, 설치 인텐트
      public static let networkSecurityConfigXML: String                       // 사용자 CA 허용 스니펫(§4.5)
  }
  ```
- Produces (앱): `AppModel.runADB(_ args: [String]) async -> String`(`Shell.run` 결과 stdout+stderr 합쳐 반환; Shell은 Kit internal이므로 Kit에 `public static func runADB(_ adb: URL, _ args: [String]) async throws -> (status: Int32, output: String)`를 `AndroidSetup`에 둔다), `exportCACrt()`(NSSavePanel `EyeProxy-CA.crt`, `CertificateExporter.writePEM`).
- 뷰: `Picker`(실기기 / 에뮬레이터 / Android TV, segmented). 세 단계 안내(§4.5 문구), 현재 `model.lanAddresses.first ?? "127.0.0.1"`·`model.runningPort ?? settings.port` 표시 + 복사 버튼. 주의 문구 + `networkSecurityConfigXML` 복사 버튼. 실기기 탭: `CA 저장(.crt)…`. 에뮬레이터 탭: 호스트는 `10.0.2.2`; `locateADB()`가 있으면 `adb로 프록시 설정 + CA 복사`·`adb로 프록시 해제` 버튼과 결과 텍스트, 없으면 `commandLines` 복사용 텍스트.
- Android TV 탭: 단계 — (1) TV 설정 ▸ 기기 환경설정 ▸ 정보 ▸ 빌드 7번 → 개발자 옵션 ▸ 네트워크 디버깅 켬, (2) `adb connect <TV IP>:5555` (TV IP 입력 칸), (3) 프록시 설정·CA 복사는 에뮬레이터와 같은 명령(호스트는 Mac LAN IP), (4) 설치 인텐트로 인증서 설치 화면을 띄워 리모컨으로 진행(없으면 설정 ▸ 보안 ▸ 저장소에서 설치). 주의 문구: "앱이 사용자 CA를 신뢰하려면 디버그 빌드에 network_security_config가 필요. Play가 없는 Android TV 에뮬레이터는 `adb root; adb remount` 뒤 /system/etc/security/cacerts/에 넣으면 시스템 CA로 모든 앱이 복호화된다(해시 파일명은 `openssl x509 -subject_hash_old`)". adb가 있으면 `adb connect` 버튼 + 에뮬레이터 탭과 같은 두 버튼 + `인증서 설치 화면 열기` 버튼, 없으면 `tvCommandLines` 복사용 텍스트.

- [ ] **Step 1: 테스트 작성** — `locateADBPrefersEnvThenHomeThenPath`(fileExists 클로저로 가짜 파일 시스템: ANDROID_HOME 있으면 그것, 없으면 홈 경로, 없으면 PATH 탐색, 아무것도 없으면 nil), `proxyAndPushArgumentsAreExact`, `commandLinesContainBoth`, `tvCommandLinesContainConnectAndIntent`(`connect <ip>:5555`와 `android.intent.action.VIEW`가 들어 있고 호스트가 Mac IP).
- [ ] **Step 2: 실패 확인.** **Step 3: 구현.** **Step 4: 통과 확인 + 빌드.**
- [ ] **Step 5: 수동 확인** — 세 탭 전환, adb 없는 Mac이면 명령 텍스트가 보이는지, 있으면 버튼이 보이는지(실행은 하지 않는다). 스크린샷.
- [ ] **Step 6: 커밋** — `feat(certificate): Android 실기기·에뮬레이터·TV CA 설치 안내와 adb 도우미`

### Task 8: 개발 환경 섹션 (Kit 스니펫 + 뷰)

**Files:**
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Onboarding/DevSnippets.swift`, `EyeProxy/Views/Certificate/DevelopmentsSection.swift`
- Modify: `CertificateWindow.swift`(준비 중 → `DevelopmentsSection()`), `AppModel.swift`(`developmentPlatform`)
- Test: `Packages/EyeProxyKit/Tests/EyeProxyKitTests/DevSnippetsTests.swift`

**Interfaces:**
- Produces (Kit):
  ```swift
  public enum DevPlatform: String, CaseIterable, Identifiable, Sendable {
      case httpClients, nodeJS, python, ruby, java, docker, electron, reactNative, flutter, nextJS, firefox
      public var title: String   // "HTTP Clients (curl·wget)", "NodeJS", "Python", "Ruby", "Java", "Docker", "Electron App", "React Native", "Flutter", "NextJS (fetch)", "Firefox Browsers"
  }
  public struct DevGuide: Sendable { public let steps: [String]; public let snippet: String }
  public enum DevSnippets {
      public static func guide(for platform: DevPlatform, pemPath: String, proxyHost: String, proxyPort: Int) -> DevGuide
  }
  ```
- 내용은 §4.6 핵심을 지킨다. `proxy = "http://\(proxyHost):\(proxyPort)"`. Docker는 host를 `host.docker.internal`로 치환. React Native는 스니펫 대신 시뮬레이터·Android 섹션을 가리키는 steps만. Java는 keytool 명령 + `-Dhttps.proxyHost`. Firefox는 `about:config` 안내.
- 뷰: 왼쪽 `List(DevPlatform.allCases, selection: $model.developmentPlatform)`(폭 180) + 오른쪽 steps 번호 목록 + 스니펫 `TextEditor`(읽기 전용, 모노스페이스) + 복사 버튼. pemPath는 `AppModel.caDirectory.appending(path: "ca.pem").path`, host `127.0.0.1`, port `runningPort ?? settings.port`.

- [ ] **Step 1: 테스트 작성** — `everyPlatformMentionsPemAndProxy`: `DevPlatform.allCases` 각각 `guide(...)`의 `snippet + steps.joined()`에 pemPath가 들어 있고(React Native 제외), `proxyHost:proxyPort` 또는 `host.docker.internal:port`(Docker)가 들어 있다. `nodeUsesExtraCACerts`: nodeJS 스니펫에 `NODE_EXTRA_CA_CERTS=`. `pythonUsesRequestsBundle`: `REQUESTS_CA_BUNDLE=`과 `SSL_CERT_FILE=`.
- [ ] **Step 2: 실패 확인.** **Step 3: 구현.** **Step 4: 통과 확인 + 빌드.**
- [ ] **Step 5: 수동 확인** — 섹션에서 플랫폼을 바꾸면 스니펫이 바뀌고 복사가 되는지. 스크린샷.
- [ ] **Step 6: 커밋** — `feat(certificate): 개발 환경별 CA·프록시 설정 안내`

### Task 9: Certificate 메뉴, Tools ▸ Proxy Settings, "프록시" 메뉴 제거

**Files:**
- Create: `EyeProxy/Commands/CertificateCommands.swift`
- Modify: `EyeProxy/EyeProxyApp.swift:29-37`(`CommandMenu("프록시")` 삭제, `CertificateCommands(model:)` 추가 — `ToolsCommands` 뒤에 두면 메뉴 순서가 Flow·Tools·Certificate), `EyeProxy/Commands/ToolsCommands.swift:86-90`(`Import Settings` 뒤 `Divider()` + `Menu("Proxy Settings")`)

**Interfaces:**
- Consumes: Task 6 `AppModel.certificateSection`, `installCAOnMacWithConfirmation()`, `exportCertificate(_:)`, `resetCertificatesWithConfirmation()`; Task 8 `DevPlatform`, `AppModel.developmentPlatform`.
- Produces: `struct CertificateCommands: Commands` — §4.1 트리 그대로. 섹션 항목은 `model.certificateSection = …`(개발 환경 항목은 `developmentPlatform`도) 뒤 `openWindow(id: "devices")`. 메뉴 맨 아래 `Divider()` + `Button("Certificate & Devices Window…") { openWindow(id: "devices") }.keyboardShortcut("d")`(기존 `OpenDevicesButton` 대체·삭제).
- `Proxy Settings` 하위: `Toggle("Record Traffic", isOn: Bindable(model.settings).isRecording).keyboardShortcut("r")`, `Toggle("Override macOS Proxy", isOn: Binding(get: { model.macCaptureEnabled || model.effectiveProxyLeftover }, set: { on in Task { await model.setMacCapture(on) } })).disabled(model.macCaptureBusy)`, `Divider()`, `Button("Restart Server") { Task { await model.restartServer() } }.keyboardShortcut("r", modifiers: [.command, .shift])`, `Button("Bypass Proxy Settings…") { model.settingsTab = .bypass; openSettings() }`.
- `Window`를 이미 열어 둔 상태에서 메뉴를 누르면 `openWindow(id:)`가 창을 앞으로 가져오고 섹션만 바뀐다(SwiftUI `Window` 기본 동작).

- [ ] **Step 1: 구현.** **Step 2: 빌드.**
- [ ] **Step 3: 수동 확인** — 메뉴 막대에 "프록시"가 없고 Certificate가 있으며, 각 항목이 해당 섹션으로 창을 여는지; ⌘R·⇧⌘R·⌘D가 동작하는지; Install on this Mac…이 확인 alert를 띄우는지(취소로 닫는다 — 설치는 하지 않는다). 스크린샷.
- [ ] **Step 4: 커밋** — `feat(menu): Certificate 메뉴와 Tools ▸ Proxy Settings, 프록시 메뉴 제거`

### Task 10: 아이콘 에셋 생성 스크립트와 카탈로그

**Files:**
- Create: `scripts/make-icons.sh`, `EyeProxy/Assets.xcassets/AppIcon.appiconset/{Contents.json, icon_16.png, icon_16@2x.png, icon_32.png, icon_32@2x.png, icon_128.png, icon_128@2x.png, icon_256.png, icon_256@2x.png, icon_512.png, icon_512@2x.png}`, `EyeProxy/Assets.xcassets/MenuBarFrogOpen.imageset/{Contents.json, open.png, open@2x.png}`, 같은 식으로 `MenuBarFrogClosed`, `MenuBarFrogSubmerged`
- Modify: `project.yml`(앱 타깃 `settings.base`에 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`)
- 원본: `Design/AppIcon.svg`, `Design/MenuBar-{Open,Closed,Submerged}.svg` (이미 레포에 있음)

**Interfaces:**
- Produces: 이미지 이름 `"MenuBarFrogOpen"`, `"MenuBarFrogClosed"`, `"MenuBarFrogSubmerged"`(Task 11이 `Image(_:)`로 쓴다), 앱 아이콘 `AppIcon`.
- 스크립트: `set -euo pipefail`; 임시 폴더에 `qlmanage -t -s <px> -o <tmp> <svg>` → 산출 `<name>.svg.png`를 카탈로그 이름으로 복사. 앱 아이콘 px: 16, 32, 64, 128, 256, 512, 1024 (16@2x=32, 32@2x=64, 128@2x=256, 256@2x=512, 512@2x=1024). 메뉴 막대: 18, 36. `Contents.json`의 imageset에 `"template-rendering-intent": "template"`. 끝에 `sips -g pixelWidth`로 각 파일 크기를 검증해 다르면 exit 1. 스크립트는 산출물을 레포에 쓰고, 커밋은 사람이 한다(빌드마다 돌리지 않는다).

- [ ] **Step 1: 스크립트 작성·실행** — `./scripts/make-icons.sh` → 산출물 생성, 검증 통과.
- [ ] **Step 2: `project.yml` 수정, `xcodegen generate`, Debug 빌드** — 빌드된 앱 번들에 `Assets.car`가 있고 Finder에서 앱 아이콘이 개구리로 보인다(스크린샷: Finder 아이콘 보기 + 목록 보기 16px).
- [ ] **Step 3: 16px 판독 확인** — 목록 보기에서 눈 두 개와 입이 구분되지 않으면 `Design/AppIcon-small.svg`(혀·패킷 없는 단순판)를 만들어 16·32px에만 쓰도록 스크립트를 고친다. 구분되면 이 단계는 "불필요"로 리포트.
- [ ] **Step 4: 커밋** — `feat(icon): 개구리 앱 아이콘·상태 막대 템플릿 에셋과 생성 스크립트`

### Task 11: 상태 막대 메뉴 (MenuBarExtra)

**Files:**
- Create: `EyeProxy/Views/StatusBar/StatusMenu.swift`
- Modify: `EyeProxy/EyeProxyApp.swift`(`WindowGroup`에 `id: "main"` 부여 — 현재 선언을 확인해 id가 없으면 추가; `MenuBarExtra` 씬 추가), `Packages/EyeProxyKit/Sources/EyeProxyKit/AppSettings.swift`(`showStatusItem`), `EyeProxy/Views/Settings/SettingsView.swift`(`GeneralSettings`에 토글)
- Test: `Packages/EyeProxyKit/Tests/EyeProxyKitTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: Task 10 이미지 이름; `AppModel.serverState`, `settings.isRecording`, `setMacCapture`, `lanAddresses`, `runningPort`, `settings.toolSwitches`, `restartServer`.
- Produces (Kit): `AppSettings.showStatusItem: Bool`(키 `eyeproxy.showStatusItem`, 기본 true).
- Produces (앱): `AppModel.statusIconName: String` — `.running` + `isRecording` → `"MenuBarFrogOpen"`, `.running` + 기록 꺼짐 → `"MenuBarFrogClosed"`, `.stopped`/`.failed` → `"MenuBarFrogSubmerged"`. `struct StatusMenu: View`(메뉴 내용, §5 트리 그대로).
- 씬: `MenuBarExtra(isInserted: Bindable(model.settings).showStatusItem) { StatusMenu().environment(model) } label: { Image(model.statusIconName) }` — `.menuBarExtraStyle(.menu)`.
- 메뉴 내용: 첫 줄 `Text`(비활성) "EyeProxy — Listening on <ip>:<port>" / "EyeProxy — Stopped"(`lanAddresses.first` 없으면 `127.0.0.1`); `Toggle("Record Traffic")`; `Toggle("macOS Proxy Overridden")`(Task 9와 같은 바인딩·disabled); `Menu("Listen on IP")`에 `127.0.0.1:<port>`와 `lanAddresses` 각각 `Button` → `NSPasteboard.general` 복사; `Menu("Enable/Disable Tools")`에 Tools 메뉴와 같은 토글 6개 + `No Caching`; `Button("Open EyeProxy") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }`; `Button("Quit EyeProxy") { NSApp.terminate(nil) }.keyboardShortcut("q")`.

- [ ] **Step 1: 테스트** — `AppSettingsTests`에 `showStatusItemPersists`(기본 true, false 저장 후 재로드 false).
- [ ] **Step 2: 실패 확인 → Kit 구현 → 통과.**
- [ ] **Step 3: 앱 구현 + 빌드.**
- [ ] **Step 4: 수동 확인** — 메뉴 막대에 개구리가 뜨고, 기록 토글에 따라 눈이 뜨고 감기며(툴바 ▶ 와 동기), 서버를 중지하면(설정에서 포트를 바꾸고 재시작 전 상태로는 안 되므로 `Restart Server` 중 잠깐, 또는 포트 충돌 유발) 물결만 남는지; Listen on IP 복사; 설정 토글로 아이콘이 사라지는지. 메인 창을 닫고 `Open EyeProxy`로 다시 열리는지. 스크린샷(라이트·다크 각 1장).
- [ ] **Step 5: 커밋** — `feat(statusbar): 상태 막대 개구리 메뉴 — 기록·Mac 프록시·Listen IP·도구 스위치·종료`

### Task 12: 표시 이름 Prog으로 변경 (번들 ID 유지)

**Files:**
- Modify: `project.yml`(`PRODUCT_NAME: Prog`, Debug `PRODUCT_NAME: Prog-Debug`; `PRODUCT_MODULE_NAME: EyeProxy`와 번들 ID·`name: EyeProxy`는 유지), `EyeProxy/Info.plist`(CFBundleName·CFBundleDisplayName `Prog`, `UTTypeDescription` "Prog Session"), `scripts/release.sh`(`APP_NAME="Prog"`, appcast `<title>Prog</title>`; `SCHEME`·`SPARKLE_BIN`·`REPO`는 유지; sed가 `EyeProxy/Info.plist` 경로를 쓰는 줄은 그대로), `EyeProxy/AppModel.swift`(`defaultCommonName` → `"Prog Root CA (<host>)"`), `Packages/EyeProxyCore/Sources/EyeProxyCore/CertificateAuthority.swift:25-27`(기본 commonName `"Prog Root CA"`, `OrganizationName("Prog")`), `Packages/EyeProxyKit/Sources/EyeProxyKit/Onboarding/MobileConfig.swift`(표시 이름·파일명·organization → Prog; PayloadIdentifier `com.tv.eyeproxy.*` 유지), `CAProfileResponder.swift`(파일명 `Prog-CA.*`, `<title>Prog</title>`), `Packages/EyeProxyCore/Sources/EyeProxyCore/ProxyServer.swift:176`("Prog: upstream error"), `EyeProxy/AppModel.swift:465`(프로필 파일명 `Prog-<ssid>.mobileconfig`), 사용자에게 보이는 모든 `"EyeProxy"` 문자열(`grep -rn "EyeProxy" EyeProxy/ --include=*.swift`로 전수 — 창 제목·안내·alert·상태 막대 제목·Task 6~11에서 쓴 "EyeProxy-CA" 기본 파일명·"Open EyeProxy"·"Quit EyeProxy"), `EyeProxy/Localizable.xcstrings`(빌드가 자동 갱신하는 것을 커밋), `README.md`(제목 `# Prog`, 첫 줄에 "이전 이름 EyeProxy", 본문 앱 이름 Prog — 레포 주소·클론 경로·`com.tv.eyeproxy`·`Packages/EyeProxyKit` 같은 식별자는 그대로), `CLAUDE.md` 첫 줄.
- Test: `MobileConfigTests.swift`, `CAProfileResponderTests.swift`, `CertificateAuthorityTests.swift` 기대값 갱신.

**Interfaces:** 코드 식별자 변경 없음. 유지 목록(§8.1): 번들 ID, 모듈·폴더·스킴, `eyeproxy.*` 키, `.eyeproxy`·`.eyeproxyrules`, 규칙 JSON `"eyeproxy"` 키, Application Support 경로, Sparkle 피드 URL, 레포 이름, `http://eyeproxy/ssl` 별칭.

- [ ] **Step 1: 기대값부터 고친다** — 테스트 세 파일의 "EyeProxy" 문자열을 Prog으로, 실패 확인.
- [ ] **Step 2: 치환** — 위 파일 목록대로. `grep -rn "EyeProxy" EyeProxy/ Packages/*/Sources --include=*.swift`의 남은 결과가 모두 식별자(타입·모듈·키·경로)인지 리포트에 목록으로 적는다.
- [ ] **Step 3: 테스트·빌드** — Core·Kit PASS, Debug 빌드 산출물이 `Prog-Debug.app`이고 `defaults read <app>/Contents/Info.plist CFBundleIdentifier`가 `com.tv.eyeproxy.debug`.
- [ ] **Step 4: 수동 확인** — 앱 메뉴가 "Prog", 상태 막대 제목 "Prog — Listening on …", 기존 설정·규칙·CA가 그대로 로드되는지(UserDefaults·Application Support가 같으므로 그래야 한다).
- [ ] **Step 5: 커밋** — `chore(rename): 표시 이름 EyeProxy → Prog (번들 ID·식별자 유지)`

### Task 13: 문서 — README 기능 설명과 핸드오버 수동 점검표

**Files:**
- Modify: `README.md`(`## 첫 실행`·`## 기기 연결`을 Certificate 메뉴 기준으로 다시 쓰고, `## Tools` 뒤에 `## 필터 바`·`## 상태 막대 메뉴`·`## Certificate 메뉴` 절 추가; `## 알려진 제한` 에 "WebSocket 필터 없음", "Android는 사용자 CA까지만", "P12는 macOS openssl 필요")
- Create: `docs/superpowers/plans/2026-11-08-eyeproxy-certificate-menubar-filter-handover.md` — 수동 점검표: Mac CA 설치(관리자 인증), 시뮬레이터 설치, iPhone `http://prog/ssl`·`http://eyeproxy/ssl`, Android Chrome `/ssl` → `.crt`, adb 버튼, P12를 키체인 접근으로 가져오기, Reset 뒤 기기 재설치, 상태 막대 세 상태, 필터 바 조합, 0.2.0에서 Sparkle 업데이트로 Prog.app이 되는지.

- [ ] **Step 1: 작성.** **Step 2: 링크·명령 오타 확인(`grep -n "eyeproxy/ssl" README.md`는 별칭 설명 한 곳만).** **Step 3: 커밋** — `docs: Certificate·필터 바·상태 막대 설명과 수동 점검표`
