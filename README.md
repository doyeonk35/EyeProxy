# Prog

이전 이름은 EyeProxy다(0.2.0까지). 번들 ID·설정·인증서·레포 주소는 그대로다.

macOS용 MITM 디버깅 프록시 (Proxyman류). Mac·시뮬레이터·Apple TV·iPhone의 HTTP(S) 트래픽을 한 화면에서 본다. macOS 15+ / Swift 6.

## 설치

1. GitHub Releases에서 최신 `Prog-<version>.zip`을 받는다.
2. 압축을 풀어 `Prog.app`을 `/Applications`로 옮긴다. (Developer ID 서명·공증 완료 — 바로 실행된다.)
3. 이후 업데이트는 앱 메뉴 `Prog > 업데이트 확인…` (Sparkle).

## 첫 실행

1. 처음 켜면 루트 CA가 자동 생성된다.
2. 메뉴 **Certificate ▸ Install Certificate on this Mac…** → 확인 → 관리자 인증 → 로그인 키체인에 추가되고 SSL 신뢰가 설정된다. Certificate 창(⌘D) › 이 Mac의 **Mac에 CA 설치**와 같다.
3. Certificate 창 › 이 Mac의 **이 Mac 캡처**(메뉴 Tools ▸ Proxy Settings ▸ Override macOS Proxy, 상태 막대 메뉴 macOS Proxy Overridden도 같은 스위치)를 켜면 활성 네트워크 서비스의 HTTP·HTTPS 프록시가 `127.0.0.1:9090`으로 설정된다. 끄거나 종료하면 원래대로 복원된다.
4. 기록은 툴바 버튼(⌘R)으로 켜고 끈다. 기록 중이면 ▶, 일시정지면 ⏸로 보인다.

## 기기 연결

모든 기기 설치는 **Certificate** 메뉴나 Certificate 창(⌘D, Certificate ▸ Certificate & Devices Window…)에서 한다. 창 왼쪽 섹션은 `이 Mac` / `iOS 시뮬레이터` / `iPhone·iPad` / `Apple TV·Apple Watch` / `Android` / `개발 환경` / `내보내기·초기화` / `연결된 기기`이고, 메뉴 항목은 해당 섹션을 골라 창을 연다(열려 있으면 앞으로 가져와 섹션만 바꾼다).

- **Mac**: 위 첫 실행 절차. 브라우저·앱 트래픽이 바로 잡힌다. 사이드바는 Mac 트래픽을 프로세스별로 나눈다. Safari·WKWebView의 XPC 헬퍼 트래픽은 책임 앱 아래로 묶이고, 시뮬레이터 앱은 "<앱> (<플랫폼> 시뮬레이터)"로, curl 같은 명령줄 도구는 자기 이름으로 표시된다.
- **시뮬레이터**: Certificate ▸ Install Certificate on iOS ▸ Simulators… → 부팅된 iOS·tvOS 시뮬레이터마다 **CA 설치** → 시뮬레이터 앱 재실행.
- **iPhone·iPad / Apple TV**: Install Certificate on iOS ▸ Physical Devices… 또는 watchOS or tvOS… → **실기기 프로필 만들기**에서 SSID·보안 유형·비밀번호·Mac IP·포트를 입력해 `Prog-<SSID>.mobileconfig`(Wi-Fi + 수동 프록시)를 저장한다. Apple TV는 Apple Configurator로 페어링 후 프로필을 드래그, iPhone·iPad는 AirDrop·메일로 전달한다. 그다음 기기에서 `http://prog/ssl`로 CA 프로필을 설치하고 `인증서 신뢰 설정`에서 신뢰한다. Apple Watch는 짝지은 iPhone에 설치하면 전달된다. (프로필에 Wi-Fi 비밀번호가 평문으로 들어가며 앱은 비밀번호를 저장하지 않는다.)
- **Android**: Install Certificate on Android ▸ Physical Devices… / Emulators… → Android 섹션의 실기기·에뮬레이터·Android TV 탭(아래 Certificate 메뉴 절).
- **개발 환경**: Install Certificate on Developments ▸ … / Firefox Browsers… → 개발 환경 섹션의 플랫폼별 스니펫.

자세한 내용은 `docs/superpowers/specs/2026-11-05-eyeproxy-design.md` §7, Certificate 메뉴·창은 `docs/superpowers/specs/2026-11-08-eyeproxy-certificate-menubar-filter-design.md` §4.

## Tools

메뉴 **Tools**와 요청 우클릭 ▸ Tools에서 연다. 도구마다 창 맨 위 `Enable <Tool> Tool` 체크가 전체 스위치이고(메뉴 Tools ▸ Enable/Disable Tools에도 있음), 규칙은 위에서 아래로 검사해 처음 맞는 하나만 적용한다.

- **Breakpoint**: 맞는 요청·응답을 멈추고 Breakpoints 창에서 고쳐 보낸다(Continue Original ⌘. / Drop Connection ⌘\ / Apply & Execute ⌘↩). 자주 쓰는 헤더는 Breakpoint Templates로 저장한다.
- **Map Local**: 응답을 로컬 파일(HTTP 메시지 원문, `.http`) 또는 폴더로 바꾼다. 서버에 요청을 보내지 않는다.
- **Map Remote**: 요청을 다른 scheme·host·port·path·query로 보낸다(Host 헤더 유지 선택 가능).
- **Block List**: 요청을 막거나(목록에 표시/숨김) 숨기기만 한다. 앱 단위 차단도 된다.
- **Allow List**: 켜면 규칙에 맞는 요청만 기록·조작하고 나머지는 기록 없이 그대로 통과시킨다.
- **No Caching**: 복호화되는 요청에서 캐시 헤더를 지우고 `no-cache`를 붙인다.
- **Network Conditions**: 호스트(또는 전체)에 3G 같은 느린 네트워크 프로필을 씌운다. 한 번에 규칙 하나만 켜진다.
- **Compose / Repeat**: 요청을 새로 만들거나(⌥⌘C, `curl …` 붙여 넣기 가능) 목록의 요청을 다시 보낸다(Flow ▸ Repeat ⌘↩, Edit and Repeat… ⌥⌘↩).

**쿼리**: 규칙 편집기의 `쿼리: 무시 | 선택한 항목만 | 전체 일치`. 새 규칙은 **무시**가 기본이라 요청 URL에서 `?` 뒤를 떼고 비교하므로 `https://host/path` 하나가 쿼리가 다른 요청에 모두 맞는다(Proxyman에서 붙이던 `?*`가 필요 없다). **선택한 항목만**은 표에서 체크한 쿼리 항목만 비교한다(키는 정확히, 값은 `*`·`?` 와일드카드, 값이 `*`면 키만 있으면 됨, 체크 안 한 항목은 있든 없든 상관없음). 우클릭 ▸ Tools로 만든 규칙은 요청의 쿼리가 체크 해제로 표에 들어오니 필요한 것만 체크하면 되고, URL 칸에 쿼리가 든 URL을 붙여 넣으면 쿼리가 표로 옮겨진다. Proxyman에서 가져온 규칙은 **전체 일치**로 들어와 Proxyman과 똑같이 동작한다.

**자동 복호화**: 켜진 도구의 켜진 규칙이 가리키는 HTTPS 호스트는 SSL Proxying 목록에 없어도 자동으로 복호화한다(Proxyman은 이런 규칙을 조용히 무시한다). 정규식 규칙과 host가 `*`뿐인 규칙은 모든 HTTPS를 복호화하게 되므로 제외되며, 규칙 옆 주황 경고대로 SSL Proxying 목록에 호스트를 직접 넣어야 한다.

**Proxyman에서 가져오기**: **Tools ▸ Import Settings ▸ From Proxyman…** 은 `~/Library/Application Support/com.proxyman.NSProxy/user-data/`를 읽기만 하고(쓰지 않음) 도구별 개수를 보여 준다. 고른 도구의 규칙은 기존 Prog 규칙 **끝에** 추가되고, 같은 규칙(id)은 다시 가져와도 건너뛴다. Map Local 응답 파일은 Prog 폴더로 복사한다. 가져온 도구는 꺼진 상태로 두므로 각 도구 창에서 켠다. SSL Proxying 목록도 함께 가져올 수 있다.
각 도구 창 **More ▸ Export…** 는 `<도구 이름>.eyeproxyrules` 폴더(Proxyman 내보내기와 같은 `rules.config` + 응답 파일 `map-local/`)를 만든다. 다른 Mac에서는 그 도구 창의 **More ▸ Import…** 로 이 폴더(또는 안의 `rules.config`)나 Proxyman 내보내기 `.config`·`.json`을 고른다.

**저장 위치**: `~/Library/Application Support/com.tv.eyeproxy/rules/`(도구별 JSON, Proxyman과 같은 모양) · Map Local 응답 파일은 `…/com.tv.eyeproxy/map-local/`(Map Local More ▸ Default Local File Folder로 변경 가능) · 도구 스위치는 앱 설정(UserDefaults).

**Proxy Settings**: 예전 "프록시" 메뉴는 없어지고 Tools 맨 아래 **Proxy Settings** 하위 메뉴로 옮겼다 — Record Traffic ⌘R · Override macOS Proxy(이 Mac 캡처) · Restart Server ⇧⌘R · Bypass Proxy Settings…(설정 창 Bypass 탭).

## Certificate 메뉴

```
Certificate
  Install Certificate on this Mac…
  ─
  Install Certificate on iOS           ▸ Physical Devices… / Simulators… / watchOS or tvOS…
  Install Certificate on Android       ▸ Physical Devices… / Emulators…
  ─
  Install Certificate on Developments  ▸ HTTP Clients (curl·wget)… / NodeJS… / Python… / Ruby… / Java… /
                                         Docker… / Electron App… / React Native… / Flutter… / NextJS (fetch)…
  Install Certificate on Firefox Browsers…
  ─
  Export                               ▸ Root Certificate as PEM… / DER… / P12… / Private Key…
  ─
  Reset all Prog Certificates…
  ─
  Certificate & Devices Window…        ⌘D
```

- **this Mac**: 확인 알림 → 관리자 인증 → 결과 알림. 창을 열지 않는다(Certificate 창이 닫혀 있으면 결과는 메인 창에 뜬다).
- **iOS·Android·Developments·Firefox**: Certificate 창을 해당 섹션(Android는 탭, 개발 환경은 플랫폼)으로 연다.
- **Android 섹션**: 탭 세 개.
  - 실기기: Wi-Fi ▸ 프록시 수동에 Mac IP·포트(복사 버튼) → Chrome으로 `http://prog/ssl` → `Prog-CA.crt` 다운로드 → 설정 ▸ 보안 ▸ 암호화 및 사용자 인증 정보 ▸ 인증서 설치 ▸ CA 인증서. `CA 저장(.crt)…` 버튼도 있다.
  - 에뮬레이터: Mac 주소는 `10.0.2.2`. adb가 있으면 `adb로 프록시 설정 + CA 복사`(`settings put global http_proxy` + `/sdcard/Download/Prog-CA.crt`로 push)·`adb로 프록시 해제` 버튼, 없으면 복사용 명령을 보여 준다. adb는 `$ANDROID_HOME/platform-tools`, `~/Library/Android/sdk/platform-tools`, PATH 순으로 찾고 **창을 만들 때 한 번만** 찾으므로 adb를 설치했으면 Prog를 다시 켠다.
  - Android TV: 개발자 옵션 ▸ 네트워크 디버깅 → `adb connect` 버튼(TV IP 입력, `:5555`) → 에뮬레이터와 같은 프록시·CA 복사(호스트는 Mac LAN IP) → `인증서 설치 화면 열기`(CA 설치 인텐트, 리모컨으로 진행).
  - 아래 주의: Android 7 이상 앱은 사용자 CA를 기본으로 신뢰하지 않으므로 디버그 빌드에 `network_security_config`(XML 복사 버튼)가 필요하다.
- **개발 환경 섹션**: HTTP Clients·NodeJS·Python·Ruby·Java·Docker·Electron·React Native·Flutter·NextJS·Firefox별 절차와 복사 버튼 달린 스니펫. CA 경로는 `~/Library/Application Support/com.tv.eyeproxy/ca/ca.pem`의 절대 경로, 프록시는 `http://127.0.0.1:<포트>`(Docker는 `host.docker.internal`)로 채워진다.
- **`/ssl` 주소**: 기기가 Prog를 프록시로 쓸 때 호스트 `prog`로 응답한다(이전 주소 `http://eyeproxy/ssl`도 계속 동작).
  - `/ssl`: iOS·macOS는 `Prog-CA.mobileconfig`, User-Agent에 Android가 있으면 PEM `Prog-CA.crt`.
  - `/ssl.crt`·`/ssl.pem`: 항상 PEM. `/ssl.cer`: DER.
  - `/`: 세 링크와 현재 CA의 SHA-256 지문이 있는 안내 페이지(지문은 Certificate 창 › 내보내기·초기화에도 보인다).
- **Export**: PEM(`Prog-CA.pem`)·DER(`Prog-CA.cer`)은 바로 저장. P12는 비밀번호(비워도 됨)를 받아 `/usr/bin/openssl pkcs12`로 만들고 비밀번호는 명령 인자에 노출하지 않는다. Private Key는 경고 확인 뒤 `Prog-CA-key.pem`을 0600으로 저장한다 — 이 키가 있으면 Prog CA를 신뢰하는 모든 기기의 HTTPS를 가로챌 수 있다.
- **Reset all Prog Certificates…**: 확인 → `…/com.tv.eyeproxy/ca/`를 `ca-backup-<yyyyMMdd-HHmmss>/`로 옮기고 새 루트 CA(`Prog Root CA (<호스트>)`)를 만든 뒤 서버를 다시 시작한다. Mac·시뮬레이터·기기는 모두 다시 설치해야 한다. Mac 키체인의 옛 CA는 지우지 않으니 키체인 접근에서 직접 지운다.

## 필터 바

메인 창 툴바 바로 아래, 목록 위 한 줄(위아래·좌우 레이아웃 모두).

```
[All] │ HTTP  HTTPS │ JSON  Form  XML  JS  CSS  GraphQL  Document  Media  Other │ 1xx  2xx  3xx  4xx  5xx
```

- 묶음 안은 OR, 묶음 사이는 AND. 아무것도 안 고르면 `All`이 선택된 것으로 보이고, `All`을 누르면 세 묶음을 모두 비운다.
- 검색어·사이드바(기기·프로세스·호스트·고정)·숨김 포함과 AND로 겹친다. 필터 바를 바꿔도 다른 조건은 그대로다. 선택한 행이 걸러지면 선택이 풀린다.
- 저장하지 않는다(앱을 다시 켜면 `All`).
- 분류(칩에 마우스를 올리면 규칙이 보인다): 프로토콜은 scheme(복호화 안 한 터널은 HTTPS). 콘텐츠는 응답 `Content-Type`(없으면 요청) 기준으로 GraphQL(경로에 `graphql` 또는 `application/graphql`) → Form(요청이 urlencoded·multipart) → JSON → XML → JS → CSS → Document(html·plain·pdf·markdown·csv) → Media(이미지·영상·오디오·폰트·HLS) → Other 순서로 처음 맞는 것. 상태 칩을 고르면 응답 없는 행은 빠진다.

## 상태 막대 메뉴

메뉴 막대의 개구리 아이콘. Proxyman 상태 메뉴와 같은 순서다.

```
Show Prog
─
✓ Record Traffic
✓ macOS Proxy Overridden
─
Listen on 192.168.0.12:9090  ▸ Copy / Copy IP / Copy Port / Copy Shell Command
─
Enable/Disable Tools         ▸ Breakpoint / Map Local · Map Remote / Block List · Allow List /
                               Network Conditions / No Caching / SSL Proxying List
─
Quit Prog                    ⌘Q
```

- **Show Prog**: 앱을 앞으로 가져오고 메인 창이 닫혀 있으면 다시 연다.
- 토글은 메인 창과 같은 값이다 — Record Traffic = 툴바 ▶/⏸·⌘R, macOS Proxy Overridden = 이 Mac 캡처(바꾸는 중엔 비활성), SSL Proxying List = 툴바 자물쇠, 도구 스위치 = Tools ▸ Enable/Disable Tools.
- **Listen on**: LAN 첫 주소(없으면 `127.0.0.1`)와 포트. Copy Shell Command는 `export https_proxy=http://<ip>:<port> http_proxy=http://<ip>:<port>`. 서버가 멈추면 `Listen on — (Stopped)`로 비활성.
- **Quit Prog**: 일반 종료와 같아서 시스템 프록시를 원래대로 되돌린다.
- **아이콘**: 기록 중이면 물 위로 눈을 내민 개구리(눈 뜸), 서버는 켜졌는데 기록이 꺼지면 눈 감은 개구리, 서버가 멈추거나 실패하면 물결과 공기방울만. 템플릿 이미지라 밝은·어두운 메뉴 막대 색을 따른다.
- 설정 ▸ 일반 **상태 막대에 아이콘 표시**(기본 켬)로 숨기고 보인다.
- 앱 아이콘(녹색 개구리)과 상태 막대 아이콘 원본은 `Design/*.svg`이고, `scripts/make-icons.sh`가 `Assets.xcassets`의 PNG를 다시 만든다(산출물은 커밋).

## 문제 해결

### 네트워크 복구(긴급)

"이 Mac 캡처"가 켜진 채 Prog가 죽어 Mac 인터넷이 안 되면: Prog를 다시 켜고 **복원**을 고른다. 앱을 켤 수 없으면 터미널에서 끈다(`Wi-Fi` 자리에 `networksetup -listallnetworkservices`로 확인한 서비스 이름).

```bash
networksetup -setwebproxystate "Wi-Fi" off
networksetup -setsecurewebproxystate "Wi-Fi" off
```

### VPN(GlobalProtect) 사용 중

GlobalProtect처럼 VPN이 기본 서비스가 되면 실효 프록시(`scutil --proxy`)는 Wi-Fi가 아니라 VPN 서비스의 State 키(`State:/Network/Service/gpd.pan/Proxies`)를 따른다. VPN은 연결할 때만 Wi-Fi 프록시를 복사해 가고 이후 Wi-Fi 변경은 따라오지 않는다(켜도 적용 안 됨, 꺼도 복사본이 남음 — Proxyman도 같은 문제). 그래서 Prog는 VPN 상태에서 **켤 때** VPN State 키의 원본을 백업에 저장한 뒤 Prog 프록시를 직접 쓰고, **끌 때** 그 원본을 그대로 되돌린다(켤 때·끌 때 각각 관리자 인증 1회, 나머지 VPN 설정은 유지). Certificate 창(⌘D) › 이 Mac에 "VPN 상태에서는 켜고 끌 때 관리자 인증이 필요합니다"가 보이면 이 경우다. 켤 때 인증을 취소하면 Wi-Fi도 원래대로 돌아간다.

원본이 없는 복사본(캡처 중 VPN 연결, 이전 버전 백업)은 끌 때 HTTP·HTTPS 중 Prog 쪽만 끈다. 되돌리기에 실패하면 "이 Mac"에 주황 경고가 뜬다 — "이 Mac 캡처"를 끄면(경고가 있으면 토글이 켜진 것으로 보인다) 다시 시도하고, 그래도 안 되면 **VPN을 재연결**한다 — VPN이 프록시를 새로 받는다. 옮길 수 없는 VPN 설정(중첩 항목)이 있으면 덮어쓰지 않고 실패 처리하므로(켜기도 "적용하지 못했습니다"로 실패) 이때도 VPN 재연결로 복구한다.

앱 없이 긴급 복구할 때는 서비스 ID(`scutil <<< "show State:/Network/Global/IPv4"`의 `PrimaryService`, GlobalProtect는 `gpd.pan`)를 넣어 실행한다. `ExceptionsList`는 `scutil <<< "show State:/Network/Service/gpd.pan/Proxies"`에 보이는 목록을 그대로 옮긴다.

```bash
sudo scutil <<'EOF'
d.init
d.add FTPPassive # 1
d.add HTTPEnable # 0
d.add HTTPSEnable # 0
d.add ExceptionsList * dns.google one.one.one.one beacons.gvt2.com beacons2.gvt2.com ocsp.digicert.com
set State:/Network/Service/gpd.pan/Proxies
quit
EOF
```

`scutil --proxy`에 `HTTPEnable : 0`이 보이면 복구된 것이다.

### 포트 9090 충돌

Proxyman 등 다른 프록시가 9090을 쓰고 있으면 시작에 실패한다. 그 앱을 끄거나 설정에서 포트를 바꾼다.

### 방화벽

첫 실행 때 "들어오는 연결 허용" 창이 뜨면 **허용**해야 Apple TV·iPhone이 연결된다.

### 업데이트·다운로드

GitHub 레포가 private이면 Sparkle 업데이트와 Release 다운로드가 동작하지 않는다(공개 레포 또는 유료 플랜 필요).

## 알려진 제한(P1)

- HTTP/1.1만 지원하고 응답 전체를 버퍼링한다. `*`를 SSL 목록에 넣으면 WebSocket·SSE 스트림이 끊길 수 있다.
- 복호화하는 호스트의 CONNECT 행은 목록에 표시되지 않고, 기기 쪽 TLS 핸드셰이크 실패는 Certificate 창 › 연결된 기기의 연결 로그에만 보인다.

## 알려진 제한(Tools 1차)

- Compose·Repeat로 `https://localhost`·`https://127.0.0.1`에 보내면 Prog를 거치지 않는다(URLSession이 루프백 HTTPS는 프록시를 쓰지 않음). 기록·도구 적용이 없다. 루프백 `http://`는 정상.
- Repeat는 URLSession으로 보내므로 Accept-Language·Accept-Encoding 등이 붙어 원래 요청과 바이트 단위로 같지 않다.
- Network Conditions는 패킷 단위가 아니라 요청 단위(버퍼링 후 지연)로 속도를 늦춘다.
- GraphQL QueryName 규칙은 꺼진 채로 가져온다(2차 묶음에서 지원).
- Proxyman의 폴더 노드와 Map Remote·Breakpoint·Block·Allow 규칙의 디스크 JSON 모양은 실제 파일로 확인 전까지 추정이다. 모르는 노드·키는 건너뛰고 개수를 보여 준다.
- Flow 목록 열 배치 저장 키가 `eyeproxy.flowColumns.v2`로 바뀌어 저장된 열 너비가 한 번 초기화된다.
- Compose로 임의의 `http://` 주소에 보내기 위해 앱 전체에 `NSAllowsArbitraryLoads`가 켜져 있다.

## 알려진 제한(Certificate·필터 바·상태 막대)

- 필터 바에 WebSocket 칩이 없다(WebSocket 캡처를 아직 지원하지 않음).
- Android는 사용자 CA까지만 설치한다. 앱이 `network_security_config`로 사용자 CA를 허용해야 복호화되고, 시스템 CA는 루팅 기기나 Play 없는 에뮬레이터(`adb root; adb remount`)에서만 넣을 수 있다.
- P12는 macOS 내장 `/usr/bin/openssl`(LibreSSL, 기본 암호화 방식)로 만든다. openssl이 없거나 실패하면 오류 알림만 뜬다.
- Listen 주소(상태 막대 메뉴·툴바·Android 섹션)는 네트워크가 바뀌어도 바로 갱신되지 않는다. 메뉴·창을 다시 그릴 때 갱신된다.
- 상태 막대 아이콘은 메뉴 막대가 꽉 차면(노치 포함) "»" 안에 숨는다.

## 빌드·테스트

```bash
swift test --package-path Packages/EyeProxyCore
swift test --package-path Packages/EyeProxyKit
xcodegen generate
xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates
```

## 모듈 구조

`EyeProxy`(SwiftUI 앱) → `EyeProxyKit`(세션·규칙 저장, 기기 온보딩, 시스템 프록시·키체인·simctl 연동) → `EyeProxyCore`(NIO 기반 프록시 엔진, TLS MITM, HTTP/1.1 파싱(HTTP/2·WebSocket은 P2/P3), 인터셉터 훅). 의존은 위에서 아래로만 흐르고 Core는 UI를 import하지 않는다.

## 릴리스

Release 빌드는 unsigned로 만든 뒤 회사 Developer ID로 재서명 → 공증 → 스테이플 → zip → Sparkle EdDSA 서명 → `docs/appcast.xml` 갱신까지 스크립트가 처리한다. 사전 조건: `notarytool` 키체인 프로필, Developer ID 인증서, Xcode에서 한 번 빌드(Sparkle 도구).

```bash
./scripts/release.sh <version>
git add -A && git commit -m "release: v<version>"
git tag v<version>
git push origin main --tags
gh release create v<version> releases/<version>/Prog-<version>.zip --title "v<version>"
```

Sparkle 서명 키: TVAccountManager와 같은 EdDSA 키를 공유한다(키체인 보관).

appcast는 GitHub Pages(`main`/`docs`)로 서빙된다: `https://doyeonk35.github.io/EyeProxy/appcast.xml`
