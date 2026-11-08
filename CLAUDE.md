# Prog (구 EyeProxy) — AI Agent Guide

macOS 15+ / Swift 6 MITM 디버깅 프록시 (Proxyman류). XcodeGen(`project.yml`) 사용.

## 빌드·테스트

```bash
swift test --package-path Packages/EyeProxyCore
swift test --package-path Packages/EyeProxyKit
xcodegen generate
xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates
```

릴리스(unsigned 빌드 → Developer ID 재서명 → 공증 → zip → appcast): `./scripts/release.sh <version>` 후 commit·tag·push·`gh release create` (README 참고).

## 모듈 의존 방향

`EyeProxy`(앱) → `EyeProxyKit` → `EyeProxyCore`. 역방향 import 금지. Core는 UI 무관(NIO/인증서/Flow 모델).

## 규칙

- Tools는 인터셉터 하나 + 뷰 하나로 구성한다.
- 외부 패키지 허용 목록: swift-nio, swift-nio-ssl, swift-nio-extras, swift-certificates, swift-asn1, swift-crypto, Sparkle. 그 외 추가 금지.
- App Sandbox 끄기: entitlements는 빈 dict 유지.
- 서명: Debug = Automatic(팀 `F64BRNFSBB`, 번들 ID `com.tv.eyeproxy.debug`), Release = unsigned(`-`), 배포 서명은 별도 재서명.
- 커밋 메시지: `<type>(<scope>): <한국어 요약>`.
