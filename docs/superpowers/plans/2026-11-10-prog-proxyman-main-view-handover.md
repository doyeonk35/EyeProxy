# Prog 메인 화면을 Proxyman처럼 — 핸드오버 (2026-11-10)

플랜: `2026-11-10-prog-proxyman-main-view.md` · 스펙: `../specs/2026-11-10-prog-proxyman-main-view-design.md`(목업 `…-mockup.html`) · 브랜치: `feat/proxyman-main-view`(base `f55c07e`)
상태: Task 1~6, 8, 9 구현·리뷰 완료(플랜에 Task 7은 없다). 아래 3장의 점검표는 모달·시스템 프록시·클립보드·실기기가 필요해 자동 확인에서 뺀 것이라 사람이 확인한다.
테스트: `swift test --package-path Packages/EyeProxyKit` 362개, `swift test --package-path Packages/EyeProxyCore` 60개. 매 Task 끝에 Debug 앱 빌드 성공.

## 1. 무엇이 들어갔나

메인 창을 Proxyman 배치·이름·단축키에 맞췄다. 기록 버튼은 누르면 할 일을 보이고, 목록은 최신이 위, 툴바 검색칸 대신 규칙 여러 줄의 필터 막대, Favorites·Remote devices·All 사이드바와 경로 트리, 켜진 도구 배지가 있는 하단 바, Request·Response 탭 묶음, 설정 6탭. 사용자 설명은 README의 메인 화면·상세 패널·설정·단축키·알려진 제한(메인 화면·설정) 절.

| Task | 내용 | 커밋 |
|---|---|---|
| 0 | 스펙·플랜·목업. | `06c3c92` |
| 1 | 기록 버튼(기록 중 ⏸, 멈춤 ▶), 기본 정렬 ID 내림차순(저장 안 함), 툴바 캡슐 `● Prog \| Listening on <IP>:<포트>`(+` \| Pause`), Sparkle이 새 버전을 찾으면 `New Update ⚠` 배지(업데이터를 `AppDelegate`로 옮겨 delegate로 받음), 응답 전 Active 행 Code `-`. | `c2774f0` |
| 2 | Kit: `FilterKey` 16개·`FilterMatch` 12개·`FilterRule`·`FilterSubject`, `FlowFilter.rules`(최대 10)·`combineWithOr`·Codable(옛 `text`는 URL·Contains 규칙으로 옮김). 대소문자 무시는 `NSString` 검색(1 MB에서 Swift 대비 약 28배 빠름), 정규식 캐시. | `c6d4501` |
| 3 | 필터 막대(⌘F, 규칙 줄, AND/OR, Esc 숨김), Edit ▸ Find의 New/Remove/Previous/Next/Toggle Filter(막대 포커스일 때만), `eyeproxy.filterRules` 저장, 본문 규칙은 150 ms 디바운스 뒤 메인 밖 계산(세대 번호로 낡은 결과 버림), 툴바 `.searchable` 제거. | `228c5a4` |
| 3 수정 | 실행 때 복원된 규칙 칸이 포커스를 뺏던 것(목록으로), 트래픽 폭주 중 이벤트마다 전체 재필터·정렬하던 것을 `ThrottledRefresh`(최대 0.25초 묶음)로. 5,000 요청 폭주 중 키 입력 1.3~1.6초 → 0.11~0.20초, 폭주 뒤 유휴까지 81초 → 9.6초. 사이드바 트리·개수도 같은 경로로 캐시. | `3939ce9` |
| 4 | 사이드바 Favorites ▸ Pinned, Remote devices(없으면 숨김), All ▸ All Requests·Apps·Domains, 도메인 경로 트리(깊이 4, 세그먼트 단위 접두), 사이드바 Filter(⇧⌘F, 사이드바 포커스일 때만), `+` Add Pinned Domain 시트, 우클릭 Pin/Unpin·Enable SSL Proxying·Copy Domain. `SidebarItem`을 Kit으로 옮겨 개수 테스트가 앱과 같은 매핑을 쓴다. | `34ea5cb` |
| 5 | 하단 바: Clear·Filter·Auto Select, `N/M rows selected`, 메모리(`task_info` 상주 크기)·최근 1초 속도, 켜진 도구 배지 9종(누르면 도구 창, No Caching은 팝오버, Proxy Overridden은 Certificate › 이 Mac, SSL Proxying Off는 설정 SSL 탭). 툴바 No Caching 캡슐 제거. | `4863c80` |
| 6 | 상세 머리(메서드·상태 알약 세로, URL 색), 탭 묶음과 조건부 탭(Form·Cookies·Auth·Set-Cookie·M3U8), Summary·Treeview·JSON 탭(Body는 Pretty·Raw만), `≡`·`⋯` 표 거르기 옵션(대소문자·정규식), HTTPS Response 안내와 `enableSSLProxying(forHostsOfApp:)`. | `ed264cc` |
| 6 수정 | CONNECT 행을 거치면 응답 탭·거르기가 초기화되던 것(상태를 `FlowDetailView`로 올림), 요청 쪽 M3U8 탭 제거, 패널 제목 `Request`/`Response`. | `bdb6501` |
| 8 | 설정 탭 General·Appearance·Tools·SSL Proxying·Bypass·Advanced, General(Content Layout·메뉴 막대 아이콘·Truncation Style·Port·Auto Override·Auto Start Recording·루트 인증서 카드)·Appearance(Font Size·Tab Width·Monospaced·Word Wrap·Show Invisibles·줄무늬·App Theme·Restore Defaults), Core `CertificateAuthority.validity`. | `78e0103` |
| 8 수정 | 인증서 카드는 "로그인 키체인에 설치됨"만(신뢰는 확인하지 않음), Font Size·Tab Width를 읽을 때 범위 고정(틀린 값으로 죽지 않게). | `b3edd51` |
| 9 | Tools(Repeat No-Cache·Request Timeout·cURL `--proxy`·Export 뒤 Finder)·Advanced(Restore 고정·업데이트 알림·24시간·전체 시각·종료 알림·자원 사용량·시뮬레이터 Apple 요청 숨김·Stay On Top·Show Invisible Characters). 모든 cURL 경로를 `AppModel.copyCurl` 하나로. | `97d4a5d` |
| 9 수정 | Stay On Top을 메인 창만이 아니라 Prog 창 전체에(뒤에 열린 Breakpoint 창이 가려지던 것), 공백 `·` 표시는 Header 탭에만(그동안 값 글자 선택 끔, 우클릭 복사는 원래 값). | `81a7488` |
| 10 | README와 이 문서. | 이 커밋 |

## 2. 알아 둘 결정·달라진 점

**기본값이 바뀜(스펙 표를 따름)**
- 목록 줄무늬 켬(예전 끔), URL·Client 말줄임 Tail(예전 Middle), 상세 본문 글꼴 13pt(예전 12.5pt, 표는 원래 13).
- Request Timeout 30초 — Repeat·Compose 모두 예전 60초에서 줄었다.
- 목록 기본 정렬 ID 내림차순(저장 안 함, 다시 켜면 내림차순).

**구현 중 결정**
- Show Update Notification at Launch는 새 키 없이 Sparkle의 `SUEnableAutomaticChecks`에 그대로 묶었다. 새로 설치하면 Sparkle 권한 질문에 답할 때까지 꺼짐(스펙 표는 켬). 켬이 꼭 필요하면 Info.plist에 `SUEnableAutomaticChecks = YES`를 넣는다(권한 질문이 사라지는 정책 변경이라 하지 않음).
- 업데이트 배지는 Sparkle이 유효한 새 버전을 찾았을 때만, 문구는 `New Update ⚠`(스펙의 "N New Updates"가 아님 — Sparkle은 최선의 항목 하나만 준다). Skip This Version 뒤에도 다음 확인까지 남는다.
- 사이드바 숫자는 칩·필터 막대를 반영하지 않는 전체 수(예전·Proxyman과 같다). 걸러진 흐름으로 트리를 만들면 입력 중 도메인이 사라진다.
- 요청 쪽에는 M3U8 탭이 없다(응답이 재생목록일 때만).
- Active 행 Code `-`는 응답이 아직 없을 때만. 헤더를 받은 스트리밍 행은 실제 상태 코드를 보인다. Duration은 모든 Active 행이 `-`.
- 하단 Filter 버튼은 막대가 보이거나 켜진 규칙이 있으면 강조. SSL Proxying Off 배지는 설정 SSL 탭으로(Certificate 창에는 SSL 섹션이 없다). No Caching은 규칙 창이 없어 팝오버.
- 복원된 켜진 규칙이 있으면 막대는 보이되 첫 포커스는 목록.
- Color 키 이름은 Proxyman 그대로 `Color`(Highlight 색 이름과 맞춘다는 도움말).
- 경로 트리는 Pinned·Domains 아래에만 있다(기기·앱 아래 도메인은 경로 트리 없음).
- Port 변경은 예전처럼 "재시작" 버튼(자동 재시작 안 함, 연결을 묻지 않고 끊지 않게).
- 메모리·속도는 1초마다 세션 전체를 훑는다(`ponytail:` 표시 — 고리 버퍼로 바꿀 수 있음). ↑는 요청 시작, ↓는 응답 완료 시점.
- 공백 `·`는 Header 탭만. Query·Form·Cookies 등은 원래 값.

## 3. 수동 점검표(사용자)

자동 확인은 각 구현자가 자기 Debug 빌드(포트 19090, 모달 안 엶, 시스템 프록시·키체인·클립보드 안 건드림)로 했다. 아래는 그래서 확인하지 못한 것이다. 겹치는 항목은 하나로 합쳤다.

**필터 막대·찾기**
- [ ] 상세 ⌘F: 요청을 고르고 Body·Raw·JSON 글자 보기를 클릭한 뒤 ⌘F → 내장 찾기 막대(필터 막대가 아님). Header 표의 이름 열을 클릭하고 ⌘F → 표 거르기 칸.
- [ ] 본문 글자 보기에서 ⌘↑/⌘↓ → 문서 처음·끝으로 이동(필터 규칙 이동이 아님). 목록 포커스에서 ⌘↑/⌘↓·⌘B는 예전 그대로.
- [ ] 도구 창(예: Block List)에서 ⌘N → 그 창 규칙 추가, 메인 필터 막대는 그대로.
- [ ] Color 키: 행을 Highlight Red로 칠하고 규칙 Color · Equal · `red`.

**사이드바**
- [ ] `+` → Add Pinned Domain 시트. `example.com`이나 전체 URL을 넣고 Add → Pinned에 호스트. Cancel·Esc로 닫히고, 빈 칸이면 Add가 꺼짐.
- [ ] 도메인 우클릭: Pin/Unpin이 Pinned를 바꾸고 다시 켜도 남음, Enable SSL Proxying이 SSL Proxying 목록에 넣음, Copy Domain이 호스트를 복사.
- [ ] 트래픽이 있는 고정 도메인을 펼쳐 경로 트리, 경로 노드를 고르면 목록이 걸러짐.
- [ ] 이름을 아는 원격 기기(예: Apple TV)는 IP 대신 이름. 시뮬레이터 앱은 Apps 아래 "<앱> (tvOS 시뮬레이터)".

**하단 바·툴바**
- [ ] Override macOS Proxy를 켜면 주황 Proxy Overridden 배지 → 누르면 Certificate 창 › 이 Mac, 끄면 배지가 사라짐. VPN 쪽에 Prog 프록시가 남은 상태에서도 배지가 보임.
- [ ] 새 버전이 있는 appcast(또는 옛 빌드)로 `New Update ⚠` 배지가 캡슐 오른쪽에 뜨고, 누르면 Sparkle 업데이트 창. 최신이면 배지 없음.
- [ ] 느린 요청: Active 행이 주황 점, Code·Duration `-`.
- [ ] 열 머리로 정렬을 바꾸고 다시 켜면 ID 내림차순.

**상세 패널**
- [ ] 앱이 귀속된 Mac 앱·시뮬레이터 앱의 CONNECT 행 → `Enable only this domain` `or` `Enable all domains from "<앱>"` 두 버튼. 두 번째를 누르면 그 앱의 호스트가 모두 설정 › SSL Proxying에 들어가고 다음 연결부터 복호화. 원격 기기의 CONNECT 행은 첫 버튼만.
- [ ] 라이트 외관에서 URL 색(스킴 회색·호스트 파랑·경로 초록)·메서드·상태 알약, 설정 화면(모든 스크린샷은 다크).

**설정**
- [ ] General ▸ Auto Override System Proxy Settings at Launch 켜고 종료·재실행 → 이 Mac 캡처 켜짐, 시스템 프록시가 `127.0.0.1:<포트>`(VPN이 기본이면 관리자 인증), 종료하면 복원. 메인 창을 닫았다 다시 열어도 다시 적용하지 않음. 복원 알림이 떠 있으면 켜지 않음.
- [ ] General ▸ Generate new… → "모든 Prog 인증서를 초기화할까요?" 알림, 확인하면 카드의 이름·유효기간·설치 여부가 바뀜. Open Certificate…가 Certificate 창 › 이 Mac을 엶.
- [ ] Advanced ▸ Show Alert when quitting the app 켜고 ⌘Q → "Prog를 종료할까요?". 취소하면 앱과 멈춘 Breakpoint가 그대로, 종료하면 캡처 중이었던 프록시를 복원. 캡처 중 두 번째 ⌘Q는 다시 묻지 않음.
- [ ] Tools ▸ Auto open the Export Directory after exporting 켜고 Flow ▸ Export(HAR·CSV·Prog Session) 저장 → Finder에서 파일 선택. 끄면 Finder가 안 열림.
- [ ] Advanced ▸ Hide Unnecessary Apple Requests from iOS Simulators: 부팅한 iOS 시뮬레이터 트래픽에서 `*.apple.com`·`*.icloud.com` 행이 숨고 눈 토글로 보임. 내 앱 요청과 Mac Safari의 apple.com은 그대로.
- [ ] Tools ▸ Add --proxy flag into cURL command 켜고 cURL 복사·붙여 넣기 → 끝에(본문 앞) `--proxy 'http://<LAN IP>:<포트>'`, 툴바 캡슐과 같은 IP·포트.
- [ ] Advanced ▸ Show Update Notification at Launch(`-SUEnableAutomaticChecks NO` 없이 실행): 토글이 Sparkle 상태와 같고, 끄면 다음 실행부터 백그라운드 확인 안 함. `defaults read`의 `SUEnableAutomaticChecks`가 토글을 따라감.
- [ ] Tools ▸ Request Timeout을 1로 두고 느린 주소에 Repeat → 약 1초에 실패. 0이면 제한 없음.
- [ ] Advanced ▸ Stay On Top 켜고 Breakpoint 규칙에 맞는 요청을 보냄 → 열리는 Breakpoint 창이 메인 창 앞.
- [ ] Appearance ▸ Show Invisibles를 Raw 탭과 Word Wrap 끔 상태에서.

## 4. 2단계 메모(이번 범위 밖)

- JSON 탭: 줄 접기, Filter 모드(JSON Path·jq), 미니맵.
- 탭 줄 `+`(Custom Previewer Tab)로 탭 추가.
- 저장한 필터 버튼(Custom Filters), Command Palette.
- Favorites ▸ Saved에 요청 저장.
- Remote devices 아래 기기의 앱별 묶기(별도 조사 메모 있음, 지금은 도메인만).
- 칩 막대 WebSocket·h1·h2 칩(WebSocket 캡처 먼저).
- 필터 키 GraphQL(QueryName).
- 리뷰에서 미룬 것: 경로 트리를 기기·앱 아래 도메인에도, 사이드바 Filter가 경로 노드도 찾기, 본문 규칙의 풀린 본문 캐시와 지운 흐름의 판정 결과 정리, 속도 측정 고리 버퍼, Export가 0.25초 캐시 대신 세션의 최신 흐름을 쓰기, 종료 알림이 로그아웃·시스템 종료를 막지 않게, Font Size를 Treeview·HTML 미리보기에도, `Localizable.xcstrings`의 옛 문자열 정리.

## 5. 머지 메모

- 새 패키지 없음. 새 설정 키는 모두 `eyeproxy.` 접두(`filterRules`·`truncationStyle`·`fontSize` 등). 옛 키(`layout`·`showStatusItem`·`port`·`wrapLongLines`·`appearance`·`pinnedHosts`·`toolSwitches`)는 그대로 읽는다. 세션 파일 형식 변경 없음.
- 설정 창이 480×360에서 560×520으로 커져 처음 열 때 창 크기 자동 저장값이 한 번 바뀐다.
- 메인 체크아웃에 스펙·플랜·목업의 추적 안 된 복사본이 남아 있으면 main에 머지하기 전에 지운다.
- 머지 전 위 점검표 중 HTTPS 안내 두 버튼, Auto Override, 종료 알림, 라이트 외관은 손으로 한 번 보는 것을 권한다.
