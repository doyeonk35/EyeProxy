# Certificate 메뉴·상태 막대·필터 바·개구리 아이콘 설계

작성일 2026-11-08. 대상: EyeProxy 0.2.0(Tools 1차 묶음 머지 후).

## 1. 의도

EyeProxy의 메뉴 막대와 메인 화면을 Proxyman에 익숙한 사용자가 헤매지 않게 맞춘다. 구체적으로 네 가지다.

1. "프록시" 메뉴를 없애고 Proxyman과 같은 **Certificate** 메뉴를 만든다. 지금은 CA 설치가 기기 창(⌘D) 안에 흩어져 있어 "인증서를 어디서 설치하지?"가 첫 질문이 된다.
2. 메인 화면 목록 위에 Proxyman과 같은 **필터 바**(프로토콜·콘텐츠 종류·상태 코드)를 둔다. 지금은 검색어와 사이드바로만 거른다.
3. **상태 막대 메뉴**(메뉴 바 아이콘)에서 기록·Mac 프록시·Listen 주소·도구 스위치·종료에 바로 닿게 한다. 메인 창이 다른 데스크톱에 있어도 토글할 수 있어야 한다.
4. 앱 아이콘이 없다(Assets.xcassets에 Colors만 있음). **개구리** 아이콘을 넣고 상태 막대 아이콘도 같은 캐릭터로 맞춘다. 앱 이름도 이번에 **Prog**(frog)으로 바꾼다(§8). 캐릭터는 그 이름에서 왔다.

Proxyman의 메뉴 구조는 실제 앱의 접근성 트리에서 읽어 왔다(2026-11-08). 아래 "Proxyman 기준"이라고 적은 것은 그 결과다.

## 2. 목표·비목표·반목표

**목표**
- Certificate 메뉴에서 Proxyman이 제공하는 항목 중 우리가 실제로 동작시킬 수 있는 것은 전부 제공한다.
- 켜진 iOS·tvOS 시뮬레이터에 버튼 하나로 CA를 설치하는 기존 기능은 그대로 유지하고 더 찾기 쉽게 만든다.
- 필터 바는 Proxyman과 같은 세 묶음, 같은 칩 이름, 같은 조합 규칙.
- 상태 막대 메뉴는 메인 창 없이도 쓸 수 있다.
- 아이콘은 앱(Dock·Finder)과 상태 막대 두 벌, 라이트·다크 모두.

**비목표(이번 묶음에서 하지 않음)**
- WebSocket 캡처와 WebSocket 필터 칩. Core에 Upgrade 처리가 없다.
- Proxyman의 Atlantis·Add Custom Certificates·Java VMs 스크립트·Install on Developments ▸ VPN·Diff·Scripting.
- Android 시스템 CA 설치(루팅 필요). 사용자 CA 설치까지만 안내한다.

**반목표(이렇게 되면 실패)**
- 기존 기기 창의 시뮬레이터 설치 흐름이 더 깊어지거나 클릭이 늘어난다.
- 상태 막대 메뉴에서 Mac 프록시를 켜고 끄는데 메인 창의 상태와 어긋난다.
- 필터 칩을 눌렀는데 검색어·사이드바 선택이 풀린다(필터는 누적이어야 한다).
- 앱 아이콘이 16px에서 녹색 덩어리로만 보인다.

## 3. 제약

- Swift 6 strict concurrency, SwiftUI, macOS 15+. 외부 패키지는 CLAUDE.md의 허용 목록만(새 패키지 금지). 모듈 방향 `EyeProxy` → `EyeProxyKit` → `EyeProxyCore`.
- 필터 로직은 `EyeProxyKit`(`FlowFilter`)에 두고 테스트한다. 뷰는 앱에만.
- 시스템 프록시·키체인·CA 신뢰 변경은 사용자가 버튼을 눌렀을 때만 일어난다. 자동 테스트나 에이전트가 `networksetup -set*`, `security add-trusted-cert`, `simctl keychain`을 실행하지 않는다.
- 비밀값(CA 개인키 내용, Wi-Fi 비밀번호)을 로그·클립보드·문서에 남기지 않는다. 개인키 내보내기는 사용자가 저장 위치를 고른 파일에만 쓴다.
- 공개 레포: 커밋되는 파일에 회사 내부 도메인·로컬 사용자 경로를 넣지 않는다.
- 메뉴 항목 이름은 Proxyman처럼 영어(Install Certificate on this Mac…). 안내 문장·설명은 한국어. 기존 메뉴(Flow·Tools)와 같은 관행.

## 4. 메뉴 막대 재편

### 4.1 Certificate 메뉴 (Proxyman 기준, 빠진 항목은 §2 비목표)

```
Certificate
  Install Certificate on this Mac…
  ─
  Install Certificate on iOS         ▸  Physical Devices…
                                        Simulators…
                                        watchOS or tvOS…
  Install Certificate on Android     ▸  Physical Devices…
                                        Emulators…
  ─
  Install Certificate on Developments ▸ HTTP Clients (curl·wget)…
                                        NodeJS…
                                        Python…
                                        Ruby…
                                        Java…
                                        Docker…
                                        Electron App…
                                        React Native…
                                        Flutter…
                                        NextJS (fetch)…
  Install Certificate on Firefox Browsers…
  ─
  Export                             ▸  Root Certificate as PEM…
                                        Root Certificate as DER…
                                        Root Certificate as P12…
                                        Private Key…
  ─
  Reset all EyeProxy Certificates…
```

항목마다 하는 일:

| 항목 | 동작 |
|---|---|
| Install on this Mac… | 확인 알림("로그인 키체인에 EyeProxy CA를 추가하고 SSL 신뢰를 켭니다. 관리자 인증이 필요합니다.") → 기존 `AppModel.installCAOnMac()` → 결과 알림. 창을 열지 않는다. |
| iOS ▸ Simulators… | Certificate 창(§4.3)을 **시뮬레이터** 섹션으로 연다. 부팅된 시뮬레이터마다 "CA 설치" 버튼(기존 `installCA(toSimulator:)`)과 설치됨 표시. 기존 동작 그대로. |
| iOS ▸ Physical Devices… | Certificate 창을 **iPhone·iPad** 섹션으로 연다. 기존 실기기 프로필 폼(`ProfileFormView`) + `http://eyeproxy/ssl` 안내. |
| iOS ▸ watchOS or tvOS… | Certificate 창을 **Apple TV·Apple Watch** 섹션으로 연다. 기존 Apple TV 체크리스트 + 프로필 폼. watchOS는 "짝지은 iPhone에서 프로필을 설치하면 Watch로 전달된다"는 안내 한 줄. |
| Android ▸ Physical Devices… | Certificate 창을 **Android** 섹션(실기기 탭)으로 연다. §4.5. |
| Android ▸ Emulators… | 같은 섹션의 에뮬레이터 탭. §4.5. |
| Developments ▸ … | Certificate 창을 **개발 환경** 섹션으로 열고 해당 플랫폼을 선택한 상태. §4.6. |
| Firefox Browsers… | 개발 환경 섹션의 Firefox 항목. |
| Export ▸ PEM / DER | `NSSavePanel`(기본 이름 `EyeProxy-CA.pem` / `.cer`) → `CertificateAuthority.certificatePEM` / `certificateDER` 저장. |
| Export ▸ P12 | 비밀번호 입력 시트(비워 둘 수 있음) → `/usr/bin/openssl pkcs12 -export`로 생성. 비밀번호는 `-passout env:` 로 넘기고(인자에 노출 금지) 임시 키 파일은 0600, 끝나면 삭제. openssl이 없거나 실패하면 오류 알림. |
| Export ▸ Private Key… | 경고 알림("이 키로 누구나 EyeProxy CA를 신뢰하는 기기의 HTTPS를 가로챌 수 있습니다") → `NSSavePanel`(`EyeProxy-CA-key.pem`) → `privateKeyDER`의 PEM 저장, 0600. |
| Reset all EyeProxy Certificates… | 확인 알림("새 루트 CA를 만듭니다. Mac·시뮬레이터·기기에 설치한 CA는 모두 다시 설치해야 합니다.") → 기존 `ca/` 폴더를 `ca-backup-<yyyyMMdd-HHmmss>/`로 옮김 → `CertificateAuthority.generate` + `save` → 서버 다시 시작 → 완료 알림. Mac 키체인의 옛 CA 제거는 하지 않는다(사용자가 키체인 접근에서 지우도록 알림에 적는다). |

### 4.2 "프록시" 메뉴 제거, 항목 이동

Proxyman 기준: 기록은 메뉴 막대에 없고 툴바 ▶ 와 상태 막대 메뉴에 있다. "서버 다시 시작"은 없다. 프록시 관련은 Tools ▸ Proxy Settings 하위다.

- "프록시" 메뉴(`EyeProxyApp.swift` `CommandMenu("프록시")`)를 지운다.
- Tools 메뉴 끝에 Proxyman처럼 구분선 + `Proxy Settings` 하위 메뉴를 추가한다.
  ```
  Proxy Settings ▸ Record Traffic            ⌘R   (토글, settings.isRecording)
                   Override macOS Proxy           (토글, 이 Mac 캡처 = model.setMacCapture)
                   ─
                   Restart Server             ⇧⌘R
                   Bypass Proxy Settings…          (설정 창 Bypass 탭)
  ```
  Proxyman에는 Record Traffic·Restart가 메뉴에 없지만 SwiftUI에서 단축키는 메뉴 항목이 있어야 동작하므로 여기 둔다(내 결정). 툴바 ▶ 버튼과 ⌘R 동작은 그대로.
- `기기…`(⌘D)는 Certificate 창을 여는 항목이 되어 Certificate 메뉴 맨 아래 구분선 뒤 `Certificate & Devices Window… ⌘D`로 남긴다. 사용자 습관(⌘D) 유지.

### 4.3 Certificate 창 (기존 기기 창의 후속)

기존 `DevicesView`(139줄: Mac 섹션·시뮬레이터 섹션·체크리스트·연결된 기기)를 설정 창처럼 **왼쪽 섹션 목록 + 오른쪽 내용**으로 재편한다. 창 제목 "Certificate", id는 기존 `devices` 유지, ⌘D.

섹션(위에서부터): `이 Mac` / `iOS 시뮬레이터` / `iPhone·iPad` / `Apple TV·Apple Watch` / `Android` / `개발 환경` / `내보내기·초기화` / `연결된 기기`.

- `이 Mac`: 기존 macSection 그대로(CA 설치 버튼, 이 Mac 캡처 토글, 잔여 프록시 경고).
- `iOS 시뮬레이터`: 기존 simulatorSection 그대로. **클릭 수가 늘면 안 된다**: 창이 열리면서 바로 이 섹션이면 지금과 동일하게 한 번 클릭으로 설치.
- `iPhone·iPad`·`Apple TV·Apple Watch`: 기존 프로필 폼 + 체크리스트를 플랫폼별로 나눔.
- `Android`·`개발 환경`: §4.5·§4.6.
- `내보내기·초기화`: Export 네 가지와 Reset 버튼(메뉴와 같은 동작).
- `연결된 기기`: 기존 `ConnectedDevicesSection`.

`AppModel`에 `certificateSection: CertificateSection`(enum, 위 8개)을 두고 Certificate 메뉴 항목은 이 값을 바꾼 뒤 창을 연다. 창이 이미 열려 있으면 앞으로 가져오며 섹션만 바뀐다.

### 4.4 `http://eyeproxy/ssl` 확장 (`CAProfileResponder`)

- `/ssl`: User-Agent에 `Android`가 있으면 PEM(`Content-Type: application/x-x509-ca-cert`, 파일명 `EyeProxy-CA.crt`), 아니면 지금처럼 mobileconfig.
- `/ssl.crt`, `/ssl.pem`: 항상 PEM(위 헤더). `/ssl.cer`: DER(`application/pkix-cert`).
- `/`: 안내 페이지에 세 링크(iOS 프로파일 / Android·기타 `.crt` / DER) 와 현재 CA의 SHA-256 지문.

### 4.5 Android 섹션

탭 세 개: 실기기 / 에뮬레이터 / Android TV. 모두 단계별 안내 + 버튼. Android TV는 설정에 프록시·인증서 UI가 없으므로 adb(네트워크 디버깅, `adb connect <TV IP>:5555`)로 에뮬레이터와 같은 명령을 쓰고, 인증서 설치 화면은 `am start -a android.intent.action.VIEW -t application/x-x509-ca-cert -d file:///sdcard/Download/<crt>` 인텐트로 띄운다. Play 없는 Android TV 에뮬레이터는 `adb root; adb remount`로 시스템 CA 설치가 가능하다고 안내한다(2026-11-08 추가).

실기기:
1. Wi-Fi 설정 ▸ 프록시 수동 ▸ Mac IP·포트 입력(현재 LAN IP·포트를 그대로 보여 주고 복사 버튼).
2. Chrome으로 `http://eyeproxy/ssl` 열기 → `EyeProxy-CA.crt` 다운로드.
3. 설정 ▸ 보안 ▸ 암호화 및 사용자 인증 정보 ▸ 인증서 설치 ▸ CA 인증서 → 다운로드한 파일 선택.
안내 아래 주의: "Android 7 이상 앱은 사용자 CA를 기본으로 신뢰하지 않는다. 디버그 빌드에 `network_security_config`로 사용자 CA를 허용해야 한다." + 복사용 XML 스니펫.
버튼: `CA 저장(.crt)…`(NSSavePanel).

에뮬레이터: 같은 안내에, `adb`가 있으면(`$ANDROID_HOME/platform-tools/adb`, `~/Library/Android/sdk/platform-tools/adb`, PATH 순) 버튼 `adb로 프록시 설정 + CA 복사` 가 보인다. 실행:
`adb shell settings put global http_proxy <MacIP>:<port>` 와 `adb push <ca.crt> /sdcard/Download/EyeProxy-CA.crt`. 결과(성공/stderr)를 안내 아래 표시. 되돌리기 버튼 `adb로 프록시 해제`(`settings put global http_proxy :0`). adb가 없으면 두 명령을 복사용으로 보여 준다. 에뮬레이터에서 Mac IP 대신 `10.0.2.2`를 쓴다고 안내.

### 4.6 개발 환경 섹션

왼쪽에 플랫폼 목록(HTTP Clients·NodeJS·Python·Ruby·Java·Docker·Electron·React Native·Flutter·NextJS·Firefox), 오른쪽에 절차와 복사 버튼 달린 스니펫. 스니펫의 CA 경로는 실제 파일 `~/Library/Application Support/com.tv.eyeproxy/ca/ca.pem` 의 절대 경로를 채워 넣는다(읽기 전용 파일이므로 그대로 참조해도 된다). 프록시 주소는 `http://127.0.0.1:<port>`.

각 항목에 들어갈 핵심(빌더가 문장을 다듬는다):
- HTTP Clients: `export HTTPS_PROXY=… HTTP_PROXY=… SSL_CERT_FILE=<pem>`; curl 단독은 `curl --proxy … --cacert <pem>`.
- NodeJS: `NODE_EXTRA_CA_CERTS=<pem>` + `HTTPS_PROXY`(Node 20+ fetch는 프록시 env를 안 읽으므로 `undici`의 `EnvHttpProxyAgent` 또는 `global-agent` 안내).
- Python: `REQUESTS_CA_BUNDLE=<pem>`, `SSL_CERT_FILE=<pem>`, `HTTPS_PROXY`.
- Ruby: `SSL_CERT_FILE=<pem>`, `HTTPS_PROXY`.
- Java: `keytool -importcert -trustcacerts -alias eyeproxy -file <pem> -keystore $JAVA_HOME/lib/security/cacerts` + `-Dhttps.proxyHost/-Dhttps.proxyPort`.
- Docker: 컨테이너에서 Mac은 `host.docker.internal`; `-e HTTPS_PROXY=http://host.docker.internal:<port>` + CA 마운트 후 `update-ca-certificates`.
- Electron: `--proxy-server=127.0.0.1:<port>` + `NODE_EXTRA_CA_CERTS` 또는 `app.commandLine.appendSwitch('ignore-certificate-errors')`(개발용).
- React Native: iOS 시뮬레이터는 시뮬레이터 섹션으로 안내, Android는 Android 섹션으로 + Metro는 프록시를 안 탄다는 메모.
- Flutter: `HttpClient.findProxy` + `SecurityContext.setTrustedCertificates(<pem>)` 코드 조각.
- NextJS: `NODE_EXTRA_CA_CERTS` + `HTTPS_PROXY`(Node 항목과 같음, fetch 메모).
- Firefox: `about:config` ▸ `security.enterprise_roots.enabled = true`(Mac 키체인 CA를 따라감) 또는 설정 ▸ 인증서 보기 ▸ 가져오기 `<pem>`.

### 4.7 기존 코드 연결점

- `EyeProxy/EyeProxyApp.swift` 30–37행 `CommandMenu("프록시")`, 137행 `OpenDevicesButton`.
- `EyeProxy/Commands/ToolsCommands.swift` `ToolsMenu`.
- `EyeProxy/Views/Devices/{DevicesView,ProfileFormView,ConnectedDevicesSection}.swift`.
- `EyeProxy/AppModel.swift`: `installCAOnMac()` 445행, `installCA(toSimulator:)` 455행, `setMacCapture` 359행 부근, `caDirectory` 23행, CA 생성 118–123행, `lanAddresses`, `runningPort`, `serverState`.
- `Packages/EyeProxyCore/Sources/EyeProxyCore/CertificateAuthority.swift`: `certificateDER`·`certificatePEM`·`privateKeyDER`·`generate`·`save`·`load`.
- `Packages/EyeProxyKit/Sources/EyeProxyKit/Onboarding/CAProfileResponder.swift`.

## 5. 상태 막대 메뉴

SwiftUI `MenuBarExtra`(window style 아님, 메뉴 스타일). 설정 ▸ 일반에 `상태 막대에 아이콘 표시` 토글(기본 켬, 키 `eyeproxy.showStatusItem`).

```
    Show EyeProxy                                     (앱 활성화 + 메인 창 앞으로; 닫혀 있으면 다시 연다)
    ─
    ✓ Record Traffic                                  (settings.isRecording)
    ✓ macOS Proxy Overridden                          (model.setMacCapture; 변경 중엔 비활성)
    ─
    Listen on 192.168.0.12:9090  ▸  Copy                 (ip:port 복사)
                                    ─
                                    Copy IP / Copy Port
                                    ─
                                    Copy Shell Command   (export https_proxy=http://ip:port http_proxy=http://ip:port)
                                 (주소는 LAN 첫 주소, 없으면 127.0.0.1; 중지면 제목 "Listen on — (Stopped)", 비활성)
    ─
    Enable/Disable Tools  ▸  Breakpoint ─ Map Local·Map Remote ─ Block List·Allow List ─ Network Conditions ─ No Caching ─ SSL Proxying List   (toolSwitches 토글 + sslEnabled; Proxyman처럼 구분선으로 묶음)
    ─
    Quit EyeProxy                      ⌘Q             (NSApp.terminate → 기존 프록시 복원 경로를 탄다)
```
(2026-11-08 변경: Proxyman 상태 메뉴 순서를 그대로 따른다 — Show가 맨 위, 제목 줄 없이 Listen on 항목이 주소를 보여 준다.)

아이콘(템플릿, 18pt, 1x·2x PNG 또는 PDF 한 장):
- 기록 중: 물 위로 눈을 내민 개구리, 눈 뜸.
- 서버 켜짐·기록 꺼짐: 같은 개구리, 눈 감음.
- 서버 중지·실패: 개구리 없음. 물결선 + 공기방울 두 개(물속으로 들어감).
눈동자·공기방울은 투명(알파)으로 뚫어 막대 색이 비친다. `Image(…).renderingMode(.template)`. Mac 프록시 덮어씀 여부는 아이콘에 표시하지 않는다(메뉴 체크로 충분; 이전 안의 "점"은 뺌).

상태 전이: `serverState`·`settings.isRecording` 변화에 즉시 따라간다. 메인 창의 토글·툴바와 같은 모델 값을 바인딩하므로 어긋날 수 없다.

## 6. 필터 바

### 6.1 위치·모양

메인 창에서 툴바 바로 아래, 목록 위에 한 줄. `FlowListView`를 감싸는 컨테이너의 맨 위(레이아웃 위아래·좌우 모두 같은 자리). 높이 28pt, 수평 스크롤(지시자 숨김), 창이 좁으면 오른쪽이 잘려 스크롤.

```
[All] │ HTTP  HTTPS │ JSON  Form  XML  JS  CSS  GraphQL  Document  Media  Other │ 1xx  2xx  3xx  4xx  5xx
```

칩은 텍스트 버튼(캡션 크기). 선택되면 강조색 배경 캡슐 + 흰 글자, 아니면 보조색 글자. 묶음 사이는 세로 구분선. `All`은 아무것도 안 골랐을 때 선택 상태로 보인다.

### 6.2 규칙

- 묶음 안: 여러 개 선택 가능, OR. 묶음 사이: AND. 세 묶음 모두 비어 있으면 전체(=All).
- `All` 클릭: 세 묶음 모두 비움.
- 검색어·사이드바(기기·프로세스·호스트·고정)·"숨김 포함"과 AND로 누적된다. 필터 바를 바꿔도 다른 조건은 그대로.
- 세션 동안만 유지(앱 재시작 시 All). 저장하지 않는다.
- 선택 행이 필터에서 사라지면 기존 검색어 동작과 같게 처리(선택 해제, 상세 창 비움).

### 6.3 분류 (`EyeProxyKit`, 순수 함수, 테스트 대상)

- 프로토콜: `flow.request.scheme == "https"` → HTTPS, 아니면 HTTP. 복호화하지 않은 CONNECT 터널 행도 HTTPS.
- 콘텐츠 종류(`ContentKind`): 아래 순서로 처음 맞는 것. `type`은 응답 `Content-Type`(없으면 요청 `Content-Type`)의 `;` 앞부분을 소문자로.
  1. GraphQL: 요청 path(쿼리 제외)에 `graphql`이 들어가거나 요청 Content-Type이 `application/graphql`.
  2. Form: **요청** Content-Type이 `application/x-www-form-urlencoded` 또는 `multipart/form-data`.
  3. JSON: `type`에 `json` 포함(`application/json`, `+json`, `text/json`).
  4. XML: `xml` 포함(`+xml` 포함).
  5. JS: `javascript` 또는 `ecmascript` 포함.
  6. CSS: `text/css`.
  7. Document: `text/html`, `text/plain`, `application/pdf`, `text/markdown`, `text/csv`.
  8. Media: `image/`, `video/`, `audio/`, `font/`로 시작하거나 `application/font-*`, `application/x-font-*`, `application/vnd.apple.mpegurl`, `application/x-mpegurl`, `video/mp2t`.
  9. Other: 나머지(`Content-Type` 없음, `application/octet-stream`, CONNECT 터널 등).
- 상태 코드: `flow.response?.status / 100` → 1…5. 응답이 없는 행은 상태 묶음이 비어 있을 때만 통과한다.

`FlowFilter`에 `protocols: Set<FlowProtocol>`, `contentKinds: Set<ContentKind>`, `statusClasses: Set<Int>` 세 필드를 더하고 `matches`에서 검사한다. 분류 함수는 `ContentKind.of(_ flow: Flow)`, `FlowProtocol.of(_ flow: Flow)`.

### 6.4 기존 코드 연결점

- `Packages/EyeProxyKit/Sources/EyeProxyKit/FlowFilter.swift`(`matches(_:process:)`), 테스트 `Packages/EyeProxyKit/Tests/EyeProxyKitTests/FlowFilterTests.swift`(있으면 확장, 없으면 생성).
- `EyeProxy/Views/MainWindow.swift` 13–28행(`FlowListView` 배치 두 곳), `EyeProxy/Views/Toolbar/MainToolbar.swift`.
- `AppModel.filter`와 `visibleRows`.

## 7. 앱 아이콘

캐릭터: 정면 개구리 얼굴. 녹색 그라데이션 배경(#2fd36f → #149a4a), 연두 머리, 흰 눈 + 짙은 동공, 웃는 입, 분홍 혀가 오른쪽 아래로 뻗어 흰 패킷(요청)을 물고 있음. 원본 SVG는 레포의 `Design/AppIcon.svg`(이 문서와 같은 커밋에 들어 있다). 그대로 쓴다.

- 원본 SVG(레포에 이미 있음): `Design/AppIcon.svg`(1024 기준), `Design/MenuBar-Open.svg`, `Design/MenuBar-Closed.svg`, `Design/MenuBar-Submerged.svg`(18 기준, 검정 단색 + 투명 구멍 = 템플릿).
- `scripts/make-icons.sh`: SVG → PNG(`qlmanage -t -s <size> -o <dir>`; 2026-11-08에 네 원본 모두 확인했다. 루트 `<svg>`에 width/height가 있으면 qlmanage가 그 크기로 고정하므로 원본은 viewBox만 둔다. 산출 PNG는 알파 포함) → `EyeProxy/Assets.xcassets/AppIcon.appiconset`(16·32·128·256·512 각 1x·2x)과 `MenuBarFrogOpen/Closed/Submerged.imageset`(18·36, template). 스크립트는 산출물을 커밋 대상으로 만든다(빌드마다 돌리지 않는다).
- `project.yml`에 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. Debug 번들(`EyeProxy-Debug`)도 같은 아이콘.
- 16px에서 눈 두 개와 입이 구분되는지 Finder 목록 보기로 확인한다. 안 되면 16·32용은 혀·패킷을 빼고 눈·입만 남긴 단순판을 쓴다(빌더 판단).
- Dock 배지(Breakpoint 멈춘 개수)는 아이콘과 무관하게 계속 동작해야 한다.

## 8. 앱 이름 변경: EyeProxy → Prog (표시 이름만)

이번 묶음에서 바꾼다(2026-11-08 결정). **번들 ID `com.tv.eyeproxy`(.debug)는 유지한다** — 그래야 0.2.0 사용자가 Sparkle로 그대로 업데이트되고, UserDefaults·Application Support·설치된 CA·프로파일이 전부 이어진다. 바꾸는 것은 사용자가 보는 이름이다. 코드 안의 식별자(모듈·폴더·키·UTI·레포)는 그대로 둔다.

Sparkle 확인 결과(소스 `SUUpdateValidator.m`·`SUInstaller.m`): 업데이트 검증은 EdDSA 서명 또는 코드 서명 일치로 통과하고 번들 ID를 비교하지 않는다. (2026-11-08 정정) 링크된 Sparkle은 `SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME = 0`이라 `SUInstaller`가 호스트의 기존 번들 경로에 그대로 설치한다. 즉 0.2.0 → Prog 자동 업데이트는 되지만(번들 ID 일치) 디스크의 파일명은 `/Applications/EyeProxy.app`으로 남고 실행하면 "Prog"으로 보인다. 파일명을 바꾸려면 Finder에서 이름을 바꾸거나 zip으로 재설치하고 옛 복사본을 지운다(같은 번들 ID라 둘 다 두면 안 된다). 단 Sparkle 피드 URL이 지금 자리(`https://doyeonk35.github.io/EyeProxy/appcast.xml`)에 남아 있어야 하므로 **GitHub 레포 이름도 EyeProxy로 둔다**(이 문서의 결정; 레포 이름을 바꾸면 0.2.0의 자동 업데이트가 끊긴다).

### 8.1 바뀌는 것

| 항목 | 현재 | 변경 | 비고 |
|---|---|---|---|
| 제품 이름·표시 이름 | EyeProxy / EyeProxy-Debug | **Prog** / **Prog-Debug** | `project.yml` PRODUCT_NAME, Info.plist CFBundleName·CFBundleDisplayName. 앱 메뉴 "Quit Prog", 상태 막대 제목, 창 제목, 알림 문구. |
| 릴리스 산출물 | `EyeProxy-<v>.zip`, appcast `<title>EyeProxy</title>` | `Prog-<v>.zip`, `<title>Prog</title>` | `scripts/release.sh`의 APP_NAME. SCHEME과 SPARKLE_BIN(DerivedData `EyeProxy-*`) 경로는 프로젝트 이름이 그대로라 유지. 기존 appcast 항목(0.1.x·0.2.0)은 건드리지 않는다. |
| CA 이름 | "EyeProxy Root CA (<host>)", O=EyeProxy | 새로 만들 때만 "Prog Root CA (<host>)", O=Prog | 이미 설치된 CA는 그대로(바꾸면 전 기기 재설치). Reset(§4.1)으로 새 이름의 CA를 만들 수 있다. |
| 안내 호스트 | `http://eyeproxy/ssl` | **`http://prog/ssl`**, `eyeproxy`도 계속 응답 | 기기에 이미 적힌 주소가 깨지지 않게 별칭 유지. 안내문·README는 `prog`로. |
| mobileconfig 표시 이름·파일명 | "EyeProxy CA (…)", "EyeProxy 프록시 (<ssid>)", `EyeProxy-CA.mobileconfig`, organization EyeProxy | "Prog CA (…)", "Prog 프록시 (<ssid>)", `Prog-CA.mobileconfig`, Prog | PayloadIdentifier(`com.tv.eyeproxy.ca.*`, `.wifi.*`)는 유지 — 같은 식별자라 기기에서 옛 프로파일을 덮어쓴다. |
| 세션 파일 | `.eyeproxy`, UTI `com.tv.eyeproxy.session`, 설명 "EyeProxy Session" | 확장자·UTI 유지, 설명 "Prog Session" | 확장자를 바꾸면 UTI 추가·마이그레이션이 생기므로 이번엔 설명만. |
| 규칙 묶음 `.eyeproxyrules`, 규칙 JSON 키 `"eyeproxy"`, UserDefaults `eyeproxy.*`, Application Support `com.tv.eyeproxy/`, 임시 파일 접두사 | — | 유지 | 내부 식별자. |
| 사용자에게 보이는 문자열 | "EyeProxy: upstream error", 안내 페이지 `<title>EyeProxy</title>`, 설정·기기 창·알림의 "EyeProxy" | Prog | `grep -rn "EyeProxy" --include=*.swift`로 전수 조사. Localizable.xcstrings 포함. |
| README·CLAUDE.md·핸드오버 문서 | EyeProxy | 제목·본문은 Prog, 레포 주소·클론 경로는 EyeProxy 그대로 | 과거 스펙·플랜 문서(`docs/superpowers/`)는 역사 기록이라 그대로 둔다. "EyeProxy였던 앱"을 README 첫 줄에 한 번 적는다. |
| Xcode 프로젝트·스킴·폴더·모듈(EyeProxyCore/Kit)·GitHub 레포 | — | 유지 | 위 결정. |

### 8.2 순서

§4~§7을 먼저 끝내고(그동안 새로 쓰는 사용자 문자열은 처음부터 "Prog"으로), 이름 변경은 마지막 커밋 하나로 한다. 0.2.0 → 다음 릴리스 노트에 "앱 이름이 Prog으로 바뀌었고 설정·인증서는 그대로"를 적는다.

## 9. 빌더에게 맡기는 것

- Certificate 창의 정확한 레이아웃(섹션 목록 폭, 각 섹션 내부 배치)과 창 크기.
- 개발 환경 스니펫의 정확한 문장·명령 세부(위 §4.6 핵심은 지킨다).
- 필터 바 칩의 색·간격·폰트, 구분선 두께.
- SVG → PNG 변환 도구 선택과 스크립트 세부.
- 테스트 구성: 분류 함수·`FlowFilter` 조합 규칙·`CAProfileResponder` 경로별 응답·Export PEM/DER 바이트 동일성은 자동 테스트. 키체인·시스템 프록시·adb·openssl 실행은 수동 점검 항목으로 핸드오버 문서에 적는다.
- Reset 시 백업 폴더 이름 형식과 보존 개수(최소 1개는 남긴다).
