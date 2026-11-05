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

- **Mac**: 위 첫 실행 절차. 브라우저·앱 트래픽이 바로 잡힌다.
- **시뮬레이터**: `기기…` 창의 시뮬레이터 섹션에서 부팅된 iOS·tvOS 시뮬레이터마다 **CA 설치** → 시뮬레이터 앱 재실행.
- **Apple TV·iPhone·iPad**: 기기 창(⌘D) › **실기기 프로필 만들기**에서 SSID·보안 유형·비밀번호·Mac IP·포트를 입력해 `EyeProxy-<SSID>.mobileconfig`(Wi-Fi + 수동 프록시)를 저장한다. Apple TV는 Apple Configurator로 페어링 후 프로필을 드래그, iPhone·iPad는 AirDrop·메일로 전달한다. 그다음 기기에서 `http://eyeproxy/ssl`로 CA 프로필을 설치하고 `인증서 신뢰 설정`에서 신뢰한다. (프로필에 Wi-Fi 비밀번호가 평문으로 들어가며 앱은 비밀번호를 저장하지 않는다.)

자세한 내용은 `docs/superpowers/specs/2026-11-05-eyeproxy-design.md` §7.

## 문제 해결

### 네트워크 복구(긴급)

"이 Mac 캡처"가 켜진 채 EyeProxy가 죽어 Mac 인터넷이 안 되면: EyeProxy를 다시 켜고 **복원**을 고른다. 앱을 켤 수 없으면 터미널에서 끈다(`Wi-Fi` 자리에 `networksetup -listallnetworkservices`로 확인한 서비스 이름).

```bash
networksetup -setwebproxystate "Wi-Fi" off
networksetup -setsecurewebproxystate "Wi-Fi" off
```

### VPN(GlobalProtect) 사용 중

GlobalProtect처럼 VPN이 기본 서비스가 되면 VPN이 Wi-Fi의 프록시 설정을 자기 서비스로 **복사**해 가고, Wi-Fi를 되돌려도 복사본을 지우지 않는다(Proxyman도 같은 문제). 그래서 EyeProxy는 캡처를 끌 때 실효 프록시(`scutil --proxy`)가 아직 127.0.0.1:<포트>이면 VPN 서비스의 복사본에서 HTTP·HTTPS만 끄도록 정리한다(관리자 인증 1회, 나머지 VPN 설정은 유지). 정리에 실패하면 기기 창(⌘D) "이 Mac"에 주황 경고가 뜬다 — "이 Mac 캡처"를 끄면(경고가 있으면 토글이 켜진 것으로 보인다) 다시 정리를 시도하고, 그래도 안 되면 **VPN을 재연결**한다 — VPN이 프록시를 새로 받는다. 옮길 수 없는 VPN 설정(중첩 항목)이 있으면 덮어쓰지 않고 실패 처리하므로 이때도 VPN 재연결로 복구한다.

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
