# 요청·응답 찾기(⌘F)·필터·트리 모두 펼치기 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 상세 창의 요청·응답 패널에서 ⌘F로 찾기·거르기를 하고, 응답 JSON 트리를 버튼 하나로 모두 펼치고 접는다.

**Architecture:** 트리 검색·거르기 규칙은 `EyeProxyKit`의 순수 함수로 두고 Swift Testing으로 고정한다. 앱은 막대·버튼·단축키만 붙인다. 텍스트 본문 찾기는 AppKit `NSTextView`의 내장 찾기 막대(`NSTextFinder`)를 쓴다.

**Tech Stack:** Swift 6, SwiftUI(macOS 15+), AppKit(NSTextView/NSTextFinder). 새 패키지 없음.

**Spec:** 이 문서의 "설계" 절(사용자 요청 2026-11-10 + Proxyman 문서 조사). 사용자 요청: "배포 전에 ⌘F 기능도 같이 추가하자. 응답 treeview에서 모든 tree 한번에 다 열어주는 버튼도 하나 추가하자. 요청/응답 섹션에서 필터랑 find 찾기 기능 추가하는 것만. 상세 동작은 Proxyman 보고."

## 설계

### Proxyman 동작(문서 확인, docs.proxyman.com)
- 목록에서 ⌘F = 필터 막대 열기, Esc = 닫기.
- Header·Query·Auth·Form 보기에서 ⌘F(또는 우클릭 ▸ Show Filter) = 그 표를 거르는 필터.
- Body 탭에서 ⌘F = 본문 검색(정규식 지원, 다음 일치로 이동).
- Treeview 탭에서 ⌘F = 모드 선택(Search·Filter·JSON Path·jq). **Search**는 키·값에 검색어가 든 노드를 강조, **Filter**는 키·값에 검색어가 든 노드만 보여 준다.

### Prog 동작(이번 범위)
1. **⌘F는 포커스를 따른다.** 상세 창의 요청·응답 패널 안(표·본문·트리·Raw)에 포커스가 있으면 그 보기의 찾기/거르기를 연다. 목록·사이드바 등 그 밖이면 지금처럼 툴바 검색칸(목록 거르기)으로 간다. Esc는 열린 막대를 닫고 원래 상태로 되돌린다.
2. **헤더·쿼리·쿠키 표 거르기**: ⌘F → 표 위에 거르기 칸. 이름 또는 값에 검색어가 든 행만(대소문자 무시). "N / 전체 M" 표시. 거르는 중에도 우클릭 복사는 그대로. 탭·흐름을 바꾸면 닫힌다.
3. **본문(Pretty·Raw 모드)·Raw 탭 찾기**: ⌘F → `NSTextView` 내장 찾기 막대(일치 모두 강조, 다음/이전 ⌘G/⇧⌘G·Enter/⇧Enter, 일치 개수, 대소문자 무시·포함/단어 옵션). 정규식은 내장 막대가 지원하지 않아 이번엔 넣지 않는다(아래 "범위 밖").
4. **JSON 트리 찾기**: ⌘F → 트리 위 막대: 검색칸 + 모드 `Search | Filter`(세그먼트) + (Search일 때) 이전/다음 버튼과 "i / N".
   - Search: 키·값(미리보기)에 검색어가 든 노드를 강조하고, 그 조상들을 펼쳐 보이게 하고, 현재 일치로 스크롤. Enter/⌘G 다음, ⇧Enter/⇧⌘G 이전.
   - Filter: 일치 노드와 그 조상만 남긴다(일치한 컨테이너는 자식 전체를 그대로 둔다). 남은 노드는 모두 펼친다.
5. **트리 모두 펼치기/접기**: Tree 모드일 때 본문 막대(Pretty/Tree/Raw 피커 옆)에 버튼 두 개 — "모두 펼치기"(`arrow.down.right.and.arrow.up.left`류 심볼, 빌더 판단)·"모두 접기". 툴팁 한국어 한 줄.
6. **메뉴**: Edit ▸ Find ▸ Find…(⌘F)·Find Next(⌘G)·Find Previous(⇧⌘G)가 위 라우팅을 따른다(SwiftUI가 이미 넣는 항목이 있으면 그것을 쓰고, 없으면 `CommandGroup`으로 넣는다 — 빌더 판단, 기존 단축키와 겹치지 않게).

### 범위 밖(YAGNI, 다음에 사용자 요청 시)
- 본문 찾기 정규식, JSON Path·jq 모드, 목록 2차 필터(키·매칭 방식 메뉴), 필터 여러 개(⌘N), M3U8·요약 찾기.

## Global Constraints

- Swift 6 strict concurrency, macOS 15+. 외부 패키지는 CLAUDE.md 허용 목록만(새 패키지 금지). 모듈 방향 `EyeProxy` → `EyeProxyKit` → `EyeProxyCore`.
- 표시 이름 Prog. 번들 ID·`eyeproxy.*` 설정 키·`.eyeproxy` 그대로.
- UI 문자열 한국어, 메뉴 항목 이름은 macOS 표준 영어(Find…), 새 버튼·막대 컨트롤에는 한국어 한 줄 툴팁(`.help`).
- 공개 레포: 커밋 파일에 회사 내부 도메인·로컬 사용자 경로 금지. 테스트 픽스처는 `example.com` 류.
- 각 Task 끝: `swift test --package-path Packages/EyeProxyKit`, 앱을 건드렸으면 `xcodegen generate && xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates`. `Package.resolved` 변경은 되돌린다.
- 커밋 메시지 `<type>(<scope>): <한국어 요약>`.
- 수동 확인: 화면 잠금 확인 후 자기 Debug 빌드만 포트 19090(`-eyeproxy.port '<integer>19090</integer>'`). 모달 금지, 시스템 프록시·키체인·외관 설정 변경 금지, 자기 PID만 종료. 키·클릭은 자기 앱이 맨 앞일 때만.

## Review Focus

1. 목록·사이드바에 포커스가 있을 때 ⌘F가 여전히 툴바 검색칸으로 간다(회귀 금지) → Task 3 수동 확인.
2. 검색칸·코멘트 시트·Compose 같은 텍스트 입력 중 ⌘G·Esc가 엉뚱한 막대를 열거나 닫지 않는다 → Task 3 수동 확인.
3. 깊게 중첩된(수백 단계)·큰(수천 노드) JSON에서 거르기·모두 펼치기가 스택을 넘기거나 멈추지 않는다 → Task 1 `deepTreeSearchDoesNotRecurse`.
4. 흐름·탭을 바꾸면 이전 흐름의 검색어·강조가 남지 않는다 → Task 2·3 수동 확인.
5. 대소문자·한글 검색어(예: "이름")가 키·값 모두에서 맞는다 → Task 1 `searchIsCaseInsensitiveAndMatchesKoreanKeysAndValues`.

---

### Task 1: 트리 검색·거르기 규칙 (Kit)

**Files:** Create `Packages/EyeProxyKit/Sources/EyeProxyKit/Text/JSONTreeSearch.swift`; Test `Packages/EyeProxyKit/Tests/EyeProxyKitTests/JSONTreeSearchTests.swift`.

**Interfaces:**
- Consumes: `JSONTreeNode { id: Int, key: String, preview: String, children: [JSONTreeNode]? }`(기존).
- Produces:
  - `JSONTreeSearch.matches(in nodes: [JSONTreeNode], query: String) -> [Int]` — 키나 미리보기에 검색어가 든 노드 id를 **화면 순서(전위 순회)**로. 빈 검색어 → `[]`. 대소문자 무시(`localizedStandardContains` 또는 `range(of:options:.caseInsensitive)`).
  - `JSONTreeSearch.ancestors(of ids: Set<Int>, in nodes: [JSONTreeNode]) -> Set<Int>` — 그 노드들을 보이게 하려면 펼쳐야 할 조상 id.
  - `JSONTreeSearch.filter(_ nodes: [JSONTreeNode], query: String) -> [JSONTreeNode]` — 일치 노드와 조상만 남김, 일치한 컨테이너는 자식 전체 유지. 빈 검색어 → 원본 그대로.
  - `JSONTreeSearch.containerIDs(in nodes: [JSONTreeNode]) -> Set<Int>` — 자식이 있는 모든 노드 id(모두 펼치기용).
  - 모두 재귀 없이(명시적 스택) — `JSONTreeNode.parse`와 같은 이유(깊이 512).
- [ ] Step 1 테스트: `matchesReturnsPreorderIDsForKeysAndValues`, `searchIsCaseInsensitiveAndMatchesKoreanKeysAndValues`, `ancestorsCoverEveryLevel`, `filterKeepsAncestorsAndWholeMatchedContainer`, `emptyQueryIsNoOp`, `containerIDsListsEveryNodeWithChildren`, `deepTreeSearchDoesNotRecurse`(깊이 500 이상 중첩 JSON을 `JSONTreeNode.parse`로 만들어 네 함수 모두 호출). → RED → 구현 → GREEN → **커밋** `feat(detail): JSON 트리 검색·거르기 규칙`

### Task 2: JSON 트리 — 모두 펼치기/접기 + 찾기 막대 (앱)

**Files:** Modify `EyeProxy/Views/Detail/JSONTreeView.swift`, `EyeProxy/Views/Detail/BodyView.swift`.

**Interfaces:** Consumes Task 1.
- `OutlineGroup`은 펼침 상태를 밖에서 못 다루므로, 펼친 id 집합(`Set<Int>`)을 상태로 갖는 재귀 `DisclosureGroup`(또는 평탄화한 행 목록 + 들여쓰기 — 큰 트리 성능이 나은 쪽, 빌더 판단)으로 바꾼다. 처음 상태는 지금과 같게(모두 접힘이면 접힘).
- BodyView 막대: Tree 모드일 때 "모두 펼치기"·"모두 접기" 버튼(`.help` 한국어 한 줄).
- 찾기 막대(설계 4): 검색칸, `Search | Filter`, 이전/다음, "i / N", 닫기(Esc). Search는 현재 일치 행 강조(배경색) + 나머지 일치 옅은 강조 + 조상 펼침 + 스크롤(`ScrollViewReader`). Filter는 `JSONTreeSearch.filter` 결과를 모두 펼쳐 보여 준다. 막대를 닫으면 원래 트리·펼침 상태로.
- 이 Task에서는 막대를 여는 버튼(돋보기)을 막대 옆에 두고, ⌘F 연결은 Task 3에서 한다.
- [ ] 구현 → 빌드 → 수동 확인(중첩 JSON 응답: 모두 펼치기/접기, Search 이동, Filter 결과 스크린샷 다크) → **커밋** `feat(detail): JSON 트리 모두 펼치기·찾기·거르기`

### Task 3: ⌘F 라우팅 + 표 거르기 + 본문 찾기 막대 (앱)

**Files:** Modify `EyeProxy/Views/Detail/KeyValueTable.swift`, `EyeProxy/Views/Detail/CodeTextView.swift`, `EyeProxy/Views/Detail/FlowDetailView.swift`, `EyeProxy/Views/Detail/JSONTreeView.swift`(⌘F 연결), `EyeProxy/EyeProxyApp.swift` 또는 `EyeProxy/Commands/*.swift`(Find 메뉴).

**Interfaces:**
- `CodeTextView`: `usesFindBar = true`, `isIncrementalSearchingEnabled = true`. 편집 가능 모드(Compose·Breakpoint)에서도 동작해도 된다.
- `KeyValueTable`: 거르기 칸(설계 2), `emptyTitle`과 별개로 "일치 없음" 표시.
- 라우팅(설계 1·6): 포커스된 보기가 찾기를 받는다 — 텍스트 뷰는 응답자 체인(`performTextFinderAction(_:)`), SwiftUI 보기(표·트리)는 focused value로 넘긴 동작. 목록 쪽에서는 지금처럼 툴바 검색칸. 구현 방법은 빌더 판단, 리포트에 적는다.
- [ ] 구현 → 빌드 → 수동 확인: 헤더 표 ⌘F 거르기, 본문 Pretty·Raw 탭 ⌘F·⌘G, 트리 ⌘F, 목록 포커스 ⌘F → 툴바 검색칸(회귀 없음), 검색칸 입력 중 Esc·⌘G 동작, 흐름 바꾸면 막대·강조 사라짐 → **커밋** `feat(detail): ⌘F로 요청·응답 찾기·거르기`

### Task 4: 문서

**Files:** Modify `README.md`(상세 탭 절에 찾기·거르기·모두 펼치기, 단축키 표, 알려진 제한: 본문 정규식·JSON Path 없음), 점검표 항목을 리포트·핸드오버(`docs/superpowers/plans/2026-11-10-prog-find-filter-handover.md`)에.
- [ ] 작성 → `/Users/`·내부 도메인 grep 없음 → **커밋** `docs: 요청·응답 찾기·거르기 설명`
