# EyeProxy

macOS용 MITM 디버깅 프록시 (Proxyman류). Mac·시뮬레이터·Apple TV·iPhone의 HTTP(S) 트래픽을 한 화면에서 본다. macOS 15+ / Swift 6.

## 설치

1. GitHub Releases에서 최신 `EyeProxy-<version>.zip`을 받는다.
2. 압축을 풀어 `EyeProxy.app`을 `/Applications`로 옮긴다. (Developer ID 서명·공증 완료 — 바로 실행된다.)
3. 이후 업데이트는 앱 메뉴 `EyeProxy > 업데이트 확인…` (Sparkle).

## 첫 실행

1. 처음 켜면 루트 CA가 자동 생성된다.
2. `기기…`(⌘D) 창에서 **Mac에 CA 설치** → 로그인 키체인에 추가되고 SSL 신뢰가 설정된다. (관리자 인증 필요)
3. **이 Mac 캡처**를 켜면 활성 네트워크 서비스의 HTTP·HTTPS 프록시가 `127.0.0.1:9090`으로 설정된다. 끄거나 종료하면 원래대로 복원된다.

## 기기 연결

- **Mac**: 위 첫 실행 절차. 브라우저·앱 트래픽이 바로 잡힌다. 사이드바는 Mac 트래픽을 프로세스별로 나눈다. Safari·WKWebView의 XPC 헬퍼 트래픽은 책임 앱 아래로 묶이고, 시뮬레이터 앱은 "<앱> (<플랫폼> 시뮬레이터)"로, curl 같은 명령줄 도구는 자기 이름으로 표시된다.
- **시뮬레이터**: `기기…` 창의 시뮬레이터 섹션에서 부팅된 iOS·tvOS 시뮬레이터마다 **CA 설치** → 시뮬레이터 앱 재실행.
- **Apple TV·iPhone·iPad**: 기기 창(⌘D) › **실기기 프로필 만들기**에서 SSID·보안 유형·비밀번호·Mac IP·포트를 입력해 `EyeProxy-<SSID>.mobileconfig`(Wi-Fi + 수동 프록시)를 저장한다. Apple TV는 Apple Configurator로 페어링 후 프로필을 드래그, iPhone·iPad는 AirDrop·메일로 전달한다. 그다음 기기에서 `http://eyeproxy/ssl`로 CA 프로필을 설치하고 `인증서 신뢰 설정`에서 신뢰한다. (프로필에 Wi-Fi 비밀번호가 평문으로 들어가며 앱은 비밀번호를 저장하지 않는다.)

자세한 내용은 `docs/superpowers/specs/2026-11-05-eyeproxy-design.md` §7.

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

**쿼리 무시**: Map Local·Map Remote 등 새 규칙은 기본으로 "쿼리 무시"가 켜져 있다. 요청 URL에서 `?` 뒤를 떼고 비교하므로 `https://host/path` 하나가 쿼리가 다른 요청에 모두 맞는다(Proxyman에서 붙이던 `?*`가 필요 없다). Proxyman에서 가져온 규칙은 꺼진 채로 들어와 Proxyman과 똑같이 동작한다.

**자동 복호화**: 켜진 도구의 켜진 규칙이 가리키는 HTTPS 호스트는 SSL Proxying 목록에 없어도 자동으로 복호화한다(Proxyman은 이런 규칙을 조용히 무시한다). 정규식 규칙과 host가 `*`뿐인 규칙은 모든 HTTPS를 복호화하게 되므로 제외되며, 규칙 옆 주황 경고대로 SSL Proxying 목록에 호스트를 직접 넣어야 한다.

**Proxyman에서 가져오기**: **Tools ▸ Import Settings ▸ From Proxyman…** 은 `~/Library/Application Support/com.proxyman.NSProxy/user-data/`를 읽기만 하고(쓰지 않음) 도구별 개수를 보여 준다. 고른 도구의 규칙은 기존 EyeProxy 규칙 **끝에** 추가되고, 같은 규칙(id)은 다시 가져와도 건너뛴다. Map Local 응답 파일은 EyeProxy 폴더로 복사한다. 가져온 도구는 꺼진 상태로 두므로 각 도구 창에서 켠다. SSL Proxying 목록도 함께 가져올 수 있다.
각 도구 창 **More ▸ Export…** 는 `<도구 이름>.eyeproxyrules` 폴더(Proxyman 내보내기와 같은 `rules.config` + 응답 파일 `map-local/`)를 만든다. 다른 Mac에서는 그 도구 창의 **More ▸ Import…** 로 이 폴더(또는 안의 `rules.config`)나 Proxyman 내보내기 `.config`·`.json`을 고른다.

**저장 위치**: `~/Library/Application Support/com.tv.eyeproxy/rules/`(도구별 JSON, Proxyman과 같은 모양) · Map Local 응답 파일은 `…/com.tv.eyeproxy/map-local/`(Map Local More ▸ Default Local File Folder로 변경 가능) · 도구 스위치는 앱 설정(UserDefaults).

## 문제 해결

### 네트워크 복구(긴급)

"이 Mac 캡처"가 켜진 채 EyeProxy가 죽어 Mac 인터넷이 안 되면: EyeProxy를 다시 켜고 **복원**을 고른다. 앱을 켤 수 없으면 터미널에서 끈다(`Wi-Fi` 자리에 `networksetup -listallnetworkservices`로 확인한 서비스 이름).

```bash
networksetup -setwebproxystate "Wi-Fi" off
networksetup -setsecurewebproxystate "Wi-Fi" off
```

### VPN(GlobalProtect) 사용 중

GlobalProtect처럼 VPN이 기본 서비스가 되면 실효 프록시(`scutil --proxy`)는 Wi-Fi가 아니라 VPN 서비스의 State 키(`State:/Network/Service/gpd.pan/Proxies`)를 따른다. VPN은 연결할 때만 Wi-Fi 프록시를 복사해 가고 이후 Wi-Fi 변경은 따라오지 않는다(켜도 적용 안 됨, 꺼도 복사본이 남음 — Proxyman도 같은 문제). 그래서 EyeProxy는 VPN 상태에서 **켤 때** VPN State 키의 원본을 백업에 저장한 뒤 EyeProxy 프록시를 직접 쓰고, **끌 때** 그 원본을 그대로 되돌린다(켤 때·끌 때 각각 관리자 인증 1회, 나머지 VPN 설정은 유지). 기기 창(⌘D) "이 Mac"에 "VPN 상태에서는 켜고 끌 때 관리자 인증이 필요합니다"가 보이면 이 경우다. 켤 때 인증을 취소하면 Wi-Fi도 원래대로 돌아간다.

원본이 없는 복사본(캡처 중 VPN 연결, 이전 버전 백업)은 끌 때 HTTP·HTTPS 중 EyeProxy 쪽만 끈다. 되돌리기에 실패하면 "이 Mac"에 주황 경고가 뜬다 — "이 Mac 캡처"를 끄면(경고가 있으면 토글이 켜진 것으로 보인다) 다시 시도하고, 그래도 안 되면 **VPN을 재연결**한다 — VPN이 프록시를 새로 받는다. 옮길 수 없는 VPN 설정(중첩 항목)이 있으면 덮어쓰지 않고 실패 처리하므로(켜기도 "적용하지 못했습니다"로 실패) 이때도 VPN 재연결로 복구한다.

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
- 복호화하는 호스트의 CONNECT 행은 목록에 표시되지 않고, 기기 쪽 TLS 핸드셰이크 실패는 기기 창의 연결 로그에만 보인다.

## 알려진 제한(Tools 1차)

- Compose·Repeat로 `https://localhost`·`https://127.0.0.1`에 보내면 EyeProxy를 거치지 않는다(URLSession이 루프백 HTTPS는 프록시를 쓰지 않음). 기록·도구 적용이 없다. 루프백 `http://`는 정상.
- Repeat는 URLSession으로 보내므로 Accept-Language·Accept-Encoding 등이 붙어 원래 요청과 바이트 단위로 같지 않다.
- Network Conditions는 패킷 단위가 아니라 요청 단위(버퍼링 후 지연)로 속도를 늦춘다.
- GraphQL QueryName 규칙은 꺼진 채로 가져온다(2차 묶음에서 지원).
- Proxyman의 폴더 노드와 Map Remote·Breakpoint·Block·Allow 규칙의 디스크 JSON 모양은 실제 파일로 확인 전까지 추정이다. 모르는 노드·키는 건너뛰고 개수를 보여 준다.
- Flow 목록 열 배치 저장 키가 `eyeproxy.flowColumns.v2`로 바뀌어 저장된 열 너비가 한 번 초기화된다.
- Compose로 임의의 `http://` 주소에 보내기 위해 앱 전체에 `NSAllowsArbitraryLoads`가 켜져 있다.

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
gh release create v<version> releases/<version>/EyeProxy-<version>.zip --title "v<version>"
```

Sparkle 서명 키: TVAccountManager와 같은 EdDSA 키를 공유한다(키체인 보관).

appcast는 GitHub Pages(`main`/`docs`)로 서빙된다: `https://doyeonk35.github.io/EyeProxy/appcast.xml`
