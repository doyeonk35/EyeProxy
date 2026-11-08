# EyeProxy Tools 1차 묶음 (P2 조작 도구) 설계

- 날짜: 2026-11-06
- 상위 설계: `docs/superpowers/specs/2026-11-05-eyeproxy-design.md` (이 문서와 충돌하면 이 문서가 우선한다. 상위 문서의 Global 규칙 — macOS 15+, Swift 6, 외부 패키지 허용 목록, 모듈 의존 방향 — 은 그대로 적용)
- 표기: **[사용자]** = 사용자가 정한 것, **[내 판단]** = 설계자가 정한 것(사용자가 뒤집을 수 있음), **[빌더]** = 구현자가 정해도 되는 것

## 1. 의도

사용자는 Proxyman의 Tools 메뉴를 전부 쓰고 있고, EyeProxy가 Proxyman을 대체하려면 **Proxyman의 Tools 기능이 모두 같은 동작으로** 있어야 한다. **[사용자]** UI·UX도 Proxyman과 비슷하게 유지해 손에 익은 흐름을 그대로 쓸 수 있어야 한다. **[사용자]** 기존 Proxyman 규칙은 고치지 않고 그대로 가져와 동작해야 한다. **[사용자, 상위 설계 §4.1]**

Tools 전체는 너무 커서 세 묶음으로 나눈다. **[내 판단]**

| 묶음 | 내용 |
|---|---|
| **1차 (이 문서)** | 규칙 엔진 + Breakpoint, Map Local, Map Remote, Block List, Allow List, No Caching, Network Conditions, Compose, Repeat, Edit and Repeat, Proxyman에서 규칙 가져오기 |
| 2차 | Scripting(Proxyman 스크립트 API 호환), 스크립트 가져오기, Diff, DNS Spoofing, Reverse Proxy, External Proxy, Access Control, GraphQL QueryName 매칭 |
| 3차 | SOCKS Proxy, Custom/Client Certificates, TLS Key Logging, Protobuf, Charles 설정 가져오기 |

1차의 규칙 엔진은 2·3차 도구도 그대로 쓰게 만든다.

## 2. 목표 / 비목표 / 반목표

**목표**
1. 위 1차 도구가 Proxyman 문서·실측과 같은 동작을 한다.
2. 사용자 Mac에 있는 Proxyman 규칙(Map Local·Map Remote·Breakpoint·Network Conditions)을 한 번에 가져오면 같은 요청에 같은 결과가 나온다.
3. Map Local·Map Remote에 **쿼리 처리 선택**(무시 / 선택한 항목만 / 전체 일치)을 더한다(Proxyman에 없는 EyeProxy 전용 기능, §4.2). **[사용자]**
4. 도구 창·편집기·메뉴·단축키 배치가 Proxyman과 거의 같다.

**비목표**
- Scripting·GraphQL QueryName 매칭(2차). 규칙 모델에는 `graphQLQueryName` 필드를 두되 1차에서는 무시하고, 값이 있는 규칙은 가져올 때 "2차에서 지원" 표시와 함께 비활성으로 들인다. **[내 판단]**
- WebSocket·HTTP/2 대상 조작(상위 설계상 P2·P3 캡처 기능이 먼저 필요).
- Proxyman 파일과의 **양방향** 동기화. 가져오기는 한 방향 복사다.

**반목표 (기술적으로 동작해도 실패로 본다)**
- 가져오기 때문에 사용자 트래픽이 갑자기 바뀌는 것. 가져온 도구는 **모두 꺼진 상태**로 들어온다. **[내 판단]** (실측에서 Proxyman은 규칙 추가 시 도구를 자동으로 켰다 — EyeProxy는 그러지 않는다.)
- Proxyman 데이터 폴더에 쓰기. 가져오기는 읽기 전용이다.
- Breakpoint로 멈춘 요청이 사용자 모르게 무한정 쌓이는 것(§5.1 표시 규칙).

## 3. 실측으로 확인한 Proxyman 사실 (근거)

사용자 Mac의 Proxyman 6.3.0을 직접 열어 확인했다(사내 URL이 섞여 있어 원본 스크린샷·노트는 레포에 넣지 않는다).

- 규칙 저장: `~/Library/Application Support/com.proxyman.NSProxy/user-data/`의 `MapLocalFiles-RuleTree`, `MapRemoteService-RuleTree`, `BreakpointFiles-RuleTree`, `ScriptService-RuleTree`(JSON, 최상위 `{"nodes":[…]}`), `NetworkThrottlingService`(JSON 배열).
- Map Local 응답 파일: `…/com.proxyman.NSProxy/map-local/<host>_<ruleID>.json` — **JSON이 아니라 원문 HTTP 메시지**(상태줄, 헤더, 빈 줄, 본문). 규칙의 `localFile.path`는 이 폴더 밖(예: 다운로드 폴더)을 가리킬 수도 있다.
- 도구 on/off: `defaults`(`com.proxyman.NSProxy`)의 키. 도구마다 이름이 다르다: `MapLocalFiles-RuleTree-IsFeatureEnabled`, `BreakpointFiles-RuleTree-IsFeatureEnabled`, `ScriptService-RuleTree-IsFeatureEnabled`, `NetworkThrottlingService-IsFeatureEnabled-v1`, 그리고 Map Remote는 실제로 `MapRemoteService-IsFeatureEnabled-v1`이 화면 상태와 일치했다(`…-RuleTree-IsFeatureEnabled`도 있으나 쓰이지 않음). EyeProxy는 이 값을 가져오지 않으므로(§5.9) 참고만 한다.
- **내보내기 파일**(도구 창 More ▸ Export Settings…): 확장자 `.config`, 기본 이름 `proxyman_map_local_tree_rules`. 내용은 디스크 형식과 **같은 노드 JSON이지만 최상위가 `{"nodes":[…]}`가 아니라 노드 배열 `[…]`**이다. **선택한 규칙만** 내보낸다. **Map Local 응답 본문은 들어 있지 않고 `localFile.path`(절대 경로)만** 있다 — 다른 사람 Mac에서 내보낸 파일을 가져오면 응답 파일 경로가 깨진다.
- 실측 중 관찰: 도구 창에서 ⌘N을 누르면 Proxyman은 빈 규칙을 **즉시 저장**하고 **그 도구를 켠다**(Map Local·Map Remote 모두). 확인 후 원상 복구했다.
- 사용자 Proxyman에는 Regex 규칙이 없다(13개 모두 `useWildcard`).
- 사용자 실사용: Map Local 규칙 대부분이 URL 끝에 `?*`를 손으로 붙여 쿼리를 무시하고, 일부는 쿼리 전체를 넣어 정확히 맞춘다. 즉 **Proxyman 와일드카드는 쿼리까지 포함한 전체 URL과 비교**한다.
- Map Local 규칙 JSON 한 개(모든 키):

```json
{"nodeType":{"node":{"_0":{
  "id":"19A8BA07","name":"…","isEnabled":true,
  "url":"https://host/path?*","regex":"useWildcard",
  "method":{"exact":[{"name":"GET"}]},
  "isIncludingPaths":false,"graphQLQueryName":null,
  "isLocalFileEnable":true,"localFile":{"name":"default_message","path":"/abs/path.json"},
  "isDirectoryFileEnable":false,"directoryFile":null,
  "advanceSettings":{"delayTimePreset":10}}}}}
```
`method`는 `{"any":{}}` 또는 `{"exact":[{"name":"GET"},…]}`. `advanceSettings`는 지연이 없으면 비거나 키가 없다.

- Network Conditions 규칙 한 개:

```json
{"id":"UUID","name":"…","url":"img.example.com","isEnabled":true,"isSystemWide":false,
 "networkProfile":{"name":"Very Bad Network","profileType":1,
   "downloadBandwidth":125000,"uploadBandwidth":125000,
   "downloadBandwidthTitle":"<1 mbps","uploadBandwidthTitle":"<1 mbps",
   "delay":1400,"minimumWaitTime":500000,"packageDrop":10,"isAllLostConnection":false}}
```

- **확인하지 못한 것**: 폴더 노드의 JSON 모양(사용자 데이터에 폴더 없음), Map Remote·Breakpoint 규칙 JSON(사용자 데이터가 비어 있음), `regex`의 정규식 값 이름, `delayTimePreset` 숫자의 단위. §9 참고.

## 4. 공통: 규칙 엔진

### 4.1 규칙 모델

모든 URL 규칙 도구(Breakpoint, Map Local, Map Remote, Block, Allow, 2차의 Scripting 등)는 공통 매칭 부분을 공유한다.

```
MatchRule
  url: String                     // 패턴
  mode: wildcard | regex
  methods: any | exact([String])
  includeSubpaths: Bool           // "Include all subpaths of this URL"
  queryMode: ignore | selected | exact   // EyeProxy 전용. 새 규칙 기본 ignore, 가져온 규칙 exact [사용자]
  queryConditions: [QueryCondition]      // selected용. QueryCondition { key, value, isEnabled } [사용자]
  graphQLQueryName: String?       // 1차 미사용
```

규칙은 트리로 저장한다(폴더 = 이름과 on/off가 있는 자식 목록). 평가 순서는 트리를 위에서 아래로 깊이 우선 펼친 순서다. 꺼진 폴더 안의 규칙은 건너뛴다.

### 4.2 매칭 규칙 (Proxyman과 동일 + 쿼리 옵션)

- 비교 대상 문자열은 요청의 전체 URL `scheme://host[:port]/path[?query]`. 기본 포트(80/443)는 생략한 형태로 만든다. **[내 판단]**
- **Wildcard**: `*` = 0자 이상, `?` = 정확히 1자(Proxyman 문서 그대로 — 쿼리 구분자로 특별 취급하지 않는다). 전체 문자열에 매칭(부분 일치 불가). 패턴에 `scheme://`이 없으면 scheme은 아무거나 허용한다(`api.example.com/v1/*`). 패턴이 host만이면 그 host 전체.
  - 따라서 사용자의 `https://host/path?*`는 쿼리가 있는 `https://host/path?a=1`에는 맞고(`?`가 리터럴 `?` 한 글자에 대응), 쿼리가 없는 `https://host/path`에는 맞지 않는다. Proxyman과 같은 결과다. 테스트에 이 두 경우를 넣는다.
- **Regex**: `NSRegularExpression`, 전체 URL과 완전 일치해야 한다(부분 일치는 불일치).
- **Include all subpaths**: 켜면 패턴 뒤에 `/*`가 붙은 것처럼 하위 경로도 맞는다(패턴이 이미 `*`로 끝나면 변화 없음).
- **쿼리 처리(queryMode)** **[사용자]** — 세 가지:
  - **무시(`ignore`)**: 매칭 전에 **요청 URL에서만** 첫 `?`부터 끝까지(쿼리)를 떼고 비교한다. **패턴은 건드리지 않는다**(`/v?/users`의 `?`는 계속 한 글자 와일드카드). 그래서 패턴 `https://host/path`가 `https://host/path?a=1`, `https://host/path?b=2`, `https://host/path`에 모두 맞는다 — 사용자가 손으로 붙이던 `?*`를 대신한다. Wildcard·Regex 모두 같은 방식. 새 규칙 기본값. **[내 판단]**
  - **선택한 항목만(`selected`)** **[사용자]**: 경로는 무시처럼 쿼리 없이 비교하고, 추가로 **체크된** 쿼리 조건마다 요청 쿼리에 그 키가 있고 값이 맞아야 일치한다. 체크 안 된 조건과 표에 없는 요청 파라미터는 비교에서 빠진다(있든 없든 상관없음).
    - 키: 정확히(대소문자 구분). 같은 키가 여러 번 나오면 하나라도 맞으면 일치. 키가 빈 조건은 무시.
    - 값: `*`(0자 이상)·`?`(1자) 와일드카드, 그 외 리터럴, 대소문자 구분. 값이 `*`면 키가 있기만 하면 된다.
    - 요청 쪽 키·값은 퍼센트 디코딩 후 비교(`+`는 공백으로 보지 않음 — URLComponents.queryItems 기준). 조건은 사용자가 입력한 그대로.
    - 체크된 조건이 0개면 무시와 같다.
  - **전체 일치(`exact`)**: Proxyman과 같다(쿼리 포함 전체 URL 비교). Proxyman에서 가져온 규칙은 이 값으로 들인다(그래야 `?*`나 쿼리 전체를 넣은 기존 규칙이 Proxyman과 똑같이 동작). **[사용자 결정의 귀결]**
  - 무시·선택한 항목만인데 패턴에 쿼리처럼 보이는 부분(`?` 뒤에 `=`나 `*`가 오는 형태)이 있으면 편집기에 "패턴의 쿼리 부분과는 비교하지 않습니다" 안내를 띄운다(저장은 막지 않음). **[내 판단]**
  - 편집기: "Include all subpaths" 바로 아래 `쿼리: [무시 | 선택한 항목만 | 전체 일치]`(segmented). 선택한 항목만이면 아래에 Proxyman Edit & Repeat의 Query 탭 같은 표(☑ · Key · Value, 마지막 "New Key… / New Value…" 입력 행은 입력하면 체크된 새 행, 선택 행 − 삭제, 값 placeholder `값 또는 *`)와 회색 안내 "체크한 항목만 비교합니다. 값을 *로 두면 키만 있으면 됩니다."를 둔다. **[사용자]**
  - URL 칸에 `k=v(&k=v)*` 꼴 쿼리가 든 URL을 붙여 넣거나 입력을 마치면 쿼리를 체크된 조건으로 표에 옮기고 선택한 항목만으로 바꾼다(전체 일치면 그대로). `?` 뒤가 그 꼴이 아니면(`/v?/users`, `?*`) 건드리지 않는다. **[사용자]**
  - 우클릭 ▸ Tools 미리 채우기: URL은 쿼리 없이, 모드는 무시, 요청의 쿼리 항목은 **체크 해제**로 표에 넣는다. 하나라도 체크하면 선택한 항목만으로 바뀐다. **[사용자]**
  - 도구 창 Matching Rule 열: `Wildcard: <url>` 뒤에 선택한 항목만이면 ` · 쿼리 n개`, 전체 일치면 ` · 쿼리 전체 일치`. **[사용자]**
- **Method**: `ANY` 또는 하나 이상의 메서드. 대소문자 무시.
- **Test your Rule**: 모든 편집기에 링크. 패턴과 샘플 URL 여러 줄을 넣으면 줄마다 Matched / Not Matched. 현재 세션의 선택된 요청 URL을 샘플 첫 줄로 미리 채운다. **[내 판단]**

매칭 엔진은 Kit에 둔다(UI 없음, 순수 함수). 패턴은 규칙이 바뀔 때만 컴파일해 캐시한다. **[빌더]** 방법은 자유.

### 4.3 도구별 on/off

각 도구 창 맨 위 `☐ Enable <Tool> Tool` 체크박스가 그 도구 전체의 스위치다. 규칙마다 Enabled 체크도 있다. 도구가 꺼져 있으면 규칙은 평가하지 않는다. 메뉴 **Tools ▸ Enable/Disable Tools ▸** 에 같은 스위치가 체크 메뉴로 있다. 상태는 `AppSettings`에 저장한다.

### 4.4 규칙 호스트 자동 복호화 [사용자]

Proxyman은 SSL Proxying 목록에 없는 HTTPS 호스트에 걸린 규칙을 조용히 무시한다. EyeProxy는 **켜진 도구의 켜진 규칙이 가리키는 호스트를 SSL Proxying 목록에 없어도 자동으로 복호화**한다.

- CONNECT 단계의 복호화 판정 = `SSL Proxying 목록에 있음` **또는** `자동 복호화 호스트 집합에 있음`. 자동 집합은 규칙이 바뀌거나 도구 스위치가 바뀔 때 다시 계산해 Core에 넘긴다(기존 `update(sslPolicy:)`와 같은 방식).
- 대상 도구: Breakpoint, Map Local, Map Remote, Block List(경로까지 있는 규칙), Allow List(경로까지 있는 규칙). Network Conditions·No Caching은 호스트만 알면 되므로 대상이 아니다(No Caching은 §5.6대로 복호화되는 요청에만 적용).
- 호스트 뽑기: Wildcard 패턴의 host 부분을 그대로 호스트 패턴으로 쓴다(`*.example.com`, `api?.example.com` 가능, 포트는 무시). scheme이 `http://`인 패턴은 제외. **Regex 규칙과 host 부분에 와일드카드만 있는 규칙(`*`)은 자동 대상에서 뺀다** — 모든 HTTPS를 복호화하게 되므로. 이런 규칙은 편집기와 규칙 표에 "SSL Proxying 목록에 호스트를 추가해야 동작합니다 [목록에 추가]" 경고를 띄운다. **[내 판단]**
- 편집기에서 규칙의 호스트가 자동 대상이면 URL 칸 아래에 회색으로 "이 호스트는 자동으로 복호화됩니다"를 표시한다.
- 상세 화면 요약에 자동 복호화로 잡힌 요청은 "자동 복호화(규칙: <이름>)"로 표시해 왜 복호화됐는지 알 수 있게 한다.
- Block List: 경로 없이 host만인 규칙은 CONNECT 단계에서 바로 끊는다(복호화 불필요). 경로가 있는 규칙은 자동 복호화 후 요청 단위로 판정한다.
- Allow List: 켜져 있을 때 host가 어떤 Allow 규칙의 호스트 패턴에도 안 맞으면 CONNECT 단계에서 복호화 없이 터널·미기록으로 통과시킨다. 맞으면(경로 조건이 있으면 자동 복호화 후) 요청 단위로 판정한다.
- 인증서 미신뢰 기기에서는 자동 복호화가 TLS 실패를 낳을 수 있다. 이 경우는 기존 연결 로그·TLS 실패 표시 그대로 보인다(새 처리 없음).

### 4.5 처리 순서 [내 판단]

Proxyman 문서에 도구 간 우선순위가 없어서 아래 순서로 정한다. 같은 도구 안에서는 **첫 일치 규칙 하나만** 적용한다(Proxyman 창 안내 "Each request is checked against the rules from top to bottom, stopping when a match is found." 그대로).

요청 쪽:
1. **Allow List** — 켜져 있고 어떤 규칙에도 안 맞으면: 기록하지 않고 통과(HTTPS는 복호화 없이 터널, HTTP는 그냥 전달).
2. **Block List** — 맞으면 액션대로(§5.4). 막힌 요청은 이후 단계로 가지 않는다.
3. **No Caching**(요청 헤더 정리).
4. **Map Remote** — 목적지 교체.
5. **Map Local** — 맞으면 업스트림에 가지 않고 로컬 응답을 만든다(응답 쪽 3·4 단계는 거친다).
6. **Breakpoint(요청)** — 멈춤·편집.
7. 업스트림 전송(Network Conditions 적용).

응답 쪽:
1. **No Caching**(응답 헤더 정리).
2. **Breakpoint(응답)** — Map Local 응답도 멈출 수 있다(Proxyman 2.16+ 조합과 동일).
3. Network Conditions의 다운로드 지연.
4. 기록·표시.

Map Local과 Breakpoint 조합, Repeat 요청에도 모든 도구가 적용된다(Proxyman 문서와 동일). Map Remote 다음 단계(Map Local, Breakpoint)는 **바뀐 URL**로 매칭한다. **[내 판단]**

## 5. 도구별 동작

### 5.1 Breakpoint

- 규칙 = MatchRule + `☐ Request` `☐ Response`(둘 다 가능). 표 열: Name · Method · Matching Rule · Request · Response.
- 맞으면 해당 단계에서 요청/응답을 **멈추고** Breakpoint 창을 띄운다(이미 열려 있으면 목록에 추가). 여러 건이 동시에 멈출 수 있다.
- Breakpoint 창: 왼쪽에 멈춘 건 목록(메서드·URL·요청/응답 단계), 오른쪽에 편집기.
  - 요청: URL(scheme·host·port·path), Method, Header 표, Query 표, Body(텍스트·JSON), **Raw** 탭(HTTP 메시지 원문 전체 편집).
  - 응답: Status Code, Header 표, Body, Raw 탭.
  - 버튼(단축키 Proxyman과 동일): **Continue Original ⌘.** / **Drop Connection ⌘\\**(옆 화살표 ▾ → Abort Mode: 429 응답 / 503 응답) / **Apply & Execute ⌘↩**.
  - Raw 탭의 **Templates ▾**: 저장된 Request/Response 템플릿 적용, Save as Template…, Reset to the Original.
- **Breakpoint Templates 창**(Tools ▸ Breakpoint ▸ Breakpoint Templates…): 왼쪽 트리 Request Templates / Response Templates, ⌘N 새 요청 템플릿, ⇧⌘N 새 응답 템플릿. 요청 템플릿 = Method·URL·Headers, 응답 템플릿 = Status·Headers.
- 멈춘 동안 클라이언트 연결은 열어 둔다. 자동 시간 제한은 두지 않는다. **[내 판단]** 대신 멈춘 건이 있으면 툴바 상태 캡슐에 "⏸ N건 대기"를 표시하고, 앱 종료 시 모두 Continue Original로 풀어 준다.
- 진입점: Tools ▸ Breakpoint ▸ Rules… / Breakpoints…(멈춘 건 창) / Breakpoint Templates…, 요청 우클릭 ▸ Tools ▸ Breakpoint…(현재 요청 URL로 규칙 미리 채움).

### 5.2 Map Local

- 규칙 = MatchRule + 대상: **Local File** 또는 **Local Directory**(세그먼트), + Advanced Settings: Delay Response(No Delay 외 프리셋).
- **File**: 응답은 HTTP 메시지 원문 파일(상태줄·헤더·빈 줄·본문). 편집기에 줄번호·문법색이 있는 HTTP 메시지 편집기를 보여 주고 ⌘S로 저장. `Select Local File`로 임의 파일(텍스트·JSON·바이너리·이미지)을 고르면 그 파일을 본문으로 쓰고 상태 200·Content-Type 추정. 메시지 안의 `<FILE_URL="경로">` 줄은 본문을 그 파일로 대신한다(`~` 확장). Content-Length는 실제 본문 길이로 다시 계산한다. **[내 판단]**
- **Directory**: 일치한 접두 부분을 떼고 남은 경로를 폴더 아래 상대 경로로 찾는다. host 전체 패턴이면 전체 경로를 쓴다. Regex는 첫 캡처 그룹이 상대 경로. **파일이 없으면 실제 서버 응답을 그대로 쓴다.** 쿼리는 파일 경로에 쓰지 않는다. **[내 판단]** Content-Type은 확장자로 추정, 상태 200.
- 응답 파일 저장 위치: `~/Library/Application Support/com.tv.eyeproxy/map-local/<host>_<ruleID>.http`. More ▸ Default Local File Folder(Choose Folder / Use Default Folder / Reveal in Finder).
- 진입점: Tools ▸ Map Local…, 요청 우클릭 ▸ Tools ▸ Map Local…(**현재 응답을 HTTP 메시지로 미리 채운 새 규칙** — 가장 많이 쓰는 흐름), 단축키 ⌥⌘L. **[내 판단: Proxyman 문서에 단축키 없음]**
- 편집기는 별도 창 "Map Local Editor: <이름>"(Proxyman과 동일).

### 5.3 Map Remote

- 규칙 = MatchRule(Include all subpaths 기본 켜짐 — Proxyman 실측) + Map To: Protocol / Host / Port / Path / Query. 빈 칸은 원래 값을 유지. Map To에는 와일드카드·정규식 불가. Host 칸에 URL을 붙여 넣으면 각 칸으로 자동 분해.
- Advanced: `☐ Preserve the Original URL after matching with Map Remote`(켜면 목록·상세에 원래 URL을 보이고 실제 전송만 바꾼다), `☐ Preserve Host Header`(기본: Host 헤더를 새 host로 바꾼다).
- Include all subpaths가 켜진 상태에서 Path를 바꾸면 일치한 접두 경로만 바꾸고 나머지 하위 경로는 이어 붙인다. **[내 판단]**
- 바뀐 요청은 상세 화면 요약에 "Map Remote: <규칙 이름> · 원래 URL"로 표시한다.
- 편집기는 시트(Proxyman과 동일). 진입점: Tools ▸ Map Remote…, 우클릭 ▸ Tools ▸ Map Remote…, ⌥⌘R.
- 보안: 기존의 LAN→루프백 차단(`shouldBlockUpstream`)은 Map Remote 후의 목적지에도 그대로 적용한다.

### 5.4 Block List

- 규칙 = MatchRule + Block Action: **Block & Hide Request**(막고 목록에 안 보임) / **Block & Display Requests**(막고 목록에 보임, 상태 "Blocked") / **Hide, but not Block**(통과시키되 목록에 안 보임).
- "막기"는 연결을 끊는다(Proxyman: "drops the connection"). HTTPS는 CONNECT 단계에서 host가 맞으면 터널을 열지 않고 끊는다.
- **Block App**: `Select App…`으로 Mac 앱을 고르면 그 앱의 트래픽 전체를 막는다. 앱 판별은 이미 있는 프로세스 귀속(Flow 화면 가독성 작업의 `ProcessIdentity`)을 쓴다.
- 숨겨진 요청은 세션에 기록하되 기본 목록에서 거른다. 필터 바에 "숨김 포함" 토글을 둔다. **[내 판단]**
- 진입점: Tools ▸ Block List…, 우클릭 ▸ Tools ▸ Block List…, ⌥⌘[.

### 5.5 Allow List

- 켜져 있으면 규칙에 맞는 요청만 EyeProxy에 기록·조작한다. 나머지는 통과(§4.5 1단계).
- Block List와 둘 다 맞으면 Block이 이긴다(순서상 Allow 판정 후 Block). **[내 판단]**
- 진입점: Tools ▸ Allow List…, ⌥⌘].

### 5.6 No Caching

- 규칙 없는 전역 토글: Tools ▸ No Caching(체크 메뉴), ⌥⌘N. 켜지면 메인 창 오른쪽 아래(상태줄)에 "No Caching" 배지.
- 복호화하는 요청·응답과 평문 HTTP에만 적용(터널은 내용을 못 보므로 제외).
- 요청: `If-Modified-Since`, `If-None-Match` 제거, `Pragma: no-cache`, `Cache-Control: no-cache` 추가.
- 응답: `Expires`, `Last-Modified`, `ETag` 제거, `Expires: 0`, `Cache-Control: no-cache` 추가.
- 설정 ▸ 도구: `☐ Repeat 요청에 No-Cache 사용`.

### 5.7 Network Conditions

- 규칙 = 이름 + 대상(host 문자열, 또는 `Apply System-wide`) + Network Profile. **한 번에 규칙 하나만 활성**(Proxyman 창의 주황 안내 "Only 1 Rule can be activated at once." 그대로 — 하나를 켜면 나머지는 꺼진다).
- 표 열: Enabled · Name · Status(● Active) · Host · Network Profile("Very Bad Network (Download: <1 mbps, Upload: <1 mbps)").
- 프리셋(Proxyman 문서의 이름·대역 그대로): 100% Loss / Very Bad Network(<1 mbps) / Slow Network(5–10) / Medium Network(10–20) / 2G EDGE(↓<240 kbps, ↑<200) / 3G(↓<780 kbps, ↑<330) / 4G LTE(↓30–50, ↑5–10) / 5G(↓50–150, ↑10–50) / Wi-Fi(↓25–40, ↑15–30) / Wi-Fi 802.11ac(↓150–250, ↑70–100). 대역폭은 범위 안에서 요청마다 무작위로 고른다(문서: "changes randomly within the given range"). 프리셋별 지연·손실 값은 문서에 없으므로 **[내 판단]** 표로 정한다: Very Bad = 1400 ms·10%(실측값), 2G = 650 ms·5%, 3G = 200 ms·2%, Slow = 150 ms·1%, Medium = 80 ms·0.5%, 4G = 50 ms·0, 5G = 20 ms·0, Wi-Fi = 10 ms·0, 802.11ac = 5 ms·0.
- **Custom Profile…**: 다운로드·업로드 Mbps, 지연 ms, 손실 %를 직접 넣고 이름 붙여 저장.
- 구현 방식 **[내 판단]**: EyeProxy는 P1에서 본문을 통째로 버퍼링하므로, 패킷 단위가 아니라 **요청 단위로 시간을 늦춘다**. 업로드 = 지연 + 요청 크기/업로드 대역폭, 다운로드 = 지연 + 응답 크기/다운로드 대역폭만큼 기다린 뒤 전달. 손실 %는 그 확률로 1초 재전송 지연을 한 번 더 넣는다. 100% Loss는 연결을 받기만 하고 응답하지 않는다(클라이언트 타임아웃까지). 터널(복호화 안 하는 HTTPS)은 바이트 스트림 사이에 같은 비율의 대기를 넣는다. 정밀한 패킷 수준 재현은 범위 밖.
- 진입점: Tools ▸ Network Conditions…, ⌥⌘J, 우클릭 ▸ Tools ▸ Network Conditions….

### 5.8 Compose / Repeat / Edit and Repeat

- **Compose 창**(Tools ▸ Compose Request…, ⌥⌘C, 툴바 버튼): 상단 [Method ▾] URL 입력(placeholder "Enter URL (Focus: ⌘K | Paste cURL Here | Send: ⌘↩)") [SEND (⌘↩)]. 왼쪽 Request(Header · Query · Body · Raw 탭, Key/Value 표 "New Key… / New Value…"), 오른쪽 Response(기존 상세 응답 뷰 재사용). 하단 [Template ▾](Empty Request, GET with Query, POST with JSON, POST with Form, POST with Multiparts, Import from cURL…), [History ▾](보낸 요청·응답 기록), (…) ▸ Request Timeout(15/30/60초/사용자 지정/없음).
- URL 칸에 cURL을 붙여 넣으면 메서드·헤더·본문으로 풀어 넣는다(기존 `CurlExport`의 역방향 파서를 Kit에 추가).
- 보낸 요청은 **EyeProxy 프록시를 거쳐** 나가고 메인 목록에도 기록된다(그래서 모든 도구가 적용됨). **[내 판단]**
- **Repeat**(Flow ▸ Repeat, ⌘↩, 여러 건 가능): 같은 요청을 다시 보낸다. **Edit and Repeat…**(⌥⌘↩): 그 요청으로 채운 Compose 창을 연다.
- 메뉴 위치는 Proxyman과 같게 **Flow** 메뉴를 새로 만든다: Repeat / Edit and Repeat… / — / (2차 이후 항목 자리).

### 5.9 Proxyman에서 가져오기

- 진입점: **Tools ▸ Import Settings ▸ From Proxyman…**, 그리고 각 도구 창 More ▸ Import…(파일 선택).
- "From Proxyman…"은 `~/Library/Application Support/com.proxyman.NSProxy/user-data/`를 **읽기 전용**으로 읽어 Map Local·Map Remote·Breakpoint·Network Conditions 규칙을 보여 주는 확인 시트를 띄운다(도구별 개수, 체크로 고르기). [가져오기]를 누르면 EyeProxy 규칙 목록 **끝에 추가**한다(기존 EyeProxy 규칙은 그대로).
- Map Local 응답 파일이 Proxyman `map-local/` 안에 있으면 EyeProxy `map-local/`로 복사하고 경로를 바꾼다. 밖에 있으면 경로를 그대로 쓴다(파일이 없으면 규칙을 가져오되 비활성 + 경고 아이콘).
- 가져온 규칙: `queryMode = exact`, 각 규칙의 `isEnabled`는 Proxyman 값 유지, **도구 스위치는 모두 꺼진 채**로 둔다(반목표).
- 같은 Proxyman 규칙 `id`가 이미 있으면 건너뛴다(두 번 눌러도 중복 없음).
- 알 수 없는 키·노드 종류는 무시하고 건너뛴 개수를 결과 시트에 보여 준다.
- 확인 시트에 `☐ SSL Proxying 목록도 가져오기`(Proxyman `SSLList-<projectID>`의 `nodes`·`excludeNodes`, 노드의 `kind.domain[].url`) 선택지를 둔다. 기본 켜짐. **[내 판단]**
- **파일 가져오기**(각 도구 창 More ▸ Import…, 상위 설계 §6의 "팀원과 규칙 공유" 경로): Proxyman 내보내기 `.config`(최상위 **노드 배열**)와 디스크 형식(`{"nodes":[…]}`)을 모두 받는다. Block List·Allow List도 이 경로로 받는다(사용자 데이터에는 아직 없어 디스크 형식 미확인 — Map Local과 같은 노드 틀에 `blockAction` 등 도구 필드가 붙는다고 보고, 모르는 필드는 건너뜀). **[빌더]** 필드 이름은 실제 파일을 얻으면 맞춘다.
- Proxyman 내보내기 파일에는 Map Local 응답 본문이 없으므로, 응답 파일 경로가 이 Mac에 없으면 그 규칙은 비활성 + 경고 아이콘으로 들이고 편집기에서 파일을 다시 고르게 한다.
- EyeProxy의 **More ▸ Export…**는 팀 공유가 되도록 폴더 하나(`<이름>.eyeproxyrules/`: Proxyman과 같은 노드 배열 `rules.config` + 참조하는 응답 파일 `map-local/`)로 내보내고, 가져올 때 이 폴더도 받는다. 응답 경로는 폴더 기준 상대 경로로 바꿔 쓴다. **[내 판단 — Proxyman보다 나은 점]**

### 5.10 EyeProxy 저장 형식

- 위치: `~/Library/Application Support/com.tv.eyeproxy/rules/` 아래 도구별 파일.
- 형식: **Proxyman과 같은 JSON 모양**을 쓰고, EyeProxy 전용 필드는 `eyeproxy` 하위 객체에 둔다(예: `"eyeproxy":{"queryMode":"selected","queryItems":[{"key":"a","value":"1","isEnabled":true}],"ignoreQuery":false}`). 그래야 Proxyman 파일을 그대로 넣어도 읽힌다. **[내 판단]**
  - `queryItems`는 선택한 항목만일 때만 쓴다. `ignoreQuery`(무시 → true, 나머지 → false)도 함께 써서 이전 빌드가 읽어도 크게 어긋나지 않게 한다. 구버전 파일(`ignoreQuery`만)은 true → 무시, false → 전체 일치로 읽고, `eyeproxy`가 없으면(Proxyman 규칙) 전체 일치. **[사용자]**
- Map Local 응답 파일 확장자는 `.http`(내용은 Proxyman과 같은 HTTP 메시지 원문). Proxyman에서 온 `.json` 이름도 그대로 읽는다.
- More ▸ Export…는 §5.9의 폴더 형식으로 내보낸다.

## 6. UI

### 6.1 메뉴 (Proxyman 배치를 따름)

- **Tools**: SSL Proxying List… / Compose Request… ⌥⌘C / — / Breakpoint ▸ (Rules…, Breakpoints…, Breakpoint Templates…) / Map Local… ⌥⌘L / Map Remote… ⌥⌘R / Block List… ⌥⌘[ / Allow List… ⌥⌘] / No Caching ⌥⌘N / — / Network Conditions… ⌥⌘J / — / Enable/Disable Tools ▸ (도구별 체크) / — / Import Settings ▸ From Proxyman… / —(2차 항목 자리)
- **Flow**(신규): Repeat ⌘↩ / Edit and Repeat… ⌥⌘↩ (기존 세션 저장·내보내기 항목은 지금 위치 유지 **[내 판단]**)
- 기존 "프록시" 메뉴는 그대로 둔다. 단축키 충돌: 기존 ⌘R(기록), ⇧⌘R(서버 재시작), ⌘D(기기 창)는 유지. 도구 창 안의 ⌘D(Duplicate)는 그 창이 키 창일 때만 동작하므로 충돌하지 않는다. **[빌더]** 실제 충돌이 있으면 도구 쪽 단축키를 바꾸고 문서에 남긴다.
- 요청 우클릭 메뉴: Tools ▸ Breakpoint… / Map Local… / Map Remote… / Block List… / Allow List… / Network Conditions… (현재 요청으로 미리 채움), Repeat, Edit and Repeat….

### 6.2 공통 도구 창 (Proxyman 레이아웃)

창 크기 약 1200×670. 위에서부터:
1. `☐ Enable <Tool> Tool`
2. 한 줄 설명(굵지 않은 기본색), 그 아래 회색 안내 "Each request is checked against the rules from top to bottom, stopping when a match is found." (Network Conditions는 주황 "Only 1 Rule can be activated at once.")
3. 규칙 표(폴더 트리 지원 도구는 접기/펼치기). 빈 표 가운데 `Click "+" or ⌘N to add new entry`. 행 드래그로 순서 변경(순서 = 우선순위). 행 더블클릭 = 편집.
4. 단축키 줄: `New: ⌘N  Edit: ⌘↩  Delete: ⌘⌫  Duplicate: ⌘D  Toggle: ␣`
5. 하단: `+ −`, `New Folder`(트리 도구), `?`(도움말 링크) … 오른쪽 `Filter`, `More ▾`(Import…, Export…, 도구별 항목).

- **⌘N은 편집기를 연다. 저장(Add/Save)하기 전에는 규칙이 추가되지 않고, 도구 스위치도 건드리지 않는다.** **[내 판단 — Proxyman 실측 동작(즉시 추가 + 도구 자동 켜기)과 일부러 다르게]**
- 삭제는 확인 시트 "선택한 규칙을 삭제할까요? 되돌릴 수 없습니다." 취소/삭제.
- 라이트·다크 모두 지원(기존 외관 설정 따름). 문구는 한국어로 하되 도구 이름(Map Local 등)은 영어 그대로. **[내 판단]**

### 6.3 편집기

- **Map Local**: 별도 창. Matching Rule 묶음(Name, URL, [Method ▾][Use Wildcard ▾] "와일드카드 * 와 ? 지원" `Test your Rule`, ☐ Include all subpaths, `쿼리: 무시 | 선택한 항목만 | 전체 일치` + 쿼리 표), Advanced Settings(Delay Response ▾), Map To 묶음([Local File | Local Directory], ☑ Enable Local File, 파일 경로, 상태 점 "HTTP 메시지 형식(저장됨)", 메시지 편집기), 하단 [Select Local File] … [⚙ ▾] [Save ⌘S].
- **Map Remote**: 시트. Matching Rule(Name, Rule, [Method ▾][Use Wildcard ▾], ☑ Include all subpaths, `쿼리: 무시 | 선택한 항목만 | 전체 일치` + 쿼리 표), Map To(Protocol/Host/Port/Path/Query + 안내 두 줄), Advanced(Preserve Original URL, Preserve Host Header), [Cancel] [Add ⌘↩].
- **Breakpoint 규칙**: 시트. Matching Rule + ☐ Request ☐ Response, [Cancel] [Add ⌘↩].
- **Block/Allow**: 시트. Matching Rule + (Block만) Action ▾, Block App [Select App…].
- **Network Conditions**: 시트. Name, ☐ Apply System-wide / Host, Network Profile ▾ + [Custom Profile…].
- 메시지 편집기와 본문 뷰는 기존 `CodeTextView`(줄번호, 줄바꿈 토글)를 편집 가능 모드로 확장해 쓴다.

## 7. Core·Kit 변경 방향

- `RequestDecision`에 `.drop`(연결 끊기)과 `.passthrough`(기록·조작 없이 전달) 추가. CONNECT 단계에서도 Block·Allow 판정을 할 수 있게 터널 전에 훅을 둔다.
- Breakpoint는 기존 `async` 인터셉터 안에서 사용자가 버튼을 누를 때까지 기다리는 방식으로 충분하다(continuation). 멈춘 건 목록은 앱 쪽 `@MainActor` 상태.
- `Flow`에 `isHidden`, `appliedTools`(예: Map Remote 원래 URL, Map Local 규칙 이름, Breakpoint 편집 여부) 추가. `.eyeproxy` 세션 파일과의 호환은 새 필드를 선택적(옵셔널)으로 두어 유지.
- Network Conditions는 업스트림 전송 전후 지연 + 터널 바이트 스트림 지연 훅.
- 규칙 저장·가져오기·매칭은 Kit(`Rules/` 폴더). 도구별 인터셉터는 "인터셉터 하나 + 뷰 하나" 규칙(CLAUDE.md)을 따른다.
- 외부 패키지 추가 없음. 정규식은 `NSRegularExpression`.

## 8. 테스트 기준

- 매칭: Wildcard·Regex·subpaths·쿼리 무시/선택한 항목만/전체 일치·메서드·scheme 생략 패턴에 대한 표 기반 테스트. 사용자 실데이터 형태 패턴(`https://host/path?*`, 쿼리 전체를 넣은 패턴)이 Proxyman과 같은 결과인지 포함.
- 가져오기: §3의 JSON 예시(값만 바꾼 것)를 픽스처로 넣어 모든 필드가 들어오는지, 두 번 가져와도 중복이 없는지, 도구 스위치가 꺼진 채인지.
- 각 도구: Core 통합 테스트(로컬 HTTP·HTTPS 서버 상대)로 Map Local 파일·디렉터리(없는 파일 fallback), Map Remote(Host 헤더 두 경우), Block 세 액션, Allow 통과, No Caching 헤더, Network Conditions 지연 하한, Breakpoint 세 버튼(Continue/Drop+Abort 429·503/Apply).
- Proxyman 사용자 데이터 폴더에 쓰기가 없는지(가져오기 테스트에서 읽기 전용 디렉터리로 검증).

## 9. 빌더가 확인·결정할 것

1. **Proxyman 폴더 노드 JSON 모양**: 사용자 데이터에 폴더가 없어 미확인. 사용자에게 Proxyman에서 폴더 하나를 만들어 달라고 하거나(에이전트가 직접 Proxyman 규칙을 만들지 말 것 — 실측에서 도구가 자동으로 켜졌다), 확인 전까지 폴더 노드는 "알 수 없는 노드"로 건너뛴다.
2. **Map Remote·Breakpoint 규칙 JSON**: 사용자 데이터가 비어 있어 미확인. Map Local과 같은 `nodeType.node._0` 틀에 도구별 필드가 붙는다고 보고, 필드 이름은 Proxyman 편집기 라벨에서 추정(`toURL`, `isPreserveHostHeader` 등)하되, 실제 파일을 확보하기 전에는 가져오기 지원 범위를 "Map Local + Network Conditions 확정, 나머지 시도"로 표시한다.
3. `regex` 필드의 정규식 값 이름(`useRegex` 추정)과 `delayTimePreset`의 단위(초 추정). 모르는 값이면 와일드카드/지연 없음으로 들이고 경고.
4. Network Conditions 프리셋의 지연·손실 표(§5.7)는 조정 가능.
5. 화면 문구의 세부 표현.
