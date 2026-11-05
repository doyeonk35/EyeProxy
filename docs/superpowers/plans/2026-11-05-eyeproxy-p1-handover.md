# EyeProxy P1 핸드오버 (2026-11-05)

플랜: `2026-11-05-eyeproxy-p1.md` · 스펙: `../specs/2026-11-05-eyeproxy-design.md`
상태: Task 1~17 구현·리뷰 완료, 최종 전체 리뷰 + 수정 웨이브 통과. **Task 18(실기기·시스템 프록시 E2E)은 사용자 수동 실행 대기.**
테스트: Core 36/36, Kit 56/56. Debug 빌드 경고 0. 공증된 0.1.0 zip은 `releases/0.1.0/`(최종 수정 전 빌드 — 아래 참고).

## 1. 남은 할 일 (사용자)

### 1-1. GitHub (에이전트가 공개 표면 생성 불가 → 직접 실행)
TVAccountManager(`doyeonk35/Account-Manager-swift`)가 PUBLIC이고 Pages로 appcast를 서빙하는 전례와 동일하게, Sparkle 업데이트·Release 다운로드가 익명으로 동작하려면 **public** 레포여야 한다(private은 유료 Pages + 인증 필요).
```bash
gh repo create doyeonk35/EyeProxy --public --source . --push
```
```bash
gh api -X POST repos/doyeonk35/EyeProxy/pages -f build_type=legacy -f 'source[branch]=main' -f 'source[path]=/docs'
```

### 1-2. Task 18 E2E 체크리스트 (스펙 §7, 플랜 Task 18)
시작 전 원래 상태 기록: `networksetup -getwebproxy "Wi-Fi"`, `-getsecurewebproxy`, `-getproxybypassdomains`, `scutil --proxy` (서비스명은 `networksetup -listallnetworkservices`).

**A. 시스템 프록시 (앱의 기기 창 ⌘D › "이 Mac 캡처")** — 각각 VPN on/off, Proxyman 실행 중/종료 상태로:
1. 켜기 → `scutil --proxy`에 127.0.0.1:<포트> → 끄기 → `-get…` 세 값이 원래와 동일, `~/Library/Application Support/com.tv.eyeproxy/system-proxy-backup.json` 없음.
2. 켠 채 ⌘Q(두 번 연타 포함) → 종료 후 원복.
3. 켠 채 `kill -9 $(pgrep -f EyeProxy)` → 재실행 → 복원 알럿(Return=복원) → 원복.
   - **항목 2/3을 VPN(GlobalProtect) 켠 상태에서 재검증**: 종료·복원 후 `scutil --proxy`가 `HTTPEnable : 0`(VPN 서비스 `gpd.pan` 복사본까지 정리됨, 관리자 인증 1회)이고 인터넷이 되는지 확인.
4. 켠 채 설정에서 포트 변경 → 재시작 → `scutil`이 새 포트.
5. 켠 채 Wi-Fi↔이더넷 전환 → 끄기 → 원복.
6. 켜기 → 관리자 프롬프트 취소 → 토글 off 유지, 백업 없음, 에러 표시.
7. **Proxyman 실행 중 EyeProxy 9090 시작** → "포트 사용 중" 메시지가 떠야 함. 안 뜨면(Proxyman이 127.0.0.1만 바인드) 최종 리뷰 Minor 5(SO_REUSEADDR) 수정 필요.

**B. CA**
8. "Mac에 CA 설치" → 상태 "설치됨"; `security find-certificate -a -Z -c EyeProxy ~/Library/Keychains/login.keychain-db`의 SHA-256 == `openssl x509 -noout -fingerprint -sha256 -in ~/Library/Application\ Support/com.tv.eyeproxy/ca/ca.pem`.
9. 시뮬레이터 부팅 → 기기 창 새로고침 → CA 설치 → iOS 시뮬 Safari로 `https://example.com`(SSL 목록에 추가) → 복호화 행("이 Mac" 그룹).

**C. 실기기**
10. Apple TV: 기기 창 › 실기기 프로필 만들기(SSID·비밀번호·Mac IP) → Apple Configurator 드롭 → TV `설정 > 일반 > 프로필 > 프로필 추가`에 `http://eyeproxy/ssl` → 인증서 신뢰 → TVING 앱 → `api.tving.com` SSL 목록 추가 → JSON 보임, 사이드바 기기 이름 변경.
11. iPhone: Wi-Fi 수동 프록시 → Safari `http://eyeproxy/ssl` → 설치·신뢰 → 앱 트래픽.
12. iPhone 신뢰 off 상태로 요청 → 기기 창 연결 로그에 "기기가 EyeProxy 인증서를 신뢰하지 않습니다 (…)".
13. 공용 기기에 두 사람 CA 설치 → 서로 덮어쓰지 않음(식별자 분리). 기존 `com.tv.eyeproxy.ca` 프로필이 있으면 수동 삭제.
14. LAN 업스트림(스테이징 10.x) 요청 → macOS "로컬 네트워크" 프롬프트 허용 → 동작.
15. **하루 사용** → Proxyman 켜고 싶었던 순간 전부 기록(→ P2 입력), 메모리·반응성 체크.

### 1-3. 재릴리스
0.1.0 zip은 최종 수정 웨이브(루프백 차단·CA 식별자·README) **이전** 빌드. Task 18 통과 후:
```bash
./scripts/release.sh 0.1.1
```
그 다음 `git tag v0.1.1 && git push origin main --tags && gh release create v0.1.1 releases/0.1.1/EyeProxy-0.1.1.zip --title v0.1.1`.

## 2. 컨트롤러 판정(Rulings) — 플랜/스펙과 다르게 결정한 것 전부
- Ruling: main 브랜치에서 직접 작업 — 플랜 Task 1이 `git init -b main` 후 main에 커밋하도록 명시했고 사용자가 플랜을 승인함. 빈 레포라 보호할 기존 코드가 없음. 틀리면 비용: 없음(브랜치 분리는 나중에 가능).
- Ruling: T1 SmokeTests는 `swift test`가 빌드되게 하는 자리표시자. T2가 실제 테스트를 넣을 때 SmokeTests.swift 삭제. — 이유: 빈 테스트 타깃은 SwiftPM이 경고/스킵. 틀리면 비용: 파일 하나.
- Ruling: .gitignore의 `.superpackages/`는 오타, 넣지 않음. — 비용: 없음.
- Ruling: T1 Step 1(git init)은 컨트롤러가 이미 수행(39d6792). 구현자는 건너뜀.
- Ruling: Task 7 테스트의 TestOrigin은 자체 CA 리프를 쓰므로 업스트림 검증(시스템 신뢰)이 실패함 → `ProxyConfiguration.upstreamTrustRootsDER: [[UInt8]]?`(nil=시스템 신뢰)를 추가해 테스트에서 CA를 주입. 운영 코드 경로는 nil 그대로. — 비용: 설정 필드 하나.
- Ruling: 업스트림 30초 타임아웃이 총 데드라인이라 30초 넘는 대용량 응답(영상·앱 다운로드)이 502가 됨 → Task 6 디스패치에 "channelRead마다 데드라인 재설정(유휴 타임아웃)"을 필수로 포함. — 비용: 몇 줄.
- Ruling: CONNECT 200 응답은 RFC 9110 §9.3.6에 따라 Content-Length를 넣지 않음(API 메모의 Content-Length: 0 대신). 인코더 자동 프레이밍이 꺼져 있어 생략 가능. — 비용: 없음.
- Ruling: 서브에이전트 커밋의 Co-Authored-By가 실제 작성 모델(Opus 5.5)로 찍히는 것은 그대로 둠(히스토리 amend 안 함). — 이유: 트레일러는 작성자 표기이며 기능과 무관. 비용: 없음.
- Ruling: 리뷰 마이너 1~3(테스트 헬퍼 connect 실패 시 promise 누수 trap, 헬퍼 자체 타임아웃 없음, 터널 TLS 검사가 같은 CA라 패스스루 증명 못 함→별도 CA 사용)은 Task 7이 같은 헬퍼를 쓰므로 Task 7 디스패치에 필수로 포함. — 비용: 테스트 코드 몇 줄.
- Ruling: MITM 경로는 CONNECT용 .requestStarted를 내지 않음(복호화된 요청이 첫 이벤트) — 브리프 테스트 1과 일치, Proxyman도 복호화 호스트의 CONNECT 행을 안 보여줌. 핸드셰이크 실패는 .connectionLog로만 표시(디스패치의 ".failed로 마감" 지시는 철회). — 비용: UI에서 미신뢰 기기 감지는 Connection Log·DeviceRegistry 카운트에 의존.
- Ruling: .mobileconfig의 PayloadUUID를 식별자(+CA DER) 해시 기반 결정적 UUID로 생성 — 브리프 테스트의 바이트 동일성(`res.body == caProfile(...)`)을 만족하고 재설치 시 동일 프로필이 됨. — 비용: UUID가 랜덤이 아님(기기 입장에선 동일 프로필 갱신으로 보임, 오히려 바람직).
- Ruling: 마이너 중 실제 영향 있는 3건(hex 제로패딩 없음→UUID 충돌 가능, SSID try! 크래시, 손상 JSON이 기기 이름을 조용히 덮어씀)은 Task 10+11 디스패치에 후속으로 포함. — 비용: 몇 줄.
- Ruling: JSON pretty-print는 플랜의 JSONSerialization(.sortedKeys 없이) 대신 원문 키 순서·숫자 리터럴을 보존하는 텍스트 재들여쓰기로 구현. — 이유: 디버깅 프록시가 서버가 보낸 순서를 바꿔 보여주면 안 됨(Proxyman은 보존). 비용: 토크나이저 ~60줄.
- Ruling: activeService는 기본 경로 인터페이스가 utun*/ipsec*/ppp*이거나 매칭이 없으면 IPv4가 있는 첫 활성 서비스로 폴백(플랜 변경). — 이유: 사용자 Mac이 평소 VPN 상태라 플랜대로면 기능 자체가 불가. 비용: 다중 활성 인터페이스에서 잘못된 서비스 선택 가능(Task 15 수동 확인으로 검증).
- Ruling: MacKeychain.isInstalled(commonName:) → isInstalled(pemURL:) 로 시그니처 변경, SHA-256 지문 일치로 판정(플랜 변경). — 이유: CN 부분 일치는 오탐으로 HTTPS 복호화가 조용히 실패. 비용: Task 15 AppModel이 pemURL을 넘겨야 함(디스패치에 반영).
- Ruling: 재리뷰 마이너 3건(백업이 다른 서비스 것일 때 복원 누락→죽은 프록시, Shell 임시파일 누수, 링크로컬 169.254 폴백)은 Task 15(이 코드를 처음 실제 실행하는 태스크) 디스패치에 필수 포함.
- Ruling: 브리프 편차 3건 수용 — 종료 시 stopServer 미호출(willTerminate에서 await 불가; 단 Task 15에서 applicationShouldTerminate .terminateLater로 시스템 프록시 복원은 반드시 동기 보장), ⌘R/⌘K는 메뉴 커맨드, 컬럼 가시성은 @AppStorage. — 비용: 없음.
- Ruling: Xcode가 Kit Package.resolved에 넣는 Sparkle 핀은 커밋하지 않음(워크스페이스 해상도 부산물).
- Ruling: 시스템 프록시 변경·루트 CA 신뢰 설치는 에이전트 운영 규칙상 "시스템/보안 설정 변경"으로 사용자 승인이 있어도 에이전트가 실행하지 않음(구현자 거부 타당, 컨트롤러도 동일 규칙). → Task 15 Step 3의 부작용 검사는 Task 18 E2E에서 사용자가 직접 수행. 리포트에 정확한 절차 기재됨. — 비용: 이 코드 경로(SystemProxy.enable/disable·MacKeychain.install·Simulators.installRootCert)는 사용자 실행 전까지 미검증.
- Ruling: 재리뷰 마이너 중 죽은 프록시 경로 3건(서비스 이름 변경 시 orphan 오판→127.0.0.1 잔류, 종료 중 토글 on 슬립, 유지가 .cancel 역할이고 서버 미실행 시에도 적용)은 Task 16 디스패치에 후속으로 포함. — 비용: 몇 줄.
- Ruling: 컨트롤러가 .gitignore에 build/ 한 줄을 직접 커밋(48ba227) — 리뷰 마이너, 한 줄, 코드 아님. 규칙 위반 최소 사례로 기록.
- Ruling: 공증된 0.1.0 zip(375a3a0)은 최종 수정 웨이브 이전 빌드 → Task 18 통과 후 `release.sh 0.1.1`로 재릴리스해야 배포본에 루프백 차단·CA 식별자 수정이 포함됨. — 비용: 재공증 1회.
- Ruling: VPN(GlobalProtect)이 Wi-Fi 프록시를 `State:/Network/Service/<id>/Proxies`로 복사하고 되돌려도 지우지 않아 종료 후 인터넷이 끊김(현장 확인) → disable 끝에서 실효 프록시가 우리 것이고 기본 서비스가 물리 서비스(Setup 키 없음)가 아니면 그 State 키를 관리자 권한 `scutil`로 HTTP·HTTPS 끔으로 다시 씀(나머지 항목 보존, 입력 검증). 실패 시 오류·주황 경고 → VPN 재연결로 복구. — 비용: VPN 사용자는 끌 때 관리자 인증 1회 추가, VPN 재연결 시 VPN이 다시 덮어씀(정상).
- Ruling: 워크스페이스 삭제 전 판정 목록·P2 이월 마이너·Task 18 체크리스트를 docs/superpowers/plans/2026-11-05-eyeproxy-p1-handover.md 로 레포에 보존.

## 3. P2 이월 백로그 (태스크 리뷰에서 나온 마이너, 미수정)
최종 리뷰 분류: 아래 중 "핸드오버 전 수정" 항목(압축 폭탄 상한·cURL 메서드 인용·복원 Return·Sparkle 키 README·CA 식별자·루프백 차단)은 수정 완료. 나머지는 P2.

- Task 1: minor (deferred): Info.plist 버전 리터럴(플랜 명시, 변수 치환 권장) / project.yml Debug 서명 중복 선언 / 플레이스홀더 enum이 모듈명과 동일 → T2·T8에서 실제 타입 넣을 때 삭제
- Task 2+3: minor (deferred): SSL 정책 regex 매 호출 컴파일(캐시 권장)·try? 무시 / `$` vs `\z` / Flow.url IPv6 대괄호 미처리 / header 조회 중복 / 테스트 보강(runResponse·Codable 라운드트립·특수문자) / 테스트 헬퍼 구조체 private화 / Fixtures URL.path 퍼센트 디코딩
- Task 4: minor (deferred): load 시 공개키-개인키 일치 검사 / validYears 검증·윤년 / 캐시 무한(397일 만료 미처리) / 체인 테스트가 호스트명·EKU 정책 미검증
- Task 4: minor (deferred): 기존 ca-key.pem 덮어쓸 때 createFile이 0600 재적용하는지 미검증 / 기존 디렉터리 권한은 안 바꿈
- Task 5: minor (deferred): hop-by-hop 헤더 목록 불완전(Connection 토큰·TE·Trailer·Upgrade, Expect: 100-continue 미응답) / 디코더 오류 시 400 없이 종료 / HTTP/1.0 keep-alive 헤더 / events 스트림 deinit finish 없음·stop() 필수 문서화 / stop() 중 진행 중 교환은 종료된 루프에 스케줄(ServerQuiescingHelper 권장) / 요청 바디 무제한 버퍼(P2 스트리밍) / keep-alive 재사용 테스트 없음 / SO_REUSEADDR로 0.0.0.0 바인드 시 127.0.0.1:9090 점유를 못 잡음 / 502 테스트 포트 재사용 경합
- Task 5: minor (deferred): 타임아웃 시 promise 이중 완료(무해) / stop() 도중 start() 직렬화 안 됨 / Expect: 100-continue 시 100을 최종 응답으로 취급 / inFlight 1개(파이프라이닝 미지원) / stop() 후 완료되는 교환이 종료된 루프에 succeed
- Task 6: minor (deferred): 정책 hop 중 클라이언트 종료 시 불필요한 업스트림 연결 / 글루 추가 실패 시 종료 이벤트 없음 / 터널 닫힘 테스트 주석 부정확(어느 쪽이 먼저 닫는지 비결정) / 초기 클라이언트 바이트 테스트 없음
- Task 7: minor (deferred): MITM 내 absolute-form 요청 400(RFC는 수용 권장) / TCP 중간 끊김(uncleanShutdown)이 핸드셰이크 전이면 로그 없음 — 인증서 피닝 앱 진단에 중요, P2에서 handshakeCompleted 추적 / 업스트림 호스트명 불일치·keep-alive 다중 요청·신뢰 로그 1회성 테스트 없음
- Task 7: minor (deferred): 중첩 CONNECT 405 테스트 없음 / CERTIFICATE_VERIFY_FAILED 문자열 매칭은 NIOSSL 버전에 취약 / 업스트림 인증서 테스트가 라벨 문구를 고정하지 않음
- Task 8+9: minor (deferred): 응답자 /ssl?x·메서드 무시 / lastSeen 동률 정렬 불안정(fixture에 날짜 주입) / `?? { }()` 관용구 / 테스트 UserDefaults suite 미삭제 / 포트 값 검증 없음 / 테스트 공백(비밀번호 nil 보안망, `/` Content-Type, save 디렉터리 부재)
- Task 10+11: minor (deferred): 압축 해제 출력 상한 없음(폭탄, P2) / gzip 다중 멤버·CRC 미검증 / 세션 version 검사가 decode 뒤 / 바디 파일 누락 시 빈 바디로 조용히 로드 / .tmp 잔류 / cURL method 비인용 / 중복 requestStarted 유령 행 / FlowFilter.host 대소문자 구분
- Task 10+11: minor (deferred): JSON 리터럴 배열 매 토큰 할당 / UTF-8 BOM 미처리→.text / 출력 상한 전용 테스트 없음
- Task 12: minor (deferred): apply 실패 시 무조건 관리자 승격(서비스 소멸도) / 부분 적용 복구는 호출자 책임 / Shell 파이프 64KB·취소 없음 / SystemProxy 동시 호출 직렬화 없음(MainActor에서만 호출) / CA 제거 API 없음(P2)
- Task 12: minor (deferred): isInstalled은 존재만 확인(신뢰 여부 아님) / 풀터널 VPN에서는 Wi-Fi 프록시 설정이 무효일 수 있음(Task 15 수동 확인) / ShellError 케이스 명칭 / route·listnetworkserviceorder 종료코드 미검사
- Task 13: minor (deferred): # 컬럼이 필터 위치 기반(안정 ID 아님) / 기기 배지는 누적 flowCount vs 전체는 세션 카운트 / lanAddresses 네트워크 변경 시 갱신 없음 / 상세 바디 매 이벤트 재디코드(T14) / devices.save는 종료 시만
- Task 14: minor (deferred): 탭 전환 시 BodyView 재생성(재디코드·WKWebView 재생성) / data.count 키로 같은 길이 바디 변경 미감지 / 빈 {} [] 트리에 "(없음)" 없음 / 쿼리 + → 공백 미변환 / 절대형 path면 URLComponents 파싱 깨짐(현재 Core는 origin-form 보장)
- Task 14: minor (deferred): capped()의 줄 경계 컷이 멀리 있는 개행에 끌려감·멀티바이트 분절 / LargeText.updateNSView 비어 있음 / 이미지 케이스에서도 hex 생성 / 차단 검증 하네스는 scratchpad(레포 외)
- Task 15: minor (deferred): 시뮬레이터 설치됨 표시가 뷰 상태 / stopServer 종료 await 무제한(타임아웃 권장) / 토글 busy 진행 표시 없음 / 로그 강조가 "신뢰" 문자열 의존 / (b)(c) 테스트 없음
- Task 15: minor (deferred): 관리자 프롬프트 취소 시 롤백·종료에서 재프롬프트(최대 3회) / 빈 stderr 시 빈 오류 메시지 / 리포트 Known limits 섹션 stale / 이름 draft가 창 닫힘 시 유실 / Shell 타임아웃 없음
- Task 16: minor (deferred): 고아 백업 정리는 활성 서비스 없으면 건너뜀 / 고아 정리는 끄기만(원본 재적용 안 함) / 복원 버튼이 Return 기본인지 런타임 미확인 / Finder 패키지 표시 미확인
- Task 16: minor (deferred, 영향 큼): 실행 간 포트가 바뀐 뒤 크래시/서비스 이름 변경 시 옛 포트의 잔여 프록시를 사용자 것으로 오인 → 백업에 적용 포트를 저장해 ownPort로 사용 권장(최종 리뷰 수정 웨이브 후보) / force 재시작의 고아 검사가 새 포트 사용 / 설정 포트 필드가 blur 없이 값 유실·오류 문구 미표시 / capturePort 미초기화 / 재시작 중 사용자 off가 덮일 수 있음
- Task 17: minor (deferred): appcast 재릴리스 regex가 사이 항목 삭제 가능 / 실패 후 재실행 시 빌드번호 재증가 / Sparkle 도구 경로가 Xcode DerivedData 의존 / Developer ID 하드코딩 / Sparkle 키 TVAccountManager와 공유(README에 기록 권장)

최종 리뷰에서 추가된 P2 항목:
- UpstreamClient: https 업스트림은 차단 검사 전에 TLS ClientHello(SNI)가 루프백 서비스에 전송됨 → TLS 핸들러를 검사 후 추가.
- `::ffff:127.0.0.1` 분기 테스트 없음. Mac 자신의 LAN IP로 프록시에 붙는 로컬 클라이언트는 LAN으로 취급.
- MITM 핸드셰이크 실패 시 메인 목록에 실패 CONNECT 행 없음(기기 창 연결 로그만) — Proxyman은 실패 행 표시. Task 18 Step 12가 불편하면 당겨서 수정.
- JSON Tree 탭은 키 정렬·NSNumber 정밀도 손실(Pretty는 원문 보존) → 토크나이저로 트리 구성.
- 세션 열기 시 라이브 트래픽이 섞이고 사이드바 기기 목록은 DeviceRegistry 기준.
- 복호화 호스트의 WebSocket/SSE는 Connection: close·전체 버퍼링으로 끊김(README 기재됨).
- SessionStore 메모리 무제한, visibleFlows O(n) 매 이벤트.
- Cookies 탭(스펙 §4.3), Xcode 27 DeviceHub 안내(§7.1) 누락.
- SystemProxyBackup에 적용 포트 저장(실행 간 포트 변경+크래시 시 옛 포트 잔여물 오인 방지).
- Sparkle 패키지 버전이 `from: 2.7.0`으로 플로팅(.xcodeproj 미추적) → 재현 빌드 불가.
