# EyeProxy 설계 문서

작성일: 2026-11-05
상태: 빌더 검토 반영, 사용자 승인 대기

## 1. 의도

사내 iOS·tvOS 개발·QA에서 쓰는 Proxyman을 대체하는 macOS 네이티브 HTTP(S) 디버깅 프록시를 만든다.

성공 기준은 하나다. **작성자(그리고 팀원)가 Proxyman을 지우고 EyeProxy만 쓴다.** 기능 목록이 길어도 "이건 Proxyman으로 봐야겠다"는 순간이 한 번이라도 생기면 실패다.

왜 만드는가:
- Proxyman은 유료 seat가 필요하고, 사내 팀원 전부에게 깔아주기 어렵다.
- Apple TV 실기기·tvOS 시뮬레이터 연결은 Proxyman으로도 손이 많이 간다(Apple Configurator로 프로필 수동 생성, 시뮬레이터 CA를 터미널에서 수동 설치). 이 부분은 Proxyman보다 **더 잘** 만들 수 있다.
- 오래 유지보수할 사내 툴이므로 코드와 아키텍처가 깔끔해야 한다. 한 사람이 주로 관리한다.

## 2. 목표 / 비목표 / 반목표

### 목표
1. Proxyman의 Team Workspace를 제외한 **모든 기능**을 제공한다. (§6 기능 표)
2. iOS·tvOS 기기·시뮬레이터의 연결과 인증서 설치를 Proxyman보다 쉽게 만든다. (§7)
3. 매일 쓰는 경로(기기 연결 → HTTPS 복호화 → Flow 확인 → Tools로 조작)가 끊김 없이 된다.
4. **이 Mac 자체의 네트워크 요청**도 똑같이 본다(시스템 프록시 등록, §7.1). macOS 앱이면서 Mac 트래픽을 못 보면 안 된다.
5. 유지보수 가능한 구조: 프록시 엔진은 UI 없이 단독 테스트 가능하고, Tools 하나를 추가할 때 손대는 곳이 명확하다.
6. (후순위) Atlantis 같은 **앱 내장 SDK**: iOS·tvOS 앱에 Swift 패키지를 넣으면 프록시·인증서 설정 없이 트래픽이 EyeProxy로 온다. 1순위 기능은 아니며 §8 P4에 둔다. 사용자가 필요하다고 확인했다.

### 비목표
- Team Workspace(규칙 공유·동기화).
- Windows·Linux 빌드.
- Proxyman for iOS 같은 모바일 앱.
- 앱 내 언어 전환. 시스템 로케일만 따른다(한국어·영어).

### 추후 지원 (지금은 만들지 않지만 막지도 않는다)
- **Android** 기기·에뮬레이터. 일반 HTTP 프록시라 동작은 하지만 지금은 테스트·가이드를 만들지 않는다. 나중에 추가할 때 Core를 고치지 않아도 되게, 기기 온보딩(§7)은 플랫폼별 가이드를 끼워 넣는 구조로 둔다.

### 반목표 (이렇게 되면 실패)
- "80%만 되는 가벼운 대체품". 결국 Proxyman을 다시 켜게 된다.
- 기능 하나 넣으려고 레이어·프로토콜·팩토리가 줄줄이 생기는 과잉 설계. 구현체가 하나뿐인 프로토콜, 바뀌지 않는 값의 설정 파일은 넣지 않는다.
- 외부 의존성 과다. Swift 패키지는 아래 명시한 것만 쓴다.
- 프록시를 켠 채 앱이 죽어서 Mac의 네트워크가 먹통이 되는 것.

## 3. 제약

- **플랫폼**: macOS 15.0+, Swift 6 (strict concurrency), SwiftUI. Xcode 16+. (15로 올린 이유: Compression 프레임워크의 Brotli 해제가 15부터라, CDN 응답의 `Content-Encoding: br`을 기기 요청을 변형하지 않고 풀 수 있다. 사용자 확정.)
- **프로젝트 생성**: XcodeGen `project.yml`. TVAccountManager(`~/personal/TvingLoginManager`)와 같은 구성.
- **서명·배포**: TVAccountManager와 동일.
  - Debug: 개인 팀 `F64BRNFSBB` 자동 서명.
  - Release: unsigned 빌드 → `scripts/release.sh`가 `Developer ID Application: Tving Co.,Ltd (635U6G6DF4)`로 재서명(hardened runtime, `--timestamp`) → `notarytool` 공증(키체인 프로필 `notarytool`) → `stapler staple`.
  - Sparkle 2.x 자동 업데이트, `docs/appcast.xml`을 GitHub Pages로 서빙, 릴리스는 GitHub Release(`doyeonk35/EyeProxy`).
- **App Sandbox 끔**. 시스템 프록시 변경·키체인 CA 신뢰·`simctl` 실행이 필요하다. Developer ID 배포에는 샌드박스가 필수가 아니다.
- **기본 포트 9090**. Proxyman과 같게 둬서 팀의 기존 Apple Configurator 프로필·Confluence 가이드·고정 IP 설정이 그대로 통한다. 설정에서 변경 가능.
- **유지보수자 1인**. 복잡한 빌드 파이프라인·CI 매트릭스는 두지 않는다.

## 4. 결정된 것 (How)

아래는 대화에서 확정했거나 작성자(Claude)가 기본값으로 정한 것. "[내 판단]" 표시는 Claude가 정한 것으로, 사용자가 뒤집을 수 있다.

### 4.1 기술 스택
- Swift + SwiftUI 네이티브 macOS 앱. [내 판단, 사용자 동의]
- 프록시 엔진: **SwiftNIO** (`swift-nio`, `swift-nio-ssl`, `swift-nio-http2`, `swift-nio-extras`). [내 판단, 사용자 동의]
- 스크립팅: **JavaScriptCore** (시스템 프레임워크, 의존성 0). **팀이 쓰고 있는 Proxyman 스크립트가 수정 없이 돌아가야 한다**(사용자 확정). 따라서 `onRequest`/`onResponse`/`onWebsocket` 시그니처뿐 아니라 `$ctx`, `sharedState`, `scheduleTask`, 환경변수, 내장 라이브러리(`require` 이름까지)를 Proxyman 문서(https://proxyman.com/docs/scripting/) 기준으로 맞춘다. 빌더는 구현 전에 그 문서에서 API 표를 뽑아 `docs/scripting-api.md`로 고정한다.
- 인증서 생성: Security.framework로는 CA 서명 발급이 번거로우므로 **swift-certificates** + **swift-crypto**(Apple 공식 패키지)로 CA·리프 인증서를 만든다. [내 판단]
- 허용 외부 패키지: swift-nio 계열, swift-certificates, swift-crypto, Sparkle. 그 외는 설계 문서를 고쳐서 넣는다.

### 4.2 모듈 구조 [내 판단]

하나의 레포에 로컬 Swift 패키지 `Packages/`와 앱 타깃을 둔다. 의존 방향은 위→아래만.

```
EyeProxy (앱 타깃, SwiftUI)
  └─ EyeProxyKit        — 세션·규칙 저장, 기기 식별, 시스템 연동(시스템 프록시, 키체인, simctl, mobileconfig)
       └─ EyeProxyCore  — 프록시 엔진. NIO 파이프라인, TLS MITM, HTTP/1.1·HTTP/2·WebSocket 파싱, 규칙 적용 훅
            └─ (swift-nio, swift-certificates)
```

- **EyeProxyCore**: AppKit·SwiftUI를 import하지 않는다. 입력은 소켓, 출력은 `Flow` 이벤트 스트림(`AsyncStream<FlowEvent>`). 규칙(Tools)은 `RequestInterceptor`/`ResponseInterceptor` 두 훅으로만 엔진에 꽂힌다. Tools 하나를 추가하면 Core에는 손대지 않고 Kit에 인터셉터 구현 하나가 늘어난다.
- **EyeProxyKit**: 앱 로직. 세션 저장, 규칙 목록 관리, 기기 온보딩, 시스템 설정 변경. 여기까지 UI 없이 `swift test`로 검증 가능해야 한다.
- **EyeProxy 앱**: SwiftUI 뷰와 뷰모델만. 뷰모델은 Kit의 타입을 그대로 쓰고, DTO 변환 계층을 따로 두지 않는다.
- 인터셉터 체인은 **배열 순회**다. 미들웨어 프레임워크·플러그인 시스템을 만들지 않는다.

### 4.3 Flow 화면 (사용자 확정)
- 기본 레이아웃 **A**: 좌측 사이드바(트리) + 상단 요청 목록 + 하단 상세(요청 | 응답 좌우 분할). Proxyman과 같다.
- 툴바 토글로 레이아웃 **B**(목록 왼쪽 | 상세 오른쪽, 상세는 요청 위·응답 아래)로 전환 가능. 선택은 저장된다.
- 사이드바 그룹: **기기별**(출발지 IP 기준: Apple TV / iPhone / 이 Mac)과 **도메인별**, 그리고 Proxyman처럼 **앱별**(macOS 로컬 프로세스). 기기별이 사내 용도에 더 자주 쓰일 것으로 보고 기본으로 둔다. [내 판단]
- 시뮬레이터 트래픽은 Mac 시스템 프록시를 타므로 IP로는 "이 Mac"과 구분이 안 된다. **P1에서는 시뮬레이터를 "이 Mac" 그룹에 포함**하고, P2에서 로컬 소켓 포트→PID 귀속(libproc)을 넣어 "앱별"과 함께 시뮬레이터 런타임 프로세스를 분리한다. [내 판단 — P1에 PID 귀속 서브시스템을 넣지 않기 위해]
- 툴바에 Tools 토글(Breakpoint·Map Local·Map Remote·Block·Allow·Network Conditions·Scripting·SSL Proxying)을 상시 표시하고, 켜진 것은 색으로 구분한다. 켜둔 걸 잊고 "왜 안 되지" 하는 일을 막는다.
- 목록 기본 컬럼: `#`, Method, URL, Status, Size, Time. 우클릭으로 컬럼 추가(Host, Content-Type, 기기, 시작 시각 등).
- 상세 탭: 요청 = Headers · Query · Body(Form/JSON/Raw) · Cookies; 응답 = Headers · JSON(트리+pretty) · Raw · Preview(이미지·HTML) · Cookies. Protobuf·GraphQL 전용 뷰는 §6 참고.

### 4.4 기기 연결 & 인증서 (§7에 상세)
- 앱 첫 실행 시 루트 CA 생성, `~/Library/Application Support/com.tv.eyeproxy/ca/`에 보관. CA는 10년, 리프 인증서는 호스트별로 발급·캐시.
- CA 배포 엔드포인트: 프록시를 거쳐 `http://eyeproxy/ssl`로 접속하면 CA 프로필(`.mobileconfig`)을 내려준다. iOS·tvOS 공통.
- Mac: 로그인 키체인에 CA 추가 + 신뢰 설정(관리자 암호 1회). 시뮬레이터: `xcrun simctl keychain <UDID> add-root-cert`.
- iOS·tvOS 실기기: 앱이 **Wi-Fi + 수동 프록시 `.mobileconfig`**를 생성해 준다(SSID·Mac IP·포트 입력). tvOS는 Apple Configurator로 TV에 드롭하면 되고, iOS는 AirDrop·메일로 보내 설치한다.

### 4.5 이름·식별자 (사용자 확정)
- 앱 이름 **EyeProxy**, 번들 ID `com.tv.eyeproxy`(Debug는 `.debug` 접미), 레포 `doyeonk35/EyeProxy`, 프로젝트 위치 `~/personal/EyeProxy`.

### 4.6 세션 저장 형식 [내 판단]
- 자체 형식: 디렉터리 패키지 `*.eyeproxy/` 안에 `index.json`(메타·헤더) + `bodies/<id>` (원본 바디). 바디를 JSON에 base64로 넣지 않는다.
- HAR 가져오기·내보내기 지원. Proxyman 세션 파일 가져오기는 **하지 않는다**(비공개 형식).

### 4.7 HTTP/2 [내 판단]
- **P1은 양쪽 모두 http/1.1만** 쓴다. 클라이언트(기기→EyeProxy)에는 ALPN으로 http/1.1만 광고하고, 업스트림에도 http/1.1만 제안한다. iOS·tvOS URLSession은 http/1.1로 자연스럽게 내려오고 앱 동작에는 영향이 없다. h1↔h2 변환·멀티플렉싱 코드를 P1에 넣지 않기 위한 선택.
- h2는 §8 P3에서 업스트림·클라이언트를 함께 붙인다.

## 5. 아키텍처 원칙 (유지보수)

사용자가 명시적으로 요구한 항목이다.

1. **Core는 순수**: 엔진은 UI·디스크·시스템 설정을 모른다. 테스트는 소켓 두 개 붙여서 돈다.
2. **Tools는 인터셉터 하나**: 새 Tool = `Packages/EyeProxyKit/Sources/Rules/<Tool>Rule.swift` 하나 + 그 뷰 하나. 등록은 배열에 한 줄.
3. **상태는 한 곳**: 세션(Flow 목록)·규칙·설정은 Kit의 `@Observable` 스토어가 소유. 뷰는 읽기만 하고 변경은 스토어 메서드로.
4. **동시성은 Swift 6 기본**: 엔진은 NIO EventLoop, 앱은 MainActor. 경계는 `AsyncStream`으로 넘긴다. 락·세마포어 직접 사용 금지.
5. **테스트**: Core는 프로토콜 단위 테스트(요청 파싱·TLS 핸드셰이크·인터셉터 순서). Kit는 규칙 매칭·세션 저장/복원. 앱 UI는 수동. 프레임워크는 XCTest(또는 Swift Testing)만.
6. **문서**: `README.md`에 빌드·배포·기기 연결 가이드. 코드 주석은 "왜"만. CLAUDE.md에 모듈 규칙 요약.

## 6. 기능 범위 (Proxyman 문서 기준, Team Workspace 제외)

"단계"는 §8 구현 순서. P1이 있어야 Proxyman을 끄기 시작할 수 있고, P2까지 있으면 일상 업무가 된다.

| 영역 | 기능 | 설명 | 단계 |
|---|---|---|---|
| 캡처 | HTTP/HTTPS 프록시 | 기본 포트 9090, LAN 리스닝 | P1 |
| 캡처 | SSL Proxying 목록 | 호스트 단위 복호화 on/off, 와일드카드, 목록에서 우클릭 추가 | P1 |
| 캡처 | 시스템 프록시 등록 | Mac·시뮬레이터 트래픽 캡처. 앱 종료·크래시 시 반드시 복원 | P1 |
| 캡처 | Bypass Proxy List | 시스템 프록시 제외 호스트 | P1 |
| 캡처 | WebSocket | 프레임 목록·방향·내용 | P2 |
| 캡처 | HTTP/2 (클라이언트 측) | 기기→프록시 h2 | P3 |
| 캡처 | Connection Log | 연결 수준 로그(TLS 실패 이유 등) | P2 |
| 기기 | Mac 키체인 CA 설치 | 관리자 암호 1회 | P1 |
| 기기 | 시뮬레이터 CA 설치 | 부팅된 iOS·tvOS 시뮬레이터 목록 + 버튼 | P1 |
| 기기 | `http://eyeproxy/ssl` | CA 프로필 배포 | P1 |
| 기기 | `.mobileconfig` 생성 | Wi-Fi + 수동 프록시 프로필 (iOS·tvOS) | P1 |
| 기기 | 기기 인식 | 출발지 IP로 기기 그룹, 이름 지정·기억 | P1 |
| Flow | 목록·상세·검색 | §4.3 | P1 |
| Flow | 필터 | 다중 필터(Host·URL·Method·Status·Content-Type·기기), Regex, JSONPath, JQ 스타일 | P2 (기본 텍스트 필터는 P1) |
| Flow | Pin, Comment, 색 태그 | 요청 표시 | P2 |
| Flow | 세션 저장·열기·지우기 | §4.6 | P1 |
| Flow | HAR 가져오기·내보내기 | | P2 |
| Flow | cURL·코드 생성 | cURL 복사 P1, Swift·Python·Node 등 코드 생성 P3 | P1/P3 |
| Tools | Breakpoint | 요청/응답 중단·편집·Abort(429/503). Raw 편집 포함 | P2 |
| Tools | Map Local (File·Directory) | 응답을 로컬 파일/폴더로 | P2 |
| Tools | Map Remote | host·port·path·scheme 치환, Preserve Host Header 옵션 | P2 |
| Tools | Block List / Allow List | | P2 |
| Tools | Network Conditions | 프리셋(2G~5G·Wi-Fi·100% Loss)·커스텀, 전체 또는 호스트별 | P2 |
| Tools | No Caching | 캐시 헤더 제거 | P2 |
| Tools | Scripting | JS `onRequest`/`onResponse`/`onWebsocket`, Mock API, 환경변수, 스니펫. **Proxyman 스크립트 API 완전 호환**(§4.1) | P3 |
| Tools | Proxyman 규칙 가져오기 | Proxyman이 export한 Map Local·Map Remote·Breakpoint·Block/Allow·Network Conditions 규칙 파일을 읽어 그대로 적용. 각 Tool이 P2에 들어갈 때 함께 | P2 |
| Tools | Proxyman 스크립트 가져오기 | Proxyman Script List export를 읽어 등록 | P3 |
| Tools | Compose / Repeat / Edit & Repeat | | P2 |
| Tools | Diff | 요청·응답 두 개 비교 | P3 |
| Tools | DNS Spoofing | 도메인→IP 매핑 | P3 |
| Tools | Reverse Proxy | 로컬 포트→원격 | P3 |
| Tools | External Proxy | 상위 프록시 경유(HTTP·SOCKS) | P3 |
| Tools | SOCKS Proxy | SOCKS5 수신 | P4 |
| Tools | Access Control | 프록시 접속 허용 IP | P3 |
| Tools | Custom Certificates | 사용자 CA·클라이언트 인증서 | P4 |
| Tools | TLS Key Logging | SSLKEYLOGFILE 형식 | P4 |
| 뷰어 | JSON·이미지·HTML 프리뷰 | | P1 |
| 뷰어 | GraphQL | Query Name 표시, 규칙 매칭에 사용 | P3 |
| 뷰어 | Protobuf | .proto 등록 후 디코딩 | P4 |
| 기타 | Charles 설정 변환 | Charles Rewrite·Map 설정 가져오기 | P4 |
| 기타 | Publish to Gist | | P4 |
| 기타 | Swagger/OpenAPI | 세션에서 스펙 생성 | P4 |
| 기타 | 앱 내장 SDK (Atlantis 대응) | iOS·tvOS 앱에 넣는 Swift 패키지. `URLProtocol` 등록으로 URLSession 트래픽을 가로채 Bonjour로 Mac의 EyeProxy를 찾아 전송. Breakpoint 불가(Atlantis와 동일). 같은 레포의 별도 패키지 `EyeProxySDK` | P4 |
| 기타 | Network Extension | 프록시 없이 캡처 | 하지 않음 (Proxyman도 선택 기능. 필요해지면 재논의) |
| 기타 | CLI | `eyeproxy-cli network-condition on|off` 등 자동화용 | P3 (TVAccountManager의 `tvlogin`처럼 별도 바이너리) |

## 7. 기기 온보딩 상세

현재 사내 절차(Confluence "PD - Proxyman을 통한 tvOS 기기 로깅 환경 세팅 가이드")와 시뮬레이터 메모를 EyeProxy가 흡수한다.

### 7.1 Mac (이 Mac + 시뮬레이터)
1. "이 Mac 캡처" 토글 → `networksetup`으로 활성 네트워크 서비스에 HTTP·HTTPS 프록시 `127.0.0.1:9090` 설정. 관리자 권한 필요하면 1회 요청. 끄거나 종료하면 복원. **비정상 종료 대비**: 켤 때 원래 값을 디스크에 기록하고, 다음 실행 시 남아 있으면 복원 제안.
2. "Mac에 CA 설치" 버튼 → 로그인 키체인 추가 + SSL 신뢰. 이미 설치돼 있으면 상태만 표시.
   - 1·2 모두 관리자 인증이 필요하다. **팀원 전원이 회사 Mac 관리자 권한을 가진다고 가정**한다(작성자 Mac에 있으므로 추정, 미확인). 아닌 사람이 나오면 시뮬레이터 환경변수 프록시 같은 무권한 대안을 그때 추가한다.
3. 시뮬레이터 섹션: `simctl list devices booted`로 부팅된 iOS·tvOS 시뮬레이터 나열, 각각 "CA 설치" 버튼. 설치 후 앱 재실행 필요 안내. (Xcode 27에서는 Simulator.app 대신 DeviceHub.app — 안내 문구만.)

### 7.2 Apple TV 실기기
1. 기기 추가 마법사: SSID, 보안 유형(없음/WPA2/WPA3), Wi-Fi 비밀번호, Mac IP 자동 감지(여러 인터페이스면 선택), 포트.
2. "프로필 저장" → `EyeProxy-<SSID>.mobileconfig`(Wi-Fi + 수동 프록시). 안내: Apple Configurator 페어링 후 TV에 드래그.
   - tvOS에서 프록시를 지정하는 유일한 경로가 Wi-Fi 페이로드라 WPA 네트워크면 비밀번호가 프로필에 **평문으로** 들어간다. 앱은 비밀번호를 **저장하지 않고**(키체인에도) 매번 묻는다. 저장 시 "이 파일에 Wi-Fi 비밀번호가 평문으로 들어 있다"를 한 줄 표시한다. [내 판단]
3. TV에서 `설정 > 일반 > 프로필 > 프로필 추가`에 `http://eyeproxy/ssl` 입력 → CA 프로필 설치 → `인증서 신뢰 설정`에서 신뢰. 이 단계는 앱 화면에 체크리스트로 보여준다.
4. 트래픽이 들어오면 사이드바에 해당 IP가 뜨고, 이름("거실 Apple TV")을 붙일 수 있다.

### 7.3 iPhone·iPad
- 7.2와 같은 프로필을 AirDrop·메일로 보내거나, Wi-Fi 설정에서 수동 프록시 입력. 이후 Safari로 `http://eyeproxy/ssl`.

### 7.4 확인
- 기기 화면에 "마지막 수신 시각", "SSL 복호화 성공/실패 수"를 보여 인증서 신뢰가 안 된 상태를 바로 알 수 있게 한다(-9813 계열을 Connection Log에 사람 말로).

## 8. 구현 순서

각 단계 끝은 "작성자가 이 단계만으로 Proxyman 없이 할 수 있는 일"로 정의한다.

- **P1 — 보기**: 프록시 엔진 + TLS MITM + Flow 화면 + 기기 온보딩 + 세션 저장. 끝나면: tvOS·iOS 트래픽을 EyeProxy로 본다. 조작은 못 한다.
- **P2 — 조작**: Breakpoint, Map Local, Map Remote, Block/Allow, Network Conditions, No Caching, Compose/Repeat, 필터 전부, WebSocket, HAR, Pin/Comment. 끝나면: 일상 QA·디버깅을 EyeProxy로만 한다.
- **P3 — 자동화·고급**: Scripting, Diff, DNS Spoofing, Reverse/External Proxy, Access Control, GraphQL, HTTP/2 클라이언트, 코드 생성, CLI. 끝나면: Proxyman을 지운다.
- **P4 — 나머지**: 앱 내장 SDK(EyeProxySDK), Protobuf, Custom Certificates, TLS Key Logging, SOCKS, Charles 변환, Gist, OpenAPI.
- **추후**: Android 온보딩 가이드·테스트.

P1이 끝나면 Sparkle 배포 파이프라인(release.sh, appcast)을 먼저 붙인다. 팀원이 일찍 써보고 피드백을 주는 편이 낫다.

## 9. 빌더에게 맡기는 것

- NIO 파이프라인 세부 구성(핸들러 분리, 백프레셔, 바디 스트리밍 vs 버퍼링 임계값).
- 요청 목록 가상화·대용량 세션 성능 전략(수만 건 기준).
- SwiftUI 뷰 분해, 뷰모델 경계, 단축키 배치(단, Proxyman과 같은 단축키는 같게: Map Remote ⌥⌘R, Network Conditions ⌥⌘J, Scripting ⌥⌘I 등 문서에 있는 것).
- 시스템 프록시 변경 방식(`networksetup` + 권한 요청 vs SMAppService 헬퍼). 조건: 비정상 종료 후 복원 가능할 것.
- 규칙 매칭 문법(와일드카드·정규식 모두 지원, Proxyman 규칙과 호환되게).
- 테스트 더블·픽스처 구성.
- 아이콘·앱 비주얼.

## 10. 빌더 검토 결과 (2026-11-05)

검토자가 올린 6개 질문의 처리:

| 질문 | 처리 | 반영 위치 |
|---|---|---|
| 시뮬레이터/Mac 트래픽 구분을 P1에 넣나 | 내 판단: P1은 "이 Mac"에 포함, P2에서 PID 귀속 | §4.3 |
| `.mobileconfig` Wi-Fi 비밀번호 | 내 판단: 매번 입력, 프로필에 평문 포함, 앱은 저장 안 함, 경고 표시 | §7.2 |
| P1 업스트림 h2 필요한가 | 내 판단: P1은 양쪽 h1만 | §4.7 |
| Proxyman 규칙·스크립트를 그대로 돌려야 하나 | **사용자: 그대로 돌아가야 함** → 규칙 가져오기 P2, 스크립트 API 완전 호환 P3 | §4.1, §6 |
| Brotli 때문에 최소 macOS 15로 올리나 | **사용자: 15+** | §3 |
| 팀원 Mac 관리자 권한 | 사용자: 모름, 본인은 있음 → 전원 있다고 가정, 아니면 그때 대안 | §7.1 |

상태: **사용자 승인 대기**. 승인되면 다음 단계는 구현 플랜 작성(superpowers:writing-plans).

## 부록 A. 참고
- Proxyman 문서: https://proxyman.com/docs/
- 사내 tvOS 세팅 가이드: https://tving.atlassian.net/wiki/spaces/TVING/pages/1738342740
- 시뮬레이터 CA: `xcrun simctl keychain <UDID> add-root-cert <ca.pem>` (미설치 시 -9813 / NSURLError -1202)
- 서명·배포 레퍼런스: `~/personal/TvingLoginManager/project.yml`, `scripts/release.sh`
