# 목록·상세 편의, Export 기반, 상태 막대 눈 아이콘, 툴바 다듬기 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 안정 번호·Highlight·Delete·Auto Select·Raw/Summary/M3U8 탭·HAR/CSV Export와 HAR 가져오기를 넣고, 상태 막대 아이콘을 눈+빨간 점으로, 툴바 여백과 숨김 토글·툴팁을 다듬는다.

**Architecture:** 직렬화·파싱·세션 모델 변경은 `EyeProxyKit`의 순수 코드와 `SessionStore`/`SessionDocument`에 두고 Swift Testing으로 고정한다. 앱은 메뉴·패널·행 표시만 붙인다. Export API는 CLI·MCP가 그대로 부를 수 있는 공개 순수 함수다.

**Tech Stack:** Swift 6, SwiftUI(macOS 15+), AppKit(NSSavePanel/NSOpenPanel/NSImage), swift-crypto 등 기존 패키지만.

**Spec:** `docs/superpowers/specs/2026-11-09-prog-list-detail-export-design.md` — 번호(§)는 이 스펙.

## Global Constraints

- Swift 6 strict concurrency, macOS 15+. 외부 패키지는 CLAUDE.md 허용 목록만(새 패키지 금지). 모듈 방향 `EyeProxy` → `EyeProxyKit` → `EyeProxyCore`.
- 표시 이름 Prog. 번들 ID `com.tv.eyeproxy`, `eyeproxy.*` 설정 키, `.eyeproxy` 세션 확장자·UTI, 모듈·폴더 이름은 그대로.
- UI 문자열 한국어, 메뉴 항목 이름은 Proxyman과 같은 영어, 툴팁은 한국어 한 줄.
- 공개 레포: 커밋 파일에 회사 내부 도메인·로컬 사용자 경로 금지. 테스트 픽스처 호스트는 `example.com` 류.
- 각 Task 끝: `swift test --package-path Packages/EyeProxyKit`(Core를 건드렸으면 Core도), 앱을 건드렸으면 `xcodegen generate && xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates` 통과. `Package.resolved` 변경은 되돌리고 커밋하지 않는다.
- 커밋 메시지 `<type>(<scope>): <한국어 요약>`.
- 수동 확인 규칙: 화면 잠금 확인 후 자기 디버그 빌드만 포트 19090(`-eyeproxy.port '<integer>19090</integer>'`)으로 띄운다. 알림·저장 패널·관리자 인증 같은 모달은 열지 않는다(모달 경로는 수동 점검표로). 시스템 프록시·키체인 명령 금지.
- 같은 레포에서 다른 세션(기기 앱별 묶기)이 별도 워크트리로 `ProcessIdentity`·`SidebarTree`·`AppModel` 귀속 코드를 바꾼다. 이 묶음은 그 파일들을 꼭 필요한 만큼만 건드린다.

## Review Focus

1. 중간 요청을 지운 뒤 새 요청이 들어오면 번호가 이어서(지운 번호를 재사용하지 않고) 붙는다 → Task 2 `numbersStayStableAfterRemoval`.
2. 번호가 없는 옛 세션 파일을 열면 1부터 순서대로, 번호가 있는 세션 파일은 빈 번호까지 그대로 열린다 → Task 1 `sessionFileRoundTripsStableNumbers`, `legacySessionGetsPositionalNumbers`.
3. 바이너리 본문(이미지·gzip)과 한글 텍스트 본문이 HAR 왕복에서 바이트 그대로 돌아온다 → Task 7 `harRoundTripPreservesBinaryAndUTF8Bodies`.
4. CSV에 쉼표·따옴표·줄바꿈이 든 URL·코멘트가 있어도 열이 밀리지 않는다 → Task 7 `csvEscapesCommasQuotesAndNewlines`.
5. 상대 URI·쿼리가 붙은 재생목록 URL·BYTERANGE가 있는 미디어 재생목록도 세그먼트 표가 맞게 나온다 → Task 5 `mediaPlaylistResolvesRelativeURIsAndByteRanges`.

---

### Task 1: 안정 번호 (Kit)

**Files:** Modify `Packages/EyeProxyKit/Sources/EyeProxyKit/SessionStore.swift`, `SessionDocument.swift`; Test `Tests/EyeProxyKitTests/SessionStoreTests.swift`, `SessionDocumentTests.swift`.

**Interfaces:**
- Produces: `SessionStore.replace(flows: [Flow], connectionLog: [ConnectionLogEntry] = [], comments: [FlowID: String] = [:], highlights: [FlowID: FlowHighlight] = [:], numbers: [FlowID: Int]? = nil)` — `numbers == nil`(또는 빠진 흐름)이면 순서대로; `next = max + 1`. `SessionStore.numbersByID: [FlowID: Int]`(저장용 읽기 전용). `SessionDocument.save(..., numbers: [FlowID: Int] = [:], highlights: [FlowID: FlowHighlight] = [:], to:)`, `load` 반환 튜플에 `numbers: [FlowID: Int]?`, `highlights: [FlowID: FlowHighlight]` 추가(구버전 파일은 nil/빈 값). (`FlowHighlight`는 Task 2가 정의 — 이 Task에서는 Task 2와 함께 한 번에 넣어도 되고, 먼저 번호만 넣어도 된다; 같은 implementer가 Task 1→2 순서로 진행.)
- §5.1 규칙: `requestStarted`에서 `next` 부여, 어떤 삭제도 다른 흐름의 번호를 바꾸지 않음. `unrecorded`로 빠지는 흐름이 가장 최근 번호면 `next -= 1`, 아니면 빈 번호.

- [ ] **Step 1 테스트**: `unrecordedLatestDoesNotLeaveGap`(1 시작 → 2 시작 → 2 unrecorded → 다음 요청 2), `unrecordedEarlierLeavesGap`(1·2 시작 → 1 unrecorded → 3 시작 → 번호 2·3), `sessionFileRoundTripsStableNumbers`(번호 1·3·7 저장 → 로드 후 `replace(numbers:)` → 같은 번호, 다음 요청 8), `legacySessionGetsPositionalNumbers`(`numbers` 키 없는 index.json 픽스처 → 1,2,3).
- [ ] **Step 2** 실패 확인 → **Step 3** 구현(위치 파생 `numbers` 대신 저장 사전; `index`만 위치 파생) → **Step 4** Kit 전체 통과.
- [ ] **Step 5 앱 연결**: `AppModel.saveSession`/`openSession`이 번호를 저장·복원(`session.numbersByID`). 빌드 통과.
- [ ] **Step 6 커밋**: `feat(session): ID 번호를 안정 번호로 — 지워도 다시 매기지 않음`

### Task 2: 삭제와 Highlight 모델 (Kit)

**Files:** Create `Packages/EyeProxyKit/Sources/EyeProxyKit/FlowHighlight.swift`; Modify `SessionStore.swift`, `SessionDocument.swift`; Tests 같은 파일들.

**Interfaces:**
- Produces: `public enum HighlightColor: String, CaseIterable, Codable, Sendable { case red, yellow, green, blue, purple, gray }`(Proxyman 순서), `public struct FlowHighlight: Codable, Equatable, Sendable { public var color: HighlightColor?; public var strikethrough: Bool; public var isEmpty: Bool }`.
- `SessionStore.highlights: [FlowID: FlowHighlight]`(관찰), `setHighlight(_ color: HighlightColor?, for ids: Set<FlowID>)`(nil = 색 지움), `toggleStrikethrough(for ids: Set<FlowID>)`(선택 중 하나라도 꺼져 있으면 전부 켬, 아니면 전부 끔), `resetHighlight(for ids:)`, `remove(ids: Set<FlowID>)`(코멘트·Highlight 함께 정리, 번호 불변). 빈 `FlowHighlight`는 저장하지 않는다.
- 세션 파일 `Index.highlights: [String: FlowHighlight]?`.

- [ ] **Step 1 테스트**: `numbersStayStableAfterRemoval`(1·2·3 시작 → `remove(ids: [2])` → 남은 번호 1·3, 다음 요청 4), `removeKeepsOtherNumbersAndDropsAnnotations`, `highlightSetResetAndStrikeToggle`(혼합 선택의 취소선 규칙 포함), `sessionFileRoundTripsHighlights`.
- [ ] Step 2~4 RED→구현→GREEN. **Step 5 커밋**: `feat(session): 흐름 삭제와 Highlight 모델·세션 저장`

### Task 3: Highlight·Delete UI (앱)

**Files:** Modify `EyeProxy/Commands/ToolsCommands.swift`(FlowMenu), `EyeProxy/Views/FlowList/FlowListView.swift`, `EyeProxy/AppModel.swift`, `EyeProxy/Views/Shared/Tags.swift`(색 매핑).

**Interfaces:**
- Consumes: Task 2 API. Produces: `AppModel.deleteFlows(_ ids: Set<FlowID>)`(선택 이동: 지운 행 바로 아래 보이는 행, 없으면 위), `AppModel.deleteVisibleFlows()`(보이는 행만; 필터·사이드바가 거르고 있으면 확인 알림 "보이는 N개를 지웁니다. 숨겨진 M개는 남습니다." — 걸러진 게 없으면 확인 없이), `HighlightColor.swiftUIColor`.
- Flow 메뉴: 기존 항목 뒤 `Divider` + `Menu("Highlight") { Red ⌘1 … Gray ⌘6, Divider, Strikethrough ⌥⌘S, Reset ⌘0 }` + `Divider` + `Delete` ⌫ + `Delete All`(보이는 행). 기존 "세션 지우기" ⌘K 유지. 같은 Highlight 하위 메뉴와 Delete를 목록 우클릭에도. 단축키가 기존 것과 겹치면 다른 조합을 고르고 리포트에 적는다.
- 행 표시(§4): 모든 셀 배경을 Highlight 색 옅게(라이트 0.18, 다크 0.28 불투명도 — `@Environment(\.colorScheme)`), 상태 점 열에 같은 색 3pt 세로 막대(선택 행에서도 보이게), 취소선이면 URL 텍스트에 `.strikethrough()` + 보조색. 셀 패딩 때문에 빈 틈이 생기면 셀 프레임을 꽉 채우는 배경으로(빌더 판단).
- 선택 해제·Delete 뒤 상세 창은 새 선택을 따른다.

- [ ] Step 1 구현 → Step 2 빌드 → **Step 3 수동 확인**(모달 금지 규칙): 트래픽 몇 개 만든 뒤 Highlight 색·취소선·Reset·Delete가 보이는지 스크린샷(라이트·다크 각 1장). Delete All은 확인 알림이 뜨는 경로라 필터 없는 상태에서만 눌러 본다. → **Step 4 커밋**: `feat(list): Highlight 색·취소선과 Delete·Delete All`

### Task 4: Auto Select (Kit 규칙 + 앱)

**Files:** Create `Packages/EyeProxyKit/Sources/EyeProxyKit/AutoSelect.swift`; Modify `AppSettings.swift`(키 `eyeproxy.autoSelectLatest`, 기본 false), `EyeProxy/AppModel.swift`, `EyeProxy/EyeProxyApp.swift`(View 메뉴: `CommandGroup(after: .toolbar)` 근처에 `Toggle("Auto Select the Latest Request")`), `FlowListView.swift`(스크롤).

**Interfaces:**
- Produces: `AutoSelect.latest(in rows: [FlowRow]) -> FlowID?`(시작 시각이 가장 늦은 행, 같으면 번호가 큰 행), `AutoSelect.shouldDisable(userSelected: Set<FlowID>, autoSelected: FlowID?) -> Bool`(사용자 선택이 자동 선택한 것과 다르면 true).
- 앱: 켜져 있고 `visibleRows`가 바뀌면 `latest`를 선택하고 `ScrollViewReader`로 스크롤. 사용자가 다른 행을 선택하면 설정을 끈다(메뉴 체크 꺼짐).
- [ ] Step 1 테스트: `latestPicksNewestStartedAt`, `userSelectionDisablesAutoSelect`, `settingPersists`(AppSettingsTests). → RED → 구현 → GREEN → 빌드 → 수동 확인(켠 채 curl 3번 → 마지막 행 선택·상세 표시 스크린샷, 다른 행 클릭 → 메뉴 체크 꺼짐) → **커밋** `feat(list): 최신 요청 자동 선택(Auto Select)`

### Task 5: M3U8 파서 (Kit)

**Files:** Create `Packages/EyeProxyKit/Sources/EyeProxyKit/Text/M3U8.swift`; Test `Tests/EyeProxyKitTests/M3U8Tests.swift`(픽스처는 문자열 리터럴, 호스트 `example.com`).

**Interfaces:**
- Produces: `public enum M3U8Playlist: Equatable, Sendable { case master(Master), media(Media) }`; `Master { variants: [Variant] (bandwidth: Int?, averageBandwidth: Int?, resolution: String?, codecs: String?, frameRate: Double?, uri: String, absoluteURL: URL?), renditions: [Rendition] (type, groupID, name, language, isDefault, uri: String?, absoluteURL: URL?) }`; `Media { targetDuration: Int?, mediaSequence: Int?, playlistType: String?, hasEndList: Bool, segments: [Segment] (index: Int, duration: Double, title: String?, uri: String, absoluteURL: URL?, byteRange: String?, discontinuity: Bool), keys: [Key] (method, uri: String?) }`; `M3U8.parse(_ text: String, baseURL: URL?) -> M3U8Playlist?`(첫 줄 `#EXTM3U` 아니면 nil), `M3U8.isPlaylist(path: String, contentType: String?) -> Bool`(§7 조건).
- 속성 목록 파싱은 따옴표 안 쉼표 처리(CODECS="avc1.640028,mp4a.40.2"). 모르는 태그 무시.
- [ ] Step 1 테스트: `masterPlaylistParsesVariantsAndRenditions`, `mediaPlaylistResolvesRelativeURIsAndByteRanges`(baseURL에 쿼리 있는 경우 포함), `mediaPlaylistMarksDiscontinuityAndKey`, `nonPlaylistReturnsNil`, `isPlaylistDetectsPathAndContentTypes`. → RED → 구현 → GREEN → **커밋** `feat(detail): M3U8 재생목록 파서`

### Task 6: 상세 Raw·Summary·M3U8 탭 (Kit Raw + 앱)

**Files:** Create `Packages/EyeProxyKit/Sources/EyeProxyKit/Text/RawMessage.swift`, `EyeProxy/Views/Detail/SummaryView.swift`, `EyeProxy/Views/Detail/M3U8View.swift`; Modify `EyeProxy/Views/Detail/FlowDetailView.swift`(MessagePane 탭); Test `RawMessageTests.swift`.

**Interfaces:**
- Produces: `RawMessage.request(_ r: FlowRequest) -> String`(`"<METHOD> <path> HTTP/1.1\r\n"` + 헤더 줄 + 빈 줄 + 본문), `RawMessage.response(_ r: FlowResponse) -> String`(`"HTTP/1.1 <status> <reason>"`…). 본문: `BodyDecoder`(기존)로 압축 해제 시도 후 UTF-8이면 텍스트, 아니면 `<binary N bytes>`. 표시용이라 줄바꿈은 `\n`로(빌더 판단, 테스트로 고정).
- `MessagePane.Tab`에 `.raw` 추가(요청·응답 양쪽), 응답 쪽은 `M3U8.isPlaylist`이면 `.m3u8` 탭. Summary는 상세 상단 `FlowHeaderBar` 아래 접을 수 있는 영역 또는 탭 — 빌더 판단(스펙 §13), 내용은 스펙 §7 목록 전부.
- M3U8View: master면 변형 표 + 렌디션 표, media면 요약 줄 + 세그먼트 표 + 키 표. URI 셀 우클릭 "URL 복사".
- [ ] Step 1 테스트: `rawRequestFormatsStartLineHeadersAndBody`, `rawResponseShowsBinaryPlaceholder`, `rawDecodesGzipBody`. → RED → 구현 → GREEN → 빌드 → 수동 확인(평범한 JSON 요청의 Raw·Summary, `curl -x 127.0.0.1:19090 https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8` 같은 공개 HLS 예시의 M3U8 탭 스크린샷 — 복호화 안 되면 SSL Proxying 목록에 그 호스트를 넣는 대신 http 예시나 Map Local 없이 평문 예시를 쓰고, 안 되면 그 사실을 보고) → **커밋** `feat(detail): Raw·Summary·M3U8 탭`

### Task 7: HAR·CSV Export (Kit)

**Files:** Create `Packages/EyeProxyKit/Sources/EyeProxyKit/Export/FlowExport.swift`; Test `FlowExportTests.swift`.

**Interfaces:**
- Produces(스펙 §8.1): `public struct ExportItem: Sendable { flow: Flow; number: Int; comment: String?; highlight: FlowHighlight?; client: String? }`, `FlowExport.har(_ items: [ExportItem], creator: String = "Prog", version: String) -> Data`, `FlowExport.csv(_ items: [ExportItem]) -> String`. HAR 매핑은 스펙 §8.2 그대로(`_prog` 확장, 바이너리 base64, 응답 없음 = status 0 + `_prog.error`, 미완료 = time 0 + `_prog.incomplete`). 날짜 ISO 8601 밀리초 UTC. 도구 표시는 `ToolMark`(기존) raw 값 배열.
- JSON 키 순서가 안정적이도록 `JSONEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]`(CLI diff 친화, 빌더가 다르게 정하면 이유를 리포트에).
- [ ] Step 1 테스트: `harHasLog12ShapeAndProgExtension`(필수 키 존재·값), `harEncodesBinaryAsBase64AndTextAsIs`, `harMarksFailedAndIncompleteFlows`, `csvHasHeaderAndStableNumbers`(빈 번호 그대로), `csvEscapesCommasQuotesAndNewlines`. → RED → 구현 → GREEN → **커밋** `feat(export): HAR 1.2·CSV 내보내기 API`

### Task 8: HAR 가져오기 (Kit)

**Files:** Create `Packages/EyeProxyKit/Sources/EyeProxyKit/Export/FlowImport.swift`; Test `FlowImportTests.swift`.

**Interfaces:**
- Produces: `public struct ImportedFlow: Sendable { flow: Flow; number: Int?; comment: String?; highlight: FlowHighlight?; client: String? }`, `FlowImport.har(_ data: Data) throws -> [ImportedFlow]`(잘못된 JSON·`log.entries` 없음 → `FlowImportError.invalidHAR(String)`). URL에서 scheme·host·port·path 복원, `_prog` 있으면 `isTunnel`·`isDecrypted`·도구 표시(annotations `.tool`)·원래/전송 URL 복원. 번호 겹침 처리는 앱(`replace`)이 아니라 여기서: 겹치면 전부 nil로.
- [ ] Step 1 테스트: `harRoundTripPreservesBinaryAndUTF8Bodies`(Task 7 export → import, 바이트 동일), `harRoundTripPreservesNumbersCommentsHighlightsTools`, `foreignHARWithoutProgExtensionImportsWithDefaults`(Chrome DevTools 모양 최소 픽스처), `duplicateNumbersAreDropped`, `invalidHARThrows`. → RED → 구현 → GREEN → **커밋** `feat(export): HAR 가져오기 API`

### Task 9: Export·Import UI (앱)

**Files:** Modify `EyeProxy/Commands/ToolsCommands.swift`(FlowMenu), `FlowListView.swift`(우클릭), `EyeProxy/AppModel.swift`(+ `AppModel+Export.swift` 새 파일 권장), `EyeProxy/Info.plist`(`.har` 문서 타입 import — UTI `public.json` 계열 또는 `com.tv.eyeproxy.har` import 선언; 빌더 판단).

**Interfaces:**
- Consumes: Task 7·8. Produces: `AppModel.exportItems(scope: Set<FlowID>?) -> [ExportItem]`(선택 있으면 선택, 없으면 보이는 행; 번호·코멘트·Highlight·클라이언트 이름 채움 — 클라이언트는 목록 Client 열과 같은 문자열), `exportHAR()`, `exportCSV()`, `exportSession()`, `saveRequests()`(선택만, 없으면 비활성).
- 메뉴(스펙 §8.4): Flow ▸ `Save Requests…` / `Export ▸ as HAR (HTTP Archive)… · as CSV… · as Prog Session…`, 우클릭에 같은 Export 하위 메뉴. 기본 파일 이름 `Prog-<yyyyMMdd-HHmmss>.har|.csv|.eyeproxy`.
- 세션 열기(⌘O)가 `.eyeproxy`와 `.har`를 모두 받음. HAR이면 `FlowImport.har` → `session.replace(flows:…, numbers:)` + 코멘트·Highlight·`processes`는 비움(클라이언트 문자열은 이번엔 복원하지 않음 — 다음 묶음에서 기기 앱 귀속과 함께; 스펙 반목표는 "Highlight·코멘트·도구 표시" 보존). 실패는 `systemError`.
- [ ] Step 1 구현 → 빌드 → 수동 확인은 모달이 필요해 **하지 않는다** → 수동 점검표 항목으로 리포트에 적는다 → **커밋** `feat(export): Flow ▸ Export·Save Requests와 HAR 열기`

### Task 10: 상태 막대 눈 아이콘 + 빨간 점

**Files:** Create `Design/MenuBar-Eyes-Open.svg`, `MenuBar-Eyes-Closed.svg`, `MenuBar-Eyes-Stopped.svg`(목업 `menubar-toolbar-v2.html` A안의 22×18 viewBox 도형, 루트에 width/height 없음); Modify `scripts/make-icons.sh`(새 3종 → `MenuBarEyesOpen/Closed/Stopped.imageset`, template; 옛 `MenuBarFrog*` 생성 제거), 카탈로그(옛 MenuBarFrog* imageset 삭제), `EyeProxy/AppModel.swift`(`statusIconName` → `statusIcon: StatusIcon`), `EyeProxy/EyeProxyApp.swift`(MenuBarExtra 라벨), 새 `EyeProxy/Views/StatusBar/StatusIconImage.swift`.

**Interfaces:**
- Produces: `struct StatusIcon: Equatable { enum Eyes { case open, closed, stopped }; var eyes: Eyes; var needsAttention: Bool }`, `AppModel.statusIcon`(eyes: 서버 실행 중이면 기록 여부로 open/closed, 아니면 stopped; attention: 멈춘 Breakpoint ≥ 1 || `serverState == .failed` || `rules.loadWarnings` 비어 있지 않음). `StatusIconImage.make(_ icon: StatusIcon) -> NSImage`: attention 없으면 에셋 그대로(template), 있으면 에셋을 현재 막대 외관에 맞는 단색(라벨 색)으로 그리고 오른쪽 위에 `NSColor.systemRed` 원(지름 약 6pt)을 합성한 비템플릿 이미지. 막대 외관(라이트/다크) 변화에 다시 그려지게.
- 접근성 레이블: "Prog — 기록 중/일시정지/서버 중지[, 확인 필요]".
- [ ] Step 1 SVG·스크립트·카탈로그 → 스크립트 실행(크기 검증 통과) → Step 2 앱 구현 → 빌드 → Step 3 확인: 실제 막대 표시는 메뉴 막대가 붐비면 안 보일 수 있으니 `StatusIconImage.make`의 네 조합을 PNG로 렌더해(라이트·다크 배경) 스크린샷 파일로 첨부 → **커밋** `feat(statusbar): 상태 막대 아이콘을 눈 + 빨간 점으로`

### Task 11: 툴바 여백·숨김 토글

**Files:** Modify `EyeProxy/Views/Toolbar/MainToolbar.swift`.

- 스펙 §10: 버튼 묶음 안쪽 여백·버튼 사이 간격, 상태 캡슐 좌우 14pt·위아래 6pt. "숨김 포함" 체크박스 → `Toggle(isOn: $model.filter.includeHidden) { Label("숨긴 요청 보기", systemImage: includeHidden ? "eye" : "eye.slash") }`(버튼 스타일 토글, 켜면 선택 강조), SSL 자물쇠와 같은 `ToolbarItemGroup`에.
- [ ] 구현 → 빌드 → 수동 확인(툴바 스크린샷 라이트·다크, 숨김 토글 켬/끔) → **커밋** `feat(ui): 툴바 캡슐 여백과 숨김 보기 심볼 토글`

### Task 12: 툴팁 전수

**Files:** Modify `EyeProxy/Commands/*.swift`, `EyeProxy/Views/Toolbar/MainToolbar.swift`, `EyeProxy/Views/StatusBar/StatusMenu.swift`, `EyeProxy/Views/FlowList/FlowListView.swift`(우클릭), `EyeProxy/Views/Certificate/*.swift`(버튼), `EyeProxy/EyeProxyApp.swift`(File·View 사용자 항목).

- 스펙 §11: 모든 사용자 정의 메뉴 항목·툴바 컨트롤·상태 메뉴 항목·우클릭 항목·Certificate 창 버튼에 `.help("…")` 한국어 한 줄(무엇을 하는가 + 단축키 괄호). 이미 있는 툴팁은 문구만 통일.
- 메뉴 항목에서 `.help`가 실제 툴팁으로 뜨는지 디버그 빌드에서 한 항목만 호버해 확인(System Events로 메뉴를 열고 마우스를 올린 뒤 스크린샷; 모달 아님). 안 뜨면 그대로 두고 리포트에 "메뉴 툴팁 미표시"라고 적는다 — 대체 구현 금지(스펙 §11).
- [ ] 구현 → 빌드 → 확인 → **커밋** `feat(ui): 메뉴·툴바·상태 메뉴 한 줄 툴팁`

### Task 13: 문서

**Files:** Modify `README.md`(목록 편의·Export·상세 탭·상태 막대 아이콘·툴바 절, 알려진 제한), Create `docs/superpowers/plans/2026-11-09-prog-list-detail-export-handover.md`(수동 점검표: 확인됨/미확인 열, Export·HAR 열기·Delete All 확인 알림·메뉴 툴팁·실제 막대 아이콘 표시 등 모달·실기기 항목, 보류 항목 요약, 다음 묶음(세션 탭·호스트 그룹 탭) 메모).
- [ ] 작성 → `grep -rn "/Users/" README.md docs/superpowers/plans/2026-11-09-prog-list-detail-export-handover.md` 없음 확인 → **커밋** `docs: 목록·상세 편의·Export 설명과 수동 점검표`
