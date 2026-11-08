# EyeProxy Tools 1차 묶음 핸드오버 (2026-11-08)

플랜: `2026-11-08-eyeproxy-tools-p2.md` · 스펙: `../specs/2026-11-06-eyeproxy-tools-p2-design.md` · 브랜치: `tools-p2`
상태: Task 1~18(+15b) 구현·리뷰 완료. **아래 2장의 수동 검증은 사용자 실행 대기**(에이전트는 실제 Proxyman 데이터·시스템 프록시·실기기를 건드리지 않는다).
테스트: `swift test --package-path Packages/EyeProxyCore`, `swift test --package-path Packages/EyeProxyKit` 모두 통과. Debug 빌드 컴파일 경고 0.

## 1. 만든 것 (태스크별)

| Task | 내용 |
|---|---|
| 1 | Core: 연결 끊기(`.drop`), 응답 판정(`ResponseDecision`), 흐름 주석(`FlowAnnotation`). 응답 체인은 요청 체인이 마지막으로 바꾼 요청을 받는다. |
| 2 | Core: CONNECT 판정 훅(복호화/터널/끊기/미기록)과 터널 속도 조절(역압 포함). |
| 3 | Kit: `MatchRule` — Wildcard·Regex·Include all subpaths·쿼리 무시·메서드, Proxyman과 같은 `?*` 결과. |
| 4 | Kit: 규칙 트리(폴더)와 Proxyman 노드 JSON 코덱, 깨진 노드는 건너뛰고 셈. |
| 5 | Kit: 도구 스위치(`ToolSwitches`)와 규칙 저장소(`RuleStore`, 도구별 JSON). |
| 6 | Kit: HTTP 메시지 파일 파서(`<FILE_URL=…>`, Content-Length 재계산). |
| 7 | Kit: Map Local(파일·폴더, 없는 파일은 실제 응답). |
| 8 | Kit: Map Remote(빈 칸 유지, 접두 경로 치환, Host 헤더 선택). |
| 9 | Kit: Block List(세 동작, CONNECT 단계 차단)·Allow List(나머지는 미기록 통과). |
| 10 | Kit: No Caching·Network Conditions(프리셋·사용자 프로필, 요청 단위 지연). |
| 11 | Kit: Breakpoint 규칙·대기열·템플릿. |
| 12 | Kit+App: 도구 파이프라인 조립, 규칙 호스트 자동 복호화, 숨김/미기록 반영. |
| 13 | Kit: Proxyman 가져오기(`ProxymanImporter`)와 규칙 번들 내보내기(`RuleBundle`). |
| 14 | App: 공통 도구 창(Enable 체크·규칙 표·폴더·드래그·필터·More), 매칭 필드, Test your Rule, Tools 메뉴. |
| 15 | App: Map Local 편집기 창·HTTP 메시지 편집기·Map Remote 시트. |
| 15b | App: Proxyman과 같은 Flow 목록 열(Edited 포함)과 Add/Edit Comment(사용자 요청 추가 태스크). |
| 16 | App: Breakpoints 창(Header/Query/Body/Raw 편집, Continue Original·Drop Connection·Apply & Execute)·Templates 창, Block/Allow·Network Conditions 시트. |
| 17 | Kit+App: Compose·Repeat·Edit and Repeat, cURL 붙여 넣기 파서, Flow 메뉴. |
| 18 | App: From Proxyman… 확인 시트, 도구 창 More ▸ Import…/Export…(`.eyeproxyrules` 번들), 숨은 0×0 버튼 단축키 수정, README·이 문서. |

컨트롤러 판정(Rulings) 전체 목록은 PR 본문에 있다. 이 문서에는 옮기지 않는다.

## 2. 수동 검증 목록 (사용자 실행)

시작 전: 다른 프록시(Proxyman 등)가 같은 포트를 쓰지 않는지 확인. 확인용 요청은 `curl -x http://127.0.0.1:<포트> …` 또는 기기 트래픽으로 보낸다. 끝나면 만든 규칙을 지우고 도구 스위치를 끈다.

### 2-1. 처음 계획한 E2E

1. **실제 Proxyman 데이터 가져오기** — Proxyman을 종료하고 EyeProxy Tools ▸ Import Settings ▸ From Proxyman… → 시트의 도구별 개수 확인 → [가져오기]. 기대: Map Local 창에 Proxyman과 같은 13개 규칙이 같은 순서·이름·URL로 보이고, 모든 도구의 `Enable … Tool`이 꺼져 있다. 한 번 더 가져오면 "이미 있는 13개 건너뜀". Proxyman 폴더의 파일 수정 시각이 바뀌지 않는다.
2. **Map Local `?*` 규칙** — 가져온 `https://host/path?*` 규칙을 켜고 Map Local 도구를 켠다. 같은 앱 화면을 Proxyman과 EyeProxy에서 각각 띄운다. 기대: 쿼리가 있는 요청에만 적용되고(쿼리 없는 `https://host/path`에는 적용 안 됨) Proxyman과 같은 요청에 Edited 표시가 붙는다.
3. **자동 복호화** — SSL Proxying 목록에 없는 HTTPS 호스트에 Map Local 규칙을 만들고(편집기 URL 칸 아래 "이 호스트는 자동으로 복호화됩니다") 도구를 켠다. 기대: 그 요청이 복호화되어 로컬 응답으로 바뀌고, 상세 요약에 "자동 복호화(규칙: <이름>)".
4. **Apple TV 실기기 Breakpoint** — 기기 앱의 API URL로 Breakpoint 규칙(Request)을 켠다. 기기에서 화면을 연다. 기대: Breakpoints 창이 앞으로 오고(다른 앱이 앞이면 OS가 거부할 수 있음) 헤더를 고쳐 Apply & Execute ⌘↩ 하면 바뀐 요청이 나간다. Continue Original ⌘. / Drop Connection ⌘\도 동작.
5. **Network Conditions 3G 체감** — 기기 앱 호스트에 3G 규칙을 켜고 도구를 켠다. 기대: 이미지·목록 로딩이 눈에 띄게 느려지고, 끄면 원래 속도.
6. **번들 공유** — Map Local 창 More ▸ Export… → `Map Local.eyeproxyrules` 저장 → 다른 Mac(또는 다른 사용자 계정)에서 Map Local 창 More ▸ Import… → 폴더(또는 안의 `rules.config`) 선택. 기대: 규칙과 응답 파일이 그대로 들어오고, 도구는 꺼진 채.

### 2-2. 도구 창 공통

7. **⌘D가 메뉴의 기기 ⌘D를 이김** — 아무 도구 창에서 규칙을 선택하고 ⌘D. 기대: "<이름> 복사본"이 생기고 기기 창은 열리지 않는다. 메인 창에서 ⌘D는 기기 창. (에이전트가 Map Local 창에서 확인함 — 다른 창도 같은 코드.)
8. **⌘N / ⌘↩ / Space** — 도구 창에서 ⌘N → 편집기만 열리고 저장 전에는 규칙이 추가되지 않음. 규칙 선택 후 ⌘↩ → 편집기. Space → 선택 규칙 Enabled 토글.
9. **드래그 순서 변경** — 규칙을 다른 규칙 위로, 폴더 위로 끌어 놓는다. 기대: 규칙 앞/폴더 끝으로 옮겨지고 그 순서로 매칭된다.
10. **우클릭 ▸ Tools ▸ … 미리 채우기** — 목록의 요청을 우클릭 ▸ Tools ▸ Map Local…/Map Remote…/Breakpoint…/Block List…/Allow List…/Network Conditions…. 기대: URL은 쿼리 없이, 메서드는 그 요청 메서드로 채워지고(Map Local은 현재 응답이 메시지로), 저장한 규칙이 그 요청에 맞는다(Test your Rule로 Matched).
11. **No Caching 배지** — Tools ▸ No Caching ⌥⌘N. 기대: 메인 창 툴바에 주황 "No Caching" 배지, 끄면 사라짐.
12. **Allow List 창** — 규칙 하나를 넣고 켠다. 기대: 맞는 요청만 기록되고 나머지는 기록 없이 통과.
13. **설명·도움말** — 각 창의 설명 문구와 `?` 도움말 링크가 Proxyman 문서의 해당 페이지와 같은지(Allow List 설명 포함).

### 2-3. Map Local·Map Remote

14a. **쿼리 "선택한 항목만"** — `curl -x http://127.0.0.1:<포트> "http://<호스트>/info?screenCode=CSSD1400&apiKey=x"`로 요청을 하나 만들고 우클릭 ▸ Tools ▸ Map Local…. 기대: URL은 쿼리 없이, `쿼리: 무시` 아래 표에 `screenCode`·`apiKey`가 체크 해제로 보인다. `screenCode`만 체크 → 모드가 `선택한 항목만`으로 바뀐다. Save 후 Map Local 도구를 켜고 기대: `?screenCode=CSSD1400&apiKey=다른값`·`?apiKey=x&screenCode=CSSD1400`은 로컬 응답, `?screenCode=CSSD0100`·`?apiKey=x`·쿼리 없음은 실제 응답. 규칙 목록 Matching Rule 열 끝에 ` · 쿼리 1개`. URL 칸에 `…/info?a=1&b=*`를 붙여 넣으면 `a`·`b`가 체크된 행으로 표에 옮겨진다.
14. **새 스크린샷 비교** — Map Local 편집기(Advanced Settings 라벨)와 Map Remote 시트(약 669pt 너비)를 Proxyman 화면과 나란히 놓고 배치·문구 확인.

### 2-4. Flow 목록

15. **Add/Edit Comment** — 요청 우클릭 ▸ Add Comment… → 입력·저장 → Comment 열에 표시 → 다시 우클릭하면 Edit Comment….
16. **Request/Response 열** — 영어 단위(bytes/KB/MB)로 잘리지 않고 보이는지 좁은·넓은 창에서 확인.

### 2-5. Breakpoint·Block·Network

17. **⌘. / ⌘\ / ⌘↩** — Breakpoints 창에서 멈춘 요청에 각각 눌러 본다. 기대: Continue Original / Drop Connection(클라이언트 연결 끊김) / Apply & Execute. (에이전트가 ⌘\를 확인함: curl이 빈 응답으로 끝남.)
18. **Body·Raw 탭 편집** — 긴 본문을 입력하는 동안 커서가 끝으로 튀지 않는다.
19. **Templates 창** — ⌘N(Request)·⇧⌘N(Response)로 새 템플릿, 이름·헤더 편집 후 Save ⌘S, Breakpoints 창 Save as Template…로 저장, Reset to the Original로 원래 값 복원. (에이전트가 ⌘N·⇧⌘N·⌘S를 확인함.)
20. **Block App Select App…** — Mac 앱을 고르고 도구를 켠다. 기대: 그 앱의 요청이 막힌다.
21. **Network Conditions Custom Profile** — Custom Profile…에서 값을 넣고 저장 → 프로필 목록에 나타나고 재실행 후에도 남는다.
22. **Network 우클릭 미리 채우기** — 우클릭 ▸ Tools ▸ Network Conditions… → Host가 그 요청 호스트로 채워진다.
23. **Breakpoints 창이 앞으로** — 요청이 멈추면 Breakpoints 창이 앞으로 온다(다른 앱이 앞이면 OS가 포커스를 거부할 수 있음 — 그때는 메인 툴바의 대기 건수 버튼으로 연다).

### 2-6. Compose·Repeat

24. **우클릭 Repeat** — 요청 우클릭 ▸ Repeat. 기대: 같은 요청이 새 행으로 다시 기록.
25. **Repeat No-Cache** — 설정 ▸ 도구 "Repeat 요청에 No-Cache 사용"을 켜고 Repeat. 기대: 업스트림 요청 헤더에 `Cache-Control: no-cache`·`Pragma: no-cache`.
26. **HTTPS Compose** — 복호화되는 호스트로 Compose(⌥⌘C) → SEND. 기대: 복호화된 행으로 기록.
27. **curl 붙여 넣기** — URL 칸에 `curl -X POST … -H … -d …`를 붙여 넣는다. 기대: 메서드·헤더·본문이 각 칸으로 나뉜다.
28. **⌘↩ 충돌 없음** — 메인 창에서 Comment 시트를 연 채 ⌘↩. 기대: Repeat가 실행되지 않는다(시트의 저장만).

## 3. 알려진 제한

- Compose·Repeat로 `https://localhost`·`https://127.0.0.1`에 보내면 EyeProxy를 거치지 않는다(URLSession이 루프백 HTTPS에 프록시를 쓰지 않음). 기록·도구 적용 없음. 루프백 `http://`는 정상.
- Repeat는 URLSession으로 보내므로 Accept-Language·Accept-Encoding이 붙어 원래 요청과 바이트 단위로 같지 않다.
- Network Conditions는 패킷 단위가 아니라 요청 단위(버퍼링 후 지연)로 늦춘다.
- GraphQL QueryName 규칙은 꺼진 채로 가져온다(2차 묶음).
- Proxyman 폴더 노드와 Map Remote·Breakpoint·Block·Allow 규칙의 디스크 JSON 모양은 실제 파일로 확인하기 전까지 추정이다(스펙 §9). 모르는 노드·키는 건너뛰고 개수를 보여 준다.
- Flow 목록 열 배치 저장 키가 `eyeproxy.flowColumns.v2`로 바뀌어 저장된 열 너비가 한 번 초기화된다.
- 앱 전체에 `NSAllowsArbitraryLoads`가 켜져 있다(Compose로 임의의 `http://` 주소에 보내기 위해).
- 열기 패널은 폴더에서 Open을 누르면 고르지 않고 들어가므로, `.eyeproxyrules` 번들은 폴더 안의 `rules.config`를 골라도 된다(번들로 읽음).
- Breakpoint Templates 창의 More ▸ Import…/Export…는 아직 꺼져 있다(템플릿은 규칙 도구가 아님).
- 도구 창의 ⌘↩(편집)·⌘D(복제)와 Templates ⌘N/⇧⌘N은 창 크기의 투명 버튼에 걸려 있다. 창 안 버튼이어야 메뉴의 기기 ⌘D보다 먼저 받으며, 0×0으로 줄이면 동작하지 않는다(실측).
