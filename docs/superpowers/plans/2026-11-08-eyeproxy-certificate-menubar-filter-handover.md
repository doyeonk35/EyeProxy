# Prog Certificate 메뉴·상태 막대·필터 바 핸드오버 (2026-11-08)

플랜: `2026-11-08-eyeproxy-certificate-menubar-filter.md` · 스펙: `../specs/2026-11-08-eyeproxy-certificate-menubar-filter-design.md` · 브랜치: `certificate-menubar`
상태: Task 1~13 구현·리뷰 완료. 아래 2장의 **미확인** 항목은 사용자 실행 대기(키체인·실기기·adb·Sparkle은 사람이 확인한다).
테스트: `swift test --package-path Packages/EyeProxyCore`, `swift test --package-path Packages/EyeProxyKit`.

## 1. 개요

Proxyman 기준으로 메뉴 막대를 재편하고, 목록 위 필터 바와 상태 막대 메뉴를 더하고, 개구리 아이콘을 넣고, 표시 이름을 Prog으로 바꿨다. 번들 ID·식별자·레포는 그대로다.

| Task | 내용 |
|---|---|
| 1 | Kit: 흐름 분류(`FlowProtocol`·`ContentKind`)와 `FlowFilter`의 프로토콜·콘텐츠·상태 묶음. |
| 2 | 앱: 필터 바 뷰(칩, 묶음 안 OR·사이 AND, 저장 안 함, 접근성 선택 상태). |
| 3 | Kit: `/ssl` 확장 — Android UA는 PEM, `/ssl.crt`·`/ssl.pem`·`/ssl.cer`, `prog` 별칭, 안내 페이지 지문. |
| 4 | Core+Kit: 루트 CA 내보내기(PEM·DER·P12·개인키, 0600). |
| 5 | Kit+앱: CA 초기화 — `ca-backup-<시각>/`로 백업 뒤 새 CA 생성·서버 재시작. |
| 6 | 앱: 기기 창을 Certificate 창(섹션 8개)으로 재편, 내보내기·초기화 UI. |
| 7 | Kit+앱: Android 섹션(실기기·에뮬레이터·Android TV 탭, adb 탐색·명령). |
| 8 | Kit+앱: 개발 환경 섹션(플랫폼별 스니펫, Firefox). |
| 9 | 앱: Certificate 메뉴, Tools ▸ Proxy Settings, "프록시" 메뉴 제거. |
| 10 | 앱 아이콘·상태 막대 템플릿 에셋과 `scripts/make-icons.sh`. |
| 11 | 상태 막대 개구리 메뉴(Proxyman 순서), 툴바 기록 버튼 ▶/⏸. |
| 12 | 표시 이름 EyeProxy → Prog(번들 ID·식별자 유지). |
| 13 | README 기능 설명과 이 문서. |

## 2. 수동 점검표

시작 전: Proxyman 등 다른 프록시가 같은 포트를 쓰지 않는지 확인한다. 끝나면 기기 프록시 설정과 adb 프록시(`adb로 프록시 해제`)를 되돌린다.

| 항목 | 절차 | 기대 결과 | 상태 |
|---|---|---|---|
| Mac CA 설치 | Certificate ▸ Install Certificate on this Mac… | 확인 알림 → 관리자 인증 → 완료 메시지, 이 Mac 섹션에 "로그인 키체인에 설치됨" | [x] 확인됨 2026-11-08 |
| Export PEM | Certificate ▸ Export ▸ Root Certificate as PEM… → 저장 | 저장 패널 기본 이름 `Prog-CA.pem`, 파일이 `…/com.tv.eyeproxy/ca/ca.pem`과 바이트 동일 | [x] 확인됨 2026-11-08 |
| 필터 칩 + 사이드바 | 칩 여러 개를 고르고 사이드바 호스트 필터를 함께 건다. 위아래·좌우 레이아웃 모두 | 묶음 안 OR·사이 AND, 사이드바와 AND로 겹침. `All`이 모두 해제 | [x] 확인됨 2026-11-08 |
| Certificate 창 섹션·딥링크 | 메뉴 Android ▸ Emulators·Physical Devices, Developments ▸ Python, Firefox, iOS ▸ Simulators·watchOS or tvOS | 창에 섹션 8개, 항목마다 해당 섹션·탭·플랫폼으로 열림, 열린 창은 섹션만 바뀜 | [x] 확인됨 2026-11-08 |
| Record Traffic 동기화 | 상태 막대 메뉴 Record Traffic 토글, 툴바 버튼·⌘R | 세 곳이 같은 값, 툴바는 기록 중 ▶ / 일시정지 ⏸ | [x] 확인됨 2026-11-08 |
| Listen on 복사 | Listen on ▸ Copy / Copy IP / Copy Port / Copy Shell Command | 클립보드에 `ip:port`, IP, 포트, `export https_proxy=… http_proxy=…` | [x] 확인됨 2026-11-08 |
| Show Prog | 메인 창을 닫고 상태 막대 메뉴 Show Prog | 앱이 앞으로 오고 메인 창이 다시 열림 | [x] 확인됨 2026-11-08 |
| 상태 막대 설정 토글 | 설정 ▸ 일반 ▸ 상태 막대에 아이콘 표시 끄기·켜기 | 아이콘이 숨고 다시 보임 | [x] 확인됨 2026-11-08 |
| 앱 이름 | 앱 메뉴·창 제목 확인 | "Prog", "Quit Prog" | [x] 확인됨 2026-11-08 |
| 기존 데이터 유지 | 기존 설정·규칙·CA가 있는 상태로 실행 | 설정·규칙·CA가 그대로 로드됨(CA 재생성 없음) | [x] 확인됨 2026-11-08 |
| 검색어 + 필터 칩 | 검색어를 넣은 채 칩을 고르고 풀기 | 검색어와 칩이 AND로 겹치고 칩을 바꿔도 검색어 유지 | [ ] 미확인 |
| 메인 창 알림 폴백 | Certificate 창을 닫은 채 Certificate ▸ Install Certificate on this Mac… | 결과 알림(`infoMessage`)이 메인 창에 뜸 | [ ] 미확인 |
| 시뮬레이터 설치 | iOS ▸ Simulators… → 부팅된 시뮬레이터 CA 설치 → 앱 재실행 | 한 번 클릭으로 설치·설치됨 표시, 시뮬레이터 HTTPS 복호화 | [ ] 미확인 |
| iPhone `/ssl` | iPhone을 Prog 프록시로 두고 Safari로 `http://prog/ssl`, 이어서 `http://eyeproxy/ssl` | 두 주소 모두 `Prog-CA.mobileconfig` 프로필을 내려 줌, 설치·신뢰 후 HTTPS 복호화 | [ ] 미확인 |
| Android 실기기 | Wi-Fi 수동 프록시 → Chrome으로 `http://prog/ssl` → 설정 ▸ 보안 ▸ … ▸ CA 인증서 | `Prog-CA.crt` 다운로드, 사용자 CA로 설치(앱은 `network_security_config` 필요) | [ ] 미확인 |
| Android 에뮬레이터 adb | adb 설치 뒤 Prog 재실행(adb는 창을 만들 때 찾음) → Emulators… → `adb로 프록시 설정 + CA 복사`, `adb로 프록시 해제` | 결과 출력 표시, 에뮬레이터 프록시가 `10.0.2.2:<포트>`, Download에 `Prog-CA.crt`, 해제 뒤 프록시 없음 | [ ] 미확인 |
| Android TV | 네트워크 디버깅 켜기 → TV IP 입력 → `adb connect` → `adb로 프록시 설정 + CA 복사` → `인증서 설치 화면 열기` | 연결 성공, TV 프록시가 Mac LAN IP, 인증서 설치 화면이 뜨고 리모컨으로 설치 | [ ] 미확인 |
| P12 (비밀번호) | Export ▸ Root Certificate as P12… → 비밀번호 입력 → 키체인 접근으로 가져오기 | 같은 비밀번호로 인증서와 개인키가 들어옴 | [ ] 미확인 |
| P12 (빈 비밀번호) | 위와 같고 비밀번호를 비움 | 비밀번호 없이 가져오기 성공 | [ ] 미확인 |
| Private Key | Export ▸ Private Key… | 경고 알림 뒤 저장, `ls -l`로 권한 `-rw-------`(0600) | [ ] 미확인 |
| Reset | Reset all Prog Certificates… → 확인 | `ca-backup-<yyyyMMdd-HHmmss>/` 생김, 내보내기·초기화 섹션의 지문이 바뀜, 서버 재시작. Mac·시뮬레이터에 다시 설치하면 HTTPS 복호화 회복(기기는 재설치 필요) | [ ] 미확인 |
| 상태 막대 아이콘 표시 | 메뉴 막대에 여유가 있는 상태에서 앱을 세 번 실행 | 매번 실행 직후 개구리 아이콘이 보임(한 번 안 보였던 적 있음; 꽉 찬·노치 막대에서는 "»" 안에 숨는 게 정상) | [ ] 미확인 |
| 아이콘 세 상태 | 기록 켜기 / 기록 끄기 / 서버 중지(설정에서 다른 앱이 쓰는 포트로 바꾸고 서버 다시 시작) | 눈 뜬 개구리 / 눈 감은 개구리 / 물결·공기방울, 중지면 `Listen on — (Stopped)` | [ ] 미확인 |
| 밝은·어두운 막대 | 시스템 화면 모드를 바꿔 가며 아이콘 확인 | 템플릿으로 막대 색을 따르고 눈동자·공기방울이 뚫려 보임 | [ ] 미확인 |
| 설정 토글 뒤 재표시 | 상태 막대에 아이콘 표시를 끈 뒤 다시 켬 | 아이콘이 다시 나타나고 메뉴가 정상 동작 | [ ] 미확인 |
| VoiceOver 칩 상태 | VoiceOver로 필터 칩 이동 | 칩 이름과 "선택됨" 상태를 읽음 | [ ] 미확인 |
| Sparkle 0.2.0 → Prog | 릴리스 뒤 0.2.0 EyeProxy.app에서 업데이트 확인 | 업데이트 성공, 앱 이름 Prog으로 실행, 파일명은 EyeProxy.app 그대로. 설정·규칙·CA 유지 | [ ] 미확인 |
| xcstrings 동기화 | Xcode GUI에서 한 번 빌드(CLI 빌드는 갱신 안 함) → `Localizable.xcstrings` 커밋 | 새 문자열 추가, 지운 메뉴 키·옛 `/ssl` 키가 stale 표시 | [ ] 미확인 |

확인됨 10 · 미확인 18.

## 3. 알려진 제한·보류 사항

README `## 알려진 제한(Certificate·필터 바·상태 막대)`에 사용자용 제한(WebSocket 필터 없음, Android 사용자 CA, LibreSSL P12, Listen 주소 갱신, "»" 숨김)을 적었다. 아래는 리뷰에서 나와 보류한 소소한 항목이다.

**필터 바·분류**: 분류 코드의 중첩 옵셔널이 읽기 어렵고, 테스트가 `application/graphql`·`ecmascript`·폰트·urlencoded·1xx/5xx 같은 가장자리를 덜 다룬다. 칩 툴팁은 "응답 없으면 요청 Content-Type"과 우선순위를 말하지 않는다. 좌우 레이아웃에서 바가 상세 열 위까지 걸친다(스펙 문구와 미세하게 다르지만 보기엔 문제없음).

**`/ssl`·내보내기·초기화**: `/ssl` 응답 생성 코드가 세 곳에 중복되고, User-Agent 없음·`/ssl?x`·`/ssl/` 테스트와 롤백 경로 테스트가 없으며, 지문 테스트는 구현을 다시 계산하는 동어반복이다. 내보내기 대상 파일 교체(remove→move)와 `cert.pem` 쓰기가 원자적이지 않고, P12 테스트는 개인키 포함을 증명하지 못한다. 초기화는 멈춰 있던 서버도 켜고, 롤백 실패를 묵살하며 백업 경로를 알려 주지 않는다. 리셋 성공 뒤에도 옛 CA 저장 오류 배너가 남을 수 있다(이론적).

**Certificate 창·메뉴**: 섹션별 진행 상태가 섹션을 바꾸면 초기화되고, 저장 패널에 파일 형식 제한이 없다. 확인 알림의 기본 버튼이 실행 버튼이라 Return으로 Reset·Private Key가 확정된다 — 취소를 기본으로 둘지 검토. 메인 창 알림 폴백은 위 점검표에 있다. 일부 주석·열거형 채택이 낡았다(ToolWindow의 "기기 ⌘D" 주석 등).

**Android·개발 환경**: adb push용 임시 `Prog-CA.crt`를 지우지 않고, TV IP 입력을 다듬거나 검사하지 않는다. adb는 창을 만들 때 한 번만 찾고, adb 출력이 탭끼리 공유되며, 기기가 둘 이상일 때 `-s` 안내가 없다. 개발 환경 스니펫 테스트가 약하고(React Native·Docker 호스트·Java keytool 미검증), keytool에 `-noprompt`가 없고 JDK 8 경로를 다루지 않으며, 경로는 따옴표만 씌운다. Electron 단계 문구가 오해를 살 수 있다.

**아이콘·상태 막대**: 아이콘 스크립트는 qlmanage 오류를 숨기고(산출물 존재 검사로 보완) 경로에 `:`가 없다고 가정한다. 도구 토글이 Tools 메뉴와 상태 막대 메뉴에 따로 선언되어 새 스위치를 추가하면 두 곳을 고쳐야 한다. Listen 주소는 관찰되지 않는 계산값이라 네트워크 변경을 바로 따라가지 않는다.

**이름·문자열**: `Localizable.xcstrings`에 지운 메뉴 키와 옛 `http://eyeproxy/ssl` 키가 남아 있다(Xcode 빌드로 정리). "Prog" 접두 프로세스 검사가 넓고, Debug 앱 메뉴도 "Prog"로 보이며, multipart 경계 토큰 `EyeProxyBoundary`는 내부 식별자라 유지했다.

## 4. 릴리스 메모

- 표시 이름은 **Prog**(Debug는 Prog-Debug), 번들 ID `com.tv.eyeproxy`(.debug)는 그대로다. 설정·Application Support·설치된 CA·프로파일이 이어진다.
- Sparkle 피드는 기존 자리(`https://doyeonk35.github.io/EyeProxy/appcast.xml`)라 0.2.0에서 자동 업데이트가 이어진다. 레포 이름은 바꾸지 않는다.
- Sparkle로 업데이트한 설치본은 파일명이 EyeProxy.app으로 남는다. 바꾸려면 Finder에서 이름을 바꾸거나 zip으로 재설치하고 옛 복사본을 지운다(같은 번들 ID라 둘 다 두면 안 됨).
- `./scripts/release.sh <version>`은 `Prog-<version>.zip`을 만들고 appcast 제목도 Prog다. 기존 appcast 항목은 그대로 둔다.
- 릴리스 전에 Xcode GUI에서 한 번 빌드해 `Localizable.xcstrings`를 동기화하고 커밋한다.
- 릴리스 노트에 "앱 이름이 Prog으로 바뀌었고 설정·인증서는 그대로"를 적는다. 이미 설치된 CA 이름은 EyeProxy 그대로이고, Reset하면 새 이름(Prog Root CA)으로 다시 만들어진다.
