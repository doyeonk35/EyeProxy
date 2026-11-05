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
- **Apple TV·iPhone·iPad**: 기기 추가 마법사에서 SSID·보안 유형·비밀번호·Mac IP·포트를 입력해 `EyeProxy-<SSID>.mobileconfig`(Wi-Fi + 수동 프록시)를 저장한다. Apple TV는 Apple Configurator로 페어링 후 프로필을 드래그, iPhone·iPad는 AirDrop·메일로 전달한다. 그다음 기기에서 `http://eyeproxy/ssl`로 CA 프로필을 설치하고 `인증서 신뢰 설정`에서 신뢰한다. (프로필에 Wi-Fi 비밀번호가 평문으로 들어가며 앱은 비밀번호를 저장하지 않는다.)

자세한 내용은 `docs/superpowers/specs/2026-11-05-eyeproxy-design.md` §7.

## 빌드·테스트

```bash
swift test --package-path Packages/EyeProxyCore
swift test --package-path Packages/EyeProxyKit
xcodegen generate
xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates
```

## 모듈 구조

`EyeProxy`(SwiftUI 앱) → `EyeProxyKit`(세션·규칙 저장, 기기 온보딩, 시스템 프록시·키체인·simctl 연동) → `EyeProxyCore`(NIO 기반 프록시 엔진, TLS MITM, HTTP/1.1·HTTP/2·WebSocket 파싱, 인터셉터 훅). 의존은 위에서 아래로만 흐르고 Core는 UI를 import하지 않는다.

## 릴리스

Release 빌드는 unsigned로 만든 뒤 회사 Developer ID로 재서명 → 공증 → 스테이플 → zip → Sparkle EdDSA 서명 → `docs/appcast.xml` 갱신까지 스크립트가 처리한다. 사전 조건: `notarytool` 키체인 프로필, Developer ID 인증서, Xcode에서 한 번 빌드(Sparkle 도구).

```bash
./scripts/release.sh <version>
git add -A && git commit -m "release: v<version>"
git tag v<version>
git push origin main --tags
gh release create v<version> releases/<version>/EyeProxy-<version>.zip --title "v<version>"
```

appcast는 GitHub Pages(`main`/`docs`)로 서빙된다: `https://doyeonk35.github.io/EyeProxy/appcast.xml`
