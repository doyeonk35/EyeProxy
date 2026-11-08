# 목록·상세 편의, Export 기반, 상태 막대 눈 아이콘, 툴바 다듬기 설계

작성일 2026-11-09. 대상: Prog 0.2.0 + Certificate·필터 바·상태 막대 묶음(main a60fa59).

## 1. 의도

Prog을 실제로 써 보니 기능은 돌아가는데, Proxyman에서 매일 쓰던 손버릇(색칠해 두기, 지우기, 최신 요청 따라가기, 원문·요약 보기)이 없어 불편하다. 이번 묶음은 그 손버릇을 채운다. 사용자 말로 "Highlight, Delete / Delete All, Auto Select, 상세 탭은 진짜 자주 쓴다."

Export는 자주 쓰기도 하지만 더 중요한 이유가 있다: 나중에 **CLI·MCP 스킬**이 같은 내보내기 기능 위에 올라간다. 그래서 형식과 API를 지금 고정해 둔다.

같이 들어가는 다듬기 두 가지:
- 상태 막대 아이콘이 잘 안 보인다 → 개구리 **눈만** 남기고, 확인할 일이 있을 때 **빨간 점**(카카오톡 배지처럼).
- 툴바 캡슐이 빽빽하다 → 여백을 늘리고, "숨김 포함" 체크박스를 **심볼 토글**로.
- 앱 안의 메뉴·버튼에 **길게 호버하면 한 줄 설명**이 뜬다.

## 2. 목표·비목표·반목표

**목표**
- Highlight, Delete/Delete All, Auto Select, 상세 Raw·Summary·M3U8 탭을 Proxyman 수준으로 손에 익게.
- Export(HAR·CSV·Prog 세션)와 HAR 가져오기. 로직은 Kit의 순수 API — 나중에 CLI·MCP가 그대로 부른다.
- 상태 막대 눈 아이콘 + 빨간 점(A안: 확인할 일이 있을 때만).
- 툴바 여백, 숨김 토글 심볼화, 모든 메뉴·툴바 항목에 한 줄 툴팁.

**비목표(이번 묶음에서 하지 않음, 바로 다음 묶음)**
- Open Recent, 한 창 안의 세션 탭 여러 개.
- 호스트 그룹 탭(사내 도메인을 묶어 SSL Proxying을 한 번에 켜고 그 요청만 보는 탭, 원하는 도메인만 모은 탭).
- CLI·MCP 서버 자체.
- 기기(Apple TV·iPhone) 요청의 앱별 묶기 — 별도 검토 중.

**반목표(이렇게 되면 실패)**
- Export 형식이 앱 UI에 묶여 CLI에서 다시 짜야 한다.
- HAR로 내보냈다 다시 가져오면 Highlight·코멘트·도구 표시가 사라진다.
- Auto Select가 사용자가 보던 행을 계속 빼앗는다.
- Delete All이 필터에 가려 안 보이던 요청까지 말없이 지운다.
- 빨간 점이 평소에도 떠 있어 아무 의미가 없다.

## 3. 제약

- Swift 6 strict concurrency, SwiftUI, macOS 15+. 외부 패키지는 CLAUDE.md 허용 목록만(새 패키지 금지). 모듈 방향 `EyeProxy`(앱) → `EyeProxyKit` → `EyeProxyCore`.
- 직렬화·파싱(HAR·CSV·M3U8·Raw)은 `EyeProxyKit`의 순수 함수로 두고 Swift Testing으로 고정. 앱은 패널·메뉴만.
- 표시 이름은 Prog, 코드 식별자·번들 ID·`eyeproxy.*` 키·`.eyeproxy` 확장자는 그대로(이전 묶음 §8 결정 유지).
- UI 문자열은 한국어, 메뉴 항목 이름은 Proxyman과 같은 영어. 툴팁은 한국어 한 줄.
- 공개 레포: 커밋 파일에 회사 내부 도메인·로컬 사용자 경로 금지(테스트 픽스처는 `example.com` 류).

## 4. Highlight

- 색 6개(Red, Yellow, Green, Blue, Purple, Gray) + Strikethrough + Reset. Proxyman Flow ▸ Highlight와 같은 이름·순서.
- 어디서: Flow 메뉴 ▸ Highlight ▸ …, 목록 우클릭 ▸ Highlight ▸ …. 단축키: ⌘1…⌘6 = 색, ⌘⌥S(Strikethrough 토글), ⌘0 = Reset(제 판단, 다른 단축키와 겹치지 않는지 구현 때 확인).
- 여러 행 선택 시 모두에 적용. 색은 하나만(새 색이 덮어씀), 취소선은 색과 독립 토글.
- 표시: 행 전체 배경을 옅게(라이트 18%, 다크 28% 정도 불투명도) 칠한다. 선택된 행은 시스템 선택색이 우선이고, 선택 행에서도 색을 알아볼 수 있게 행 앞(상태 점 열)에 같은 색 세로 막대 3pt를 둔다. 취소선은 URL 열 글자에 줄을 긋고 글자를 보조색으로.
- 저장: `SessionStore`에 `highlights: [FlowID: FlowHighlight]`(`color: HighlightColor?`, `strikethrough: Bool`)를 코멘트와 같은 방식으로 두고, 세션 파일 `Index`에 `highlights` 필드 추가(구버전 세션엔 없음 → 빈 값).
- 필터 바·검색과는 무관(색으로 거르기는 이번 범위 밖).

## 5. Delete / Delete All

- Flow ▸ Delete(⌫): 선택한 행을 세션에서 지운다. 지운 뒤 선택은 바로 아래 행으로(없으면 위).
- Flow ▸ Delete All: **보이는 행만** 지운다(필터·사이드바 선택이 걸러 낸 행은 남김). 필터가 걸려 있을 때만 확인 알림("보이는 N개를 지웁니다. 숨겨진 M개는 남습니다.").
- 기존 "세션 지우기"(⌘K, 전부 지움)는 그대로 둔다. Proxyman의 Clear Session과 같은 자리.
- 지운 흐름의 코멘트·Highlight·프로세스 귀속도 같이 정리. 되돌리기(⌘Z)는 이번 범위 밖.
- Kit: `SessionStore.remove(ids: Set<FlowID>)`.

### 5.1 안정 번호(사용자 결정 2026-11-09: a안)

ID 열 번호는 Proxyman처럼 **한 번 붙으면 끝까지 그대로**다. 지워도 뒤 번호를 당기지 않아 빈 번호가 생긴다. 코멘트·Export·나중의 CLI/MCP가 "요청 #1499"로 가리켜도 바뀌지 않게 하기 위해서다.

- 지금 구조: 번호 = 목록 위치 + 1(`SessionStore.numbers`가 위치에서 파생, `remove(at:)`가 `next -= 1` 하고 뒤를 당김, `replace()`도 위치로 다시 매김). 이것을 **번호를 저장하는 구조**로 바꾼다: `requestStarted`에서 `next`를 붙이고, 어떤 삭제도 다른 흐름의 번호를 바꾸지 않는다.
- Allow List의 `unrecorded`로 곧바로 빠지는 흐름(기록하지 않는 요청): 그 흐름이 **가장 최근 번호**를 갖고 있으면 `next`를 하나 되돌려 빈 번호를 만들지 않는다. 그 사이 다른 요청이 번호를 받았으면 빈 번호를 남긴다(제 판단 — Allow List를 켠 동안 번호가 크게 뛰지 않게).
- 세션 파일(.eyeproxy): `Index`에 `numbers: [String: Int]?`(키 = FlowID) 추가. 열 때 있으면 그대로 쓰고 `next = 최대 + 1`, 없으면(구버전 세션) 지금처럼 순서대로 1부터.
- `replace(flows:…)`는 번호 사전을 받는 형태로 바꾼다(없으면 순서대로).
- 정렬 키 `FlowRow.number`는 저장된 번호를 쓴다.

## 6. Auto Select

- View ▸ Auto Select the Latest Request(토글, 앱 설정에 저장 `eyeproxy.autoSelectLatest`, 기본 끔).
- 켜져 있으면 **보이는 목록에** 새 요청이 들어올 때마다 그 행을 선택하고 스크롤한다(상세도 따라 바뀜). 필터에 걸려 안 보이는 요청은 따라가지 않는다.
- 사용자가 직접 다른 행을 클릭하거나 키보드로 선택을 옮기면 Auto Select를 **끈다**(메뉴 체크도 꺼짐). 다시 쓰려면 메뉴로 켠다. — 보던 행을 빼앗지 않기 위해(반목표). 제 판단.
- 정렬이 ID 오름차순이 아니면(예: 시간 내림차순) "가장 최근 요청" = 시작 시각이 가장 늦은 보이는 행.

## 7. 상세 탭: Raw · Summary · M3U8

현재 요청·응답 패널 탭: 헤더 / 쿼리 / 본문 / 쿠키. 추가:

- **Raw** (요청·응답 각 패널): HTTP/1.1 원문 텍스트 — 시작 줄 + 헤더 + 빈 줄 + 본문. 본문이 텍스트(UTF-8 디코딩 성공)면 그대로, 아니면 `<binary N bytes>` 한 줄. 압축 본문은 기존 본문 탭과 같은 디코딩 규칙(BodyDecoder) 적용 후 표시하고 헤더는 원래 값 그대로. 선택·복사 가능, 기존 CodeTextView 재사용. Kit: `RawMessage.request(_:)`, `RawMessage.response(_:)` → `String`.
- **Summary** (상세 상단 또는 응답 패널 앞에 하나만 — 구현이 단순한 쪽): URL, 메서드, 상태, 클라이언트(기기 이름 또는 Mac 앱), 시작 시각, 소요 시간, 요청·응답 크기, SSL(복호화 여부), 적용된 도구(Edited 표시와 같은 값), 원래 URL·실제 전송 URL(Map Remote), 코멘트, Highlight. 키-값 표.
- **M3U8**: 응답이 HLS 재생목록일 때만 탭이 보인다(조건: 요청 path가 `.m3u8`로 끝나거나 응답 Content-Type이 `application/vnd.apple.mpegurl`·`application/x-mpegurl`·`audio/mpegurl`). 두 종류:
  - Master playlist: `#EXT-X-STREAM-INF` 행마다 BANDWIDTH, AVERAGE-BANDWIDTH, RESOLUTION, CODECS, FRAME-RATE, URI 표. `#EXT-X-MEDIA`(오디오·자막) 표 하나 더.
  - Media playlist: TARGETDURATION, MEDIA-SEQUENCE, PLAYLIST-TYPE, ENDLIST 여부 요약 + `#EXTINF` 세그먼트 표(순번, 길이, URI, BYTERANGE, DISCONTINUITY 표시), `#EXT-X-KEY`(METHOD·URI) 표시.
  - URI는 요청 URL 기준 절대 URL로 풀어 보여 주고, 우클릭으로 복사.
  - Kit: `M3U8.parse(_ text: String, baseURL: URL?) -> M3U8Playlist`(enum master/media). 모르는 태그는 무시.

## 8. Export·Import (CLI·MCP 기반)

### 8.1 API (Kit, 순수)

```
FlowExport.har(_ items: [ExportItem], creator: String = "Prog", version: String) -> Data   // HAR 1.2 JSON
FlowExport.csv(_ items: [ExportItem]) -> String
FlowImport.har(_ data: Data) throws -> [ImportedFlow]   // Flow + 코멘트·Highlight·도구 표시 복원
struct ExportItem { flow: Flow; number: Int; comment: String?; highlight: FlowHighlight?; client: String? }
```
- 앱·CLI·MCP 모두 이 함수만 부른다. 앱은 범위 결정과 저장 패널만.
- 세션 파일(.eyeproxy) 내보내기는 기존 `SessionDocument.save`를 범위만 좁혀 재사용.

### 8.2 HAR 1.2 매핑

- `log.creator = {name: "Prog", version: <앱 버전>}`, `log.entries[]` 하나가 흐름 하나.
- `startedDateTime`(ISO 8601 ms), `time`(ms, 미완료면 -1 대신 0 + `_prog.incomplete: true`), `request`(method, url, httpVersion "HTTP/1.1", headers, queryString, postData{mimeType, text} — 바이너리면 `encoding: "base64"`), `response`(status, statusText, headers, content{size, mimeType, text, encoding?}, redirectURL), `cache: {}`, `timings`(send 0, wait=time, receive 0 — 세부 타이밍은 없음), `serverIPAddress` 생략.
- 응답 없음(실패·대기): `response.status = 0`, `_prog.error`에 오류 문구.
- Prog 확장(HAR 규칙: `_` 접두): `entry._prog = {number, comment, highlight: {color, strikethrough}, tools: ["Map Local", …], client, isTunnel, isDecrypted, originalURL, sentURL}`.
- 본문 크기 상한 없음(기록된 그대로). 텍스트 판정은 UTF-8 디코딩 성공 여부.

### 8.3 CSV

열: ID, Method, URL, Status, Code, Client, Start(ISO 8601), Duration(ms), Request Size, Response Size, SSL, Edited, Highlight, Comment. RFC 4180 따옴표 규칙, UTF-8, 첫 행 헤더. 본문은 넣지 않는다.

### 8.4 범위·메뉴

- Flow ▸ Export ▸ as HAR (HTTP Archive)… / as CSV… / as Prog Session…, 우클릭에도 같은 하위 메뉴.
- 범위: 선택한 행이 있으면 선택한 행, 없으면 보이는 행 전체. 저장 패널 기본 이름 `Prog-<yyyyMMdd-HHmmss>.har|.csv|.eyeproxy`.
- Flow ▸ Save Requests…: 선택한 행만 Prog 세션으로 저장(Proxyman 이름 그대로; Export as Prog Session과 같은 동작이지만 선택이 없으면 비활성).

### 8.5 HAR 가져오기

- File ▸ 세션 열기…가 `.eyeproxy`와 `.har`를 모두 받는다. HAR이면 `FlowImport.har`로 읽어 현재 세션을 **교체**(기존 열기 동작과 같음).
- `_prog`가 있으면 번호(§5.1 안정 번호 — 서로 겹치지 않을 때만, 겹치면 전체를 순서대로 다시 매김)와 코멘트·Highlight·도구 표시·클라이언트·터널·복호화 여부를 복원하고, 없으면(다른 도구의 HAR) 순서대로 번호 + 기본값.
- 내보내기의 `_prog.number`와 CSV의 ID 열은 저장된 안정 번호(빈 번호 그대로).
- 왕복 테스트: 내보낸 HAR을 다시 가져오면 번호·메서드·URL·상태·헤더·본문 바이트·코멘트·Highlight·도구 표시가 같다.

## 9. 상태 막대 아이콘 — 눈만 + 빨간 점(A안)

- 모양(목업 `menubar-toolbar-v2.html` A안): 눈 두 개 + 이어진 아래쪽 띠. 상태: 기록 중 = 눈 뜸(눈동자 구멍), 일시정지 = 눈 감음(감은 눈 선), 서버 중지·실패 = 빈 눈 윤곽 + 사선.
- 단색 템플릿(라이트·다크 자동 반전)은 그대로 유지하고, **빨간 점만 컬러**로 겹친다(오른쪽 위). 점 = "확인할 일 있음": 멈춘 Breakpoint가 1개 이상, 서버 시작 실패(`.failed`), 규칙 파일 경고가 있음. 셋 다 없으면 점 없음.
- 구현 방향(빌더 판단): 템플릿 눈 이미지를 그리고 그 위에 시스템 빨강 원을 합성한 `NSImage`(isTemplate = false, 점 없는 상태는 template = true)를 라벨로. 라이트·다크 막대에서 눈 색이 맞게 나와야 한다.
- `Design/`에 새 SVG 3개(`MenuBar-Eyes-Open/Closed/Stopped.svg`)를 추가하고 `scripts/make-icons.sh`로 카탈로그 생성(이전 묶음 방식 그대로). 기존 개구리 상태 막대 에셋은 지운다.
- 접근성 레이블: "Prog — 기록 중/일시정지/서버 중지[, 확인 필요]".

## 10. 툴바 다듬기

- 여백(목업 "제안"): 버튼 묶음 캡슐 안쪽 4~5pt, 버튼 사이 4pt, 상태 캡슐 좌우 14pt·위아래 6pt. macOS 26 기본 툴바 유리 캡슐 안에서 SwiftUI가 허용하는 방식으로(빌더 판단).
- "숨김 포함" 체크박스 → 아이콘 토글 버튼: 끔 = `eye.slash`, 켬 = `eye` + 강조(선택) 상태. SSL 자물쇠와 같은 묶음에 둔다. 동작은 그대로(`filter.includeHidden`).
- 상태 표시(No Caching 캡슐, Breakpoint 대기 버튼, 규칙 경고)는 그대로.

## 11. 툴팁(길게 호버하면 한 줄 설명)

- 대상: 툴바의 모든 버튼·토글·피커, 필터 바 칩(이미 있음), 메뉴 막대의 Flow·Tools·Certificate·View·File 사용자 정의 항목, 상태 막대 메뉴 항목, 목록 우클릭 메뉴 항목, Certificate 창의 버튼.
- 문구: 한국어 한 줄, "무엇을 하는가"(예: "Block List로 숨긴 요청도 목록에 보이기", "선택한 요청을 HAR 1.2 파일로 저장"). 단축키가 있으면 끝에 괄호.
- SwiftUI `.help(_:)` 사용. 메뉴 항목에서 `.help`가 실제 툴팁으로 뜨는지 macOS 15·26에서 확인하고, 뜨지 않으면 그 사실을 보고(대체 수단을 임의로 만들지 말 것 — 다음 결정은 사용자).

## 12. 다음 묶음을 위한 준비(이번에 구조만)

- 세션 탭·호스트 그룹 탭이 "필터 조건 + 세션"을 탭마다 따로 가질 수 있게, 세션에 속하는 데이터(Highlight·코멘트)는 `SessionStore`에 둔다.
- (제 판단) 선택·정렬·필터·Auto Select 같은 **보기 상태**는 이번에는 지금처럼 `AppModel`에 둔다. 탭별로 나누는 일은 다음 묶음(세션 탭)에서 한 번에 한다 — 이번에 옮기면 선택·정렬 구조를 두 번 뜯게 된다.
- Export API가 `[ExportItem]`을 받으니 탭별 내보내기도 그대로 된다.

## 13. 빌더에게 맡기는 것

- Highlight 색의 정확한 불투명도·세로 막대 폭, 단축키 충돌 시 대안.
- Summary를 상단 고정 영역으로 둘지 패널 탭으로 둘지.
- M3U8 표의 열 폭·정렬.
- 상태 막대 아이콘 합성 방식, 빨간 점 크기.
- 툴바 여백을 넣는 정확한 SwiftUI 방식.
- 테스트 구성: HAR 직렬화·왕복, CSV 이스케이프, M3U8 파싱(master·media·상대 URI·BYTERANGE·KEY), Raw 텍스트, `SessionStore.remove`·highlights·세션 파일 왕복, Auto Select 끄기 규칙(가능하면 순수 로직으로 분리)은 자동 테스트. 툴팁·아이콘 표시·여백은 수동 점검표.
