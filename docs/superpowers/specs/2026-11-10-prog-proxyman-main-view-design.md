# 메인 화면을 Proxyman처럼 — 설계

사용자 요청(2026-11-10, Proxyman 스크린샷 6장과 함께):
> play, pause 버튼 상태가 반대다. 기록 중이면 pause를 띄워 누르면 멈추고, 멈춰 있으면 play를 띄워 누르면 기록. 기본적으로 행을 역순으로 해서 최신 요청이 제일 위에. 검색창도 별도로, 검색할 때 필터도 있어야(안 그러면 너무 오래 걸림). 메인 화면 뷰를 Proxyman과 더 비슷하게 — 사이드바 하이어라키 구조도, 디테일한 기능도 모두 동일하게. 가장 하단 바도 동일하게 — 활성화된 툴 표시, 누르면 그 툴 설정 창.

근거: 사용자가 보낸 Proxyman 스크린샷과 Proxyman 문서(docs.proxyman.com — Content Filter, Multiple Filters, Tab View, Custom Previewer Tab).

## 1. 목표 · 반목표

- 목표: Proxyman을 쓰던 손이 Prog에서 그대로 움직이게. 화면 배치·이름·단축키·동작을 Proxyman에 맞춘다.
- 목표: 요청이 수천 개여도 검색이 끊기지 않게(검색 대상 키를 고르고, 무거운 비교는 화면 밖에서).
- 반목표: 이미 쓰는 기능(Highlight·Delete·Auto Select·Export·⌘F 상세 찾기·M3U8 등)이 깨지는 것. Proxyman에 없는 Prog 기능(인증서 창, 시뮬레이터 CA 설치 등)을 없애는 것.
- 비목표(이번 묶음 밖, 2단계): JSON 탭의 JSON Path·jq·미니맵, Custom Previewer Tab의 `+`로 탭 추가, 저장한 필터 버튼(Custom Filters), Command Palette, Favorites ▸ Saved에 요청 저장, WebSocket·h1·h2 칩.

## 2. 기록 버튼(버그)

- 기록 중 → `pause.fill`(누르면 멈춤), 멈춤 → `play.fill`(누르면 기록). 상태가 아니라 **누르면 할 일**을 보여 준다(Proxyman과 같음). 툴팁도 그대로 "기록 일시정지 (⌘R)" / "기록 다시 시작 (⌘R)".

## 3. 목록

- 기본 정렬: ID **내림차순**(최신이 맨 위). 열 머리를 누르면 지금처럼 바뀌고, 앱을 다시 켜면 내림차순.
- Auto Select는 정렬과 무관하게 최신을 고르고 스크롤(이미 그렇다) — 최신이 맨 위라 스크롤이 거의 필요 없다.

## 4. 필터 막대(검색창) — Proxyman Secondary/Multiple Filters

툴바의 검색칸(`.searchable`)을 없애고, 칩 막대 아래에 Proxyman과 같은 필터 막대를 둔다.

- 한 줄 = 규칙 하나: `[켜짐 체크박스] [키 ▾] [매칭 ▾] [검색어]` + 오른쪽 `−` `+`, 막대 끝 아래 줄에 단축키 안내 `Show ⌘F · New ⌘N · Remove ⇧⌘N · Up ⌘↑ · Down ⌘↓ · On/Off ⌘B · Hide ESC`.
- 키: URL, Host, Query String, Request Header, Response Header, Request Body, Response Body, Method, Status Code, Client, IP Address, Comment, Color(Highlight), Duration (ms), Request Body Size (KB), Response Body Size (KB). (GraphQL은 이번 범위 밖.) 기본 키 URL.
- 매칭: Contains, Not Contains, Start With, End With, Equal, Not Equal, `<`, `>=`(숫자 키만), Match Wildcard, Not Match Wildcard, Match Regex, Not Match Regex. 기본 Contains. 대소문자 무시.
- 규칙 여러 개(최대 10)는 **AND**(Proxyman 기본). AND/OR 전환은 막대 오른쪽 작은 토글(빌더 판단; 없으면 AND만).
- 막대 표시/숨김: ⌘F(목록 쪽 포커스에서 — 상세 패널 포커스면 지금의 상세 찾기), 하단 바 Filter 버튼, Esc로 숨김. 숨겨도 켜진 규칙은 계속 적용되고 하단 바 Filter 버튼이 강조로 알린다.
- 마지막 필터 설정은 앱을 다시 켜도 남는다(Proxyman "remembers your last filter settings").
- 성능: 검색어 입력은 짧게 디바운스(약 150 ms). 본문 키(Request/Response Body)가 들어간 규칙은 메인 밖에서 계산해 결과만 반영. URL·Host 같은 가벼운 키는 지금처럼 즉시.
- 지금 검색칸이 하던 "URL·메서드·상태 검색"은 키 URL + Contains로 대신한다(메서드·상태는 각 키로).

## 5. 사이드바 — Proxyman 하이어라키

```
Favorites
  Pinned            ← 고정한 도메인·앱
    gw.example.com
    ...
Remote devices      ← 원격 기기(이 Mac 아님)
  192.168.0.20 (Apple TV)   ← 기기 이름(아는 경우)
    vod.example-cdn.net     ← 그 기기의 도메인
    api.example.com
All
  Apps              ← 이 Mac의 앱(프로세스)별
    Safari ▸ 도메인들
  Domains           ← 모든 도메인
    api.example.com ▸ 경로 트리(/v3 ▸ /media ▸ …)
```

- 각 줄 오른쪽에 개수. 도메인 줄은 펼치면 경로 트리(Proxyman과 같음); 경로 노드를 고르면 그 경로로 시작하는 요청만.
- 맨 아래 사이드바 필터 칸 `Filter (⌘⇧F)`: 사이드바 항목 이름으로 거른다. 왼쪽 `+`는 Pinned에 도메인 추가(입력 시트 — 모달이므로 수동 점검표).
- 우클릭: Pin/Unpin, Enable SSL Proxying, Copy Domain(지금 있는 것 유지·이름 통일).
- 지금의 "전체" 줄은 All 섹션 머리를 눌러 대신한다(빌더 판단: 섹션 머리 선택이 어려우면 All 아래 첫 줄 "All Requests").
- Favorites ▸ Saved는 이번엔 넣지 않는다(비목표).

## 6. 하단 바 — Proxyman 상태 막대

창 맨 아래 한 줄.
- 왼쪽 버튼: **Clear**(세션 지우기 ⌘K와 같음), **Filter**(필터 막대 보이기·숨기기, 규칙이 켜져 있으면 강조), **Auto Select**(토글, 켜면 강조).
- 가운데: `선택 수/보이는 행 수 rows selected` (예: `1/106 rows selected`).
- 오른쪽:
  - 메모리·속도: `181 MB · ↑122 KB/s ↓20 KB/s` — 앱 메모리(상주 크기)와 최근 1초 업·다운로드 바이트(요청·응답 본문 크기 합으로 근사; 터널은 알 수 있는 만큼).
  - **켜진 도구 배지**: Breakpoint, Map Local, Map Remote, Block List, Allow List, Network Conditions, No Caching, 그리고 Proxy Overridden(이 Mac 캡처 켜짐), SSL Proxying 꺼짐 같은 상태. 켜진 것만 보이고, 누르면 그 도구 창(Proxy Overridden은 Certificate 창의 이 Mac 섹션)을 연다.

## 7. 상세 패널

- 머리(지금 FlowHeaderBar): 왼쪽에 메서드 알약 위·상태 알약 아래(상태는 `206 Partial Content`처럼 코드+사유), 오른쪽에 전체 URL을 여러 줄 모노 글꼴로(호스트 강조). 복사·cURL 버튼은 유지.
- 탭(요청): `Header · Query · Body · (Form) · (Cookies) · (Auth) · Raw │ Summary · Treeview · M3U8 · JSON`. 괄호는 해당 내용이 있을 때만(Proxyman처럼).
- 탭(응답): `Header · Body · (Set-Cookie) · Raw │ Treeview · M3U8 · JSON`.
  - Summary: 지금의 접는 "요약"을 탭으로 옮긴다.
  - Treeview: 지금 Body 안의 Tree 모드를 탭으로(Body는 Pretty·Raw만).
  - JSON: 본문을 JSON으로 예쁘게 보여 주는 탭(Content-Type이 json이 아니어도 시도). 이번엔 지금의 Pretty 보기 + ⌘F 찾기. 줄 접기·Filter 모드(JSON Path·jq)·미니맵은 2단계.
  - M3U8: 지금처럼 재생목록일 때만.
  - `+`(탭 추가)는 2단계.
- 탭 이름은 Proxyman과 같은 영어(Header, Body…). 표는 머리 줄 `Key | Value`.
- 마지막으로 고른 탭은 흐름을 바꿔도 유지(이미 그렇다), 없는 탭이면 Header.

## 8. 글자

- 구조 이름(사이드바 섹션·탭·하단 버튼·필터 키·매칭)은 Proxyman과 같은 영어. 툴팁·빈 화면·오류 문구는 지금처럼 한국어 한 줄.

## 9. 그 밖에 지켜야 할 것

- 이미 있는 단축키(⌘R 기록, ⌘K 세션 지우기, ⌫, ⌘1~6, ⇧⌘X, ⌘0, ⌘↩ Repeat, ⌘F 상세 찾기 라우팅)는 그대로. 새 단축키(⌘N·⇧⌘N·⌘↑·⌘↓·⌘B·⌘⇧F)는 필터 막대·사이드바 필터에 포커스가 있을 때만 — 다른 곳의 ⌘N(새 창 등)·⌘B와 겹치지 않게 범위를 좁힌다.
- 사이드바 구조를 바꾸면 기존 고정(pinnedHosts) 설정을 그대로 읽는다.
- 기기 앱별 묶기(별도 조사, `EyeProxy-evidence/research/device-app-grouping.md`)는 이번 범위 밖 — Remote devices 아래는 도메인만.

## 10. 스크린샷에서 더 보인 메인 화면 세부 (사용자 참고 캡처 15장)

참고: 캡처 정리 문서는 공개 레포 밖 로컬 보관 폴더 `EyeProxy-evidence/proxyman-ref/catalog.md`(개인 정보는 자리표시자로 바꿈).

- **툴바 상태 캡슐**: `● Prog | Listening on <IP>:<port>`, 기록을 멈추면 끝에 ` | Pause`. 새 버전이 있으면 오른쪽에 `N New Updates ⚠` 배지(누르면 Sparkle 업데이트 확인). 지금의 "실행 중 · 포트 …" 캡슐을 이 문구로 바꾼다.
- **암호화된 HTTPS 응답 안내**: 복호화하지 않은 터널(CONNECT 행)을 고르면 응답 패널에 자물쇠와 `HTTPS Response` 안내, 버튼 `Enable only this domain` / `or` / `Enable all domains from "<앱>"`(그 앱이 연 모든 도메인을 SSL Proxying 목록에 넣음; 앱을 모르면 첫 버튼만). 눌러 켜면 v1.1.1의 터널 재판정으로 바로 다시 연결된다.
- **상세 URL 색**: 스킴 회색, 호스트 파랑, 경로·쿼리 초록. URL이 길면 메서드·상태 알약을 URL 왼쪽에 세로로 쌓는다.
- **패널 필터 옵션**: 헤더·쿼리·쿠키 표 거르기(⌘F)에 `⋯` 메뉴 — `Case Sensitive / Case Insensitive`, `Text / Regular Expression`. 패널 탭 줄 오른쪽 `≡` 버튼으로도 연다.
- **목록**: 상태 점 초록 = Completed, 주황 = Active(진행 중), 빨강 = Failed. Active 행은 Code·Duration이 `-`. Client 열은 앱·기기 아이콘 + 이름.
- **사이드바**: 원격 기기가 없으면 `Remote devices` 섹션 자체를 숨긴다. Apps 아래 Mac 앱도 펼쳐 도메인을 본다.
- **헤더 값의 공백 표시**: 설정 `Show Invisible Characters`가 켜져 있으면 값의 공백을 `·`로(§11 Advanced).

## 11. 설정 창 — Proxyman 구성

지금 Prog 설정 탭: 일반 · SSL Proxying · Bypass · 도구. Proxyman 탭: General · Appearance · Privacy · Tools · GitHub · Platform · Advanced. Prog는 **General · Appearance · Tools · SSL Proxying · Bypass · Advanced**로 맞춘다(Privacy·GitHub·Platform은 Prog에 해당 기능이 없어 뺀다; SSL Proxying·Bypass는 Prog 기능이라 유지).

| 탭 | 항목(Proxyman 이름 그대로) | 종류·기본 | Prog 동작 |
|---|---|---|---|
| General | Content Layout | Vertical / Horizontal, Vertical | 지금 레이아웃 전환과 같은 설정 |
| General | Show Prog Icon on Menu Bar | ☑ | 지금 "상태 막대에 아이콘 표시" |
| General | Truncation Style | Head / Middle / Tail, Tail | 목록 URL·Client 열 말줄임 위치 |
| General | Port Number | 9090 | 지금 포트(바꾸면 서버 재시작) |
| General | Auto Override System Proxy Settings at Launch | ☐ | 켜면 실행 시 "이 Mac 캡처"를 켠다 |
| General | Auto Start Recording Traffic at Launch | ☑ | 끄면 실행 시 기록 멈춤으로 시작 |
| General | 루트 인증서 카드 | 정보 + 버튼 | CA 이름·유효기간·이 Mac 설치/신뢰 상태, `Open Certificate…`(Certificate 창), `Generate new…`(지금 CA 초기화) |
| Appearance | Font Size | 11~16, 13 | 상세 패널 본문·표 글꼴 크기 |
| Appearance | Tab Width | 2 / 4 Spaces, 2 | JSON Pretty·JSON 탭 들여쓰기 |
| Appearance | Use Monospaced Font | ☐ | 목록 표를 고정폭 글꼴로 |
| Appearance | Word Wrap | ☑ | 지금 본문 "줄바꿈"(같은 설정) |
| Appearance | Show Invisibles | ☐ | 본문 텍스트의 공백·탭·줄바꿈 표시 |
| Appearance | Alternative Rows Background Colors | ☑ | 목록 줄무늬 |
| Appearance | App Theme | System / Light / Dark | 지금 "외관" |
| Appearance | Restore Defaults | 버튼 | Appearance 값 기본으로 |
| Tools | Use No-Caching on Repeated Requests | ☐ | 지금 "Repeat 요청에 No-Cache" |
| Tools | Request Timeout | 30 seconds, 0 = 없음 | Compose·Repeat 타임아웃 |
| Tools | Add --proxy flag into cURL command | ☐ | cURL 복사에 `--proxy http://<IP>:<port>` 붙이기 |
| Tools | Auto open the Export Directory after exporting | ☐ | Export 뒤 Finder에서 보여 주기 |
| Advanced | Restore to previous HTTP/HTTPS Proxy when Prog is closed | ☑(고정) | Prog는 늘 복원한다 — 켜진 채 비활성으로 보여 주고 툴팁으로 설명 |
| Advanced | Show Update Notification at Launch | ☑ | Sparkle 자동 확인 |
| Advanced | Use 24-Hour Time | ☑ | 목록 Time 열 |
| Advanced | Display Full Time Format | ☐ | Time 열에 날짜·시간대까지 |
| Advanced | Show Alert when quitting the app | ☐ | 종료 확인 알림 |
| Advanced | Show Resource Usage in Bottom Bar | ☑ | 하단 바 메모리·속도(§6) |
| Advanced | Hide Unnecessary Apple Requests from iOS Simulators | ☐ | 시뮬레이터의 `*.apple.com`·`*.icloud.com` 요청을 숨김 표시(Block List 숨김과 같은 처리, 눈 토글로 보기) |
| Advanced | Stay On Top | ☐ | 메인 창 항상 위 |
| Advanced | Show Invisible Characters | ☐ | 헤더 값 공백을 `·`로(§10) |

- 기본값은 Prog의 지금 동작을 바꾸지 않는 쪽으로 정했다(예: Auto Override는 ☐ — 지금 Prog가 실행 시 시스템 프록시를 건드리지 않으므로). Proxyman 기본과 다른 항목은 위 표의 값이 기준.
- 이번에 넣지 않는 Proxyman 항목: Use HTTP/2, Advanced Proxy Setting(Bypass 탭이 대신), Show Minimap, Scroll Beyond The Last Line, Dock Icon, Append Proxyman Headers, Copy Library(cURL만), Preserve Original Request, Map Local Path/Delay, Scripting 두 항목, App Language, Auto Clean Up Resources, Privacy·GitHub·Platform 탭, Custom Previewer Tab 창(2단계).

## 12. 빌더 판단에 맡김

- 필터 막대·하단 바의 정확한 여백·글꼴 크기, AND/OR 토글 모양, 메모리 측정 방법(`task_info` 상주 크기 등), 사이드바 경로 트리의 깊이 상한.
