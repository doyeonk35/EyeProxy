# 메인 화면 Proxyman화 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기록 버튼·정렬을 고치고, 필터 막대·사이드바·하단 바·상세 탭·설정 창을 Proxyman과 같은 배치·이름·동작으로 바꾼다.

**Architecture:** 규칙 판정(필터 규칙 매칭, 사이드바 트리·경로 트리, 하단 바 배지 목록, 처리량 계산)은 `EyeProxyKit` 순수 코드로 두고 Swift Testing으로 고정한다. 앱은 보기·단축키만 붙인다.

**Tech Stack:** Swift 6, SwiftUI(macOS 15+), AppKit. 새 패키지 없음.

**Spec:** `docs/superpowers/specs/2026-11-10-prog-proxyman-main-view-design.md`

## Global Constraints

- Swift 6 strict concurrency, macOS 15+. 외부 패키지는 CLAUDE.md 허용 목록만. 모듈 방향 `EyeProxy` → `EyeProxyKit` → `EyeProxyCore`.
- 번들 ID·`eyeproxy.*` 설정 키·`.eyeproxy`·기존 고정(pinnedHosts) 설정 그대로 읽기.
- 구조 이름은 Proxyman 영어(스펙 §8), 툴팁·빈 화면·오류는 한국어 한 줄(`.help`).
- 공개 레포: 커밋 파일에 회사 내부 도메인·로컬 사용자 경로 금지(픽스처는 `example.com`).
- 각 Task 끝: `swift test --package-path Packages/EyeProxyKit`(Core를 건드렸으면 Core도), 앱 변경이면 `xcodegen generate && xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates`. `Package.resolved` 변경은 되돌린다.
- 커밋 `<type>(<scope>): <한국어 요약>`.
- 수동 확인: 화면 잠금 확인 후 자기 Debug 빌드만 포트 19090/19091, `-SUEnableAutomaticChecks NO`. 모달 금지, 시스템 프록시·키체인·외관 변경 금지, 자기 PID만 종료, 사용자 클립보드 읽기·출력 금지. 키·클릭은 자기 앱이 맨 앞일 때만. 사용자가 띄운 `/Applications/Prog.app`·Proxyman은 건드리지 않는다.

## Review Focus

1. 본문 키 규칙(Response Body Contains)으로 요청 5,000개를 거를 때 입력이 멈추지 않는다 → Task 2 `bodyRuleMatchingRunsOffMain`(Kit 측정 테스트)·Task 3 수동 확인.
2. 필터 막대 단축키(⌘N·⇧⌘N·⌘B·⌘↑·⌘↓)가 막대 밖에서는 아무 일도 하지 않고, 기존 단축키(⌘R·⌘K·⌫·⌘1~6·⇧⌘X·⌘0·⌘↩·⌘F 상세 찾기)를 가로채지 않는다 → Task 3 수동 확인.
3. 사이드바를 바꿔도 기존 고정 도메인이 Pinned에 그대로 나오고, 기기·앱·도메인 개수가 목록과 맞는다 → Task 4 `treeKeepsPinnedAndCountsMatch`.
4. 정렬을 내림차순으로 바꿔도 Delete 뒤 선택 이동("아래 행, 없으면 위")·Auto Select·Export 순서(번호 오름차순)가 그대로다 → Task 1 수동 확인·기존 테스트.
5. 하단 바 배지는 켜진 도구만 보이고 누르면 맞는 창이 열린다 → Task 5 `activeToolBadgesFollowSwitches`.

---

### Task 1: 기록 버튼·정렬·툴바 상태 캡슐 (앱)

**Files:** `EyeProxy/Views/Toolbar/MainToolbar.swift`, `EyeProxy/Views/StatusBar/StatusMenu.swift`(같은 아이콘이 있으면), `EyeProxy/AppModel.swift`(`sortOrder` 기본), Sparkle 업데이트 확인 상태(새 버전 수 노출이 가능한 만큼 — 빌더 판단, 안 되면 "업데이트 있음" 배지).
- 기록 중 `pause.fill`, 멈춤 `play.fill`(스펙 §2). `sortOrder` 기본 `KeyPathComparator(\.number, order: .reverse)`(스펙 §3).
- 상태 캡슐 `● Prog | Listening on <IP>:<port>`(+ ` | Pause`), 업데이트 배지(스펙 §10). 목록 상태 점 색(초록·주황·빨강)과 Active 행 `-` 표시 확인(스펙 §10).
- [ ] 구현 → 빌드 → 수동 확인(기록 켬/끔 아이콘·캡슐 문구, 새 요청이 맨 위, Delete 뒤 선택 이동) → **커밋** `fix(ui): 기록 버튼은 누르면 할 일을, 목록은 최신이 위로`

### Task 2: 필터 규칙 모델·매칭 (Kit)

**Files:** Create `Packages/EyeProxyKit/Sources/EyeProxyKit/Filter/FilterRule.swift`; Modify `FlowFilter.swift`; Test `FilterRuleTests.swift`.
**Interfaces (Produces):**
- `public enum FilterKey: String, CaseIterable, Codable, Sendable` — 스펙 §4 키 16개(rawValue = 메뉴 표시 영어).
- `public enum FilterMatch: String, CaseIterable, Codable, Sendable` — 스펙 §4 매칭 12개. `isNumericOnly`(`<`, `>=`).
- `public struct FilterRule: Codable, Equatable, Sendable, Identifiable { id: UUID; isEnabled: Bool; key: FilterKey; match: FilterMatch; text: String }`, `func matches(_ row: FilterSubject) -> Bool`.
- `public struct FilterSubject: Sendable` — 흐름에서 키별 문자열·숫자를 꺼내는 가벼운 뷰(본문은 필요할 때만 UTF-8 디코드, 압축은 BodyDecoder). `init(flow:number:comment:highlight:client:)`.
- `FlowFilter.rules: [FilterRule]`(최대 10), `FlowFilter.combineWithOr: Bool = false`; `matches`는 켜진 규칙만, 빈 검색어 규칙은 통과. 기존 `text` 필드는 제거하고 저장된 값은 URL·Contains 규칙 하나로 옮긴다.
- `FilterRule.needsBody: Bool`(Request/Response Body 키) — 앱이 메인 밖 계산 여부를 정한다.
- Wildcard는 `*`·`?`, Regex는 `NSRegularExpression`(잘못된 정규식 = 그 규칙 무시하고 표시용 `isInvalid`).
- [ ] Step 1 테스트: `everyKeyExtractsExpectedValue`, `everyMatchModeBehaves`(Contains~Not Match Regex, 대소문자 무시), `numericMatchesOnlyNumericKeys`, `multipleRulesCombineWithAndOr`, `disabledAndEmptyRulesPass`, `invalidRegexIsIgnoredAndFlagged`, `legacyTextMigratesToURLContainsRule`, `bodyRuleMatchingRunsOffMain`(5,000개 흐름·1 MB 본문 혼합으로 `Task.detached` 계산이 끝나는지·결과 정확성). → RED → 구현 → GREEN → **커밋** `feat(filter): Proxyman식 필터 규칙(키·매칭·여러 개)`

### Task 3: 필터 막대 UI + 툴바 검색칸 제거 (앱)

**Files:** Create `EyeProxy/Views/FlowList/FilterRulesBar.swift`; Modify `MainWindow.swift`(`.searchable` 제거), `FlowListView.swift`, `EyeProxy/Commands/FindCommands.swift`(목록 쪽 ⌘F → 필터 막대), `AppModel.swift`(규칙 저장·디바운스·본문 규칙 백그라운드 매칭), `AppSettings`(마지막 규칙 저장 키 `eyeproxy.filterRules`).
- 스펙 §4 배치·단축키 안내 줄, 체크박스·키 메뉴·매칭 메뉴(숫자 전용은 숫자 키에서만 활성)·검색칸·`−`/`+`. 단축키는 막대 포커스일 때만.
- `visibleFlows` 계산: 본문 규칙이 있으면 디바운스 뒤 `Task.detached`로 계산하고 최신 입력만 반영(이전 작업 취소).
- [ ] 구현 → 빌드 → 수동 확인(규칙 2개 AND, 각 매칭 몇 개, Esc 숨김 뒤에도 적용·하단 Filter 강조(Task 5 전이면 생략), 5,000개 요청에서 Response Body 검색 입력 반응, 기존 단축키 회귀 없음) → **커밋** `feat(ui): 목록 필터 막대(⌘F)로 검색칸 대체`

### Task 4: 사이드바 하이어라키 (Kit + 앱)

**Files:** Modify `Packages/EyeProxyKit/Sources/EyeProxyKit/SidebarTree.swift`(+ `PathNode`), `EyeProxy/Views/Sidebar/SidebarView.swift`, `FlowFilter`(경로 접두 조건 `pathPrefix`), Test `SidebarTreeTests.swift`.
**Interfaces (Produces):**
- `SidebarTree { pinned: [HostNode]; remoteDevices: [DeviceNode](원격만, 도메인 자식); apps: [AppNode](이 Mac); domains: [HostNode] }`.
- `PathNode { segment: String; fullPath: String; count: Int; children: [PathNode] }`, `SidebarTree.pathTree(for host: String, flows:) -> [PathNode]`(필요할 때 계산, 깊이 상한 빌더 판단).
- `SidebarItem`에 `.path(host:prefix:)` 추가.
- 사이드바 필터 칸(⌘⇧F, 사이드바 포커스 때만)·`+`(Pinned에 도메인 추가 시트 — 모달, 수동 점검표).
- [ ] Step 1 테스트: `treeSplitsRemoteDevicesAppsAndDomains`, `treeKeepsPinnedAndCountsMatch`, `pathTreeGroupsSegmentsWithCounts`, `pathPrefixFilterMatchesOnlyUnderPrefix`, `sidebarFilterMatchesNamesCaseInsensitive`. → RED → 구현 → GREEN → 빌드 → 수동 확인(스크린샷: Favorites/Pinned, Remote devices, All/Apps/Domains, 경로 펼침, 사이드바 필터) → **커밋** `feat(sidebar): Favorites·Remote devices·All 하이어라키와 경로 트리`

### Task 5: 하단 바 (Kit + 앱)

**Files:** Create `Packages/EyeProxyKit/Sources/EyeProxyKit/StatusBarModel.swift`(이름 빌더 판단), `EyeProxy/Views/BottomBar/BottomBar.swift`; Modify `MainWindow.swift`, `AppModel.swift`.
**Interfaces (Produces):**
- `ActiveToolBadge: CaseIterable` (breakpoint, mapLocal, mapRemote, blockList, allowList, networkConditions, noCaching, proxyOverridden, sslProxyingOff) + `static func active(switches:proxyOverridden:sslEnabled:) -> [ActiveToolBadge]` + 열 창 id(`tool-breakpoint-rules`, `tool-map-local`, `tool-map-remote`, `tool-block`, `tool-allow`, `tool-network`, No Caching은 Tools 메뉴 동작과 같은 곳, Proxy Overridden·SSL은 `devices` 창 해당 섹션).
- `Throughput` — 최근 1초 바이트 합(요청·응답 본문 크기)으로 ↑/↓ B/s, 순수 계산 함수 + 테스트. 메모리는 앱에서 `task_info`.
- 왼쪽 Clear·Filter·Auto Select, 가운데 `N/M rows selected`, 오른쪽 메모리·속도·배지(스펙 §6).
- [ ] Step 1 테스트: `activeToolBadgesFollowSwitches`, `badgeOpensMatchingWindow`, `throughputSumsLastSecond`. → RED → 구현 → GREEN → 빌드 → 수동 확인(배지 켬/끔, 배지 클릭 → 창, Filter 버튼 강조, rows selected 숫자) → **커밋** `feat(ui): Proxyman식 하단 바 — 켜진 도구 배지·처리량`

### Task 6: 상세 머리·탭 재배치 (앱)

**Files:** `EyeProxy/Views/Detail/FlowHeaderBar.swift`, `FlowDetailView.swift`(MessagePane 탭), `BodyView.swift`(Tree 모드 → Treeview 탭), `SummaryView.swift`(탭으로), `KeyValueTable.swift`(머리 줄 `Key | Value`), 새 `JSONTabView.swift`.
- 스펙 §7: 머리 배치, 요청 탭 `Header · Query · Body · (Form) · (Cookies) · (Auth) · Raw │ Summary · Treeview · M3U8 · JSON`, 응답 탭 `Header · Body · (Set-Cookie) · Raw │ Treeview · M3U8 · JSON`. 조건부 탭 규칙(Form = form-urlencoded/multipart 본문, Auth = Authorization 헤더, Set-Cookie = 응답 Set-Cookie). JSON 탭 = JSON으로 파싱되면 Pretty + ⌘F, 아니면 "JSON이 아닙니다".
- 기존 ⌘F 라우팅(본문 찾기·표 거르기·트리 찾기)이 새 탭에서도 그대로.
- 스펙 §10: URL 색(스킴 회색·호스트 파랑·경로 초록)과 긴 URL일 때 알약 세로 배치, 표 거르기 `⋯` 메뉴(Case Sensitive/Insensitive, Text/Regular Expression)와 탭 줄 `≡` 버튼, 복호화 안 한 터널을 고르면 응답 패널에 `HTTPS Response` 안내 + `Enable only this domain` / `Enable all domains from "<앱>"`(→ `AppModel.enableSSLProxying(for:)`, 앱의 모든 호스트는 새 `enableSSLProxying(forHostsOfApp:)`).
- [ ] 구현 → 빌드 → 수동 확인(스크린샷: 머리·URL 색, 요청·응답 탭 세트, Treeview 탭 모두 펼치기·찾기, Summary 탭, JSON 탭, 조건부 탭 유무, CONNECT 행 HTTPS 안내와 버튼, 표 거르기 정규식) → **커밋** `feat(detail): Proxyman식 머리·탭 구성`

### Task 8: 설정 창 — General·Appearance (앱 + Kit 설정)

**Files:** `EyeProxy/Views/Settings/SettingsView.swift`(탭 구성 General · Appearance · Tools · SSL Proxying · Bypass · Advanced), `Packages/EyeProxyKit/Sources/EyeProxyKit/AppSettings.swift`(새 키는 `eyeproxy.` 접두), 해당 설정을 쓰는 보기(목록 줄무늬·글꼴·말줄임, 본문 글꼴 크기·탭 폭·공백 표시), `AppModel`(실행 시 Auto Override·Auto Start Recording).
- 스펙 §11 General·Appearance 표 그대로(이름·기본값). 기존 설정 키(외관·포트·상태 막대 아이콘·줄바꿈·레이아웃)는 키를 바꾸지 않고 새 자리로 옮긴다. 루트 인증서 카드는 Certificate 창과 같은 상태를 보여 주고 버튼은 그 창·CA 초기화로.
- [ ] Step 1 테스트(AppSettingsTests): `newSettingsHaveSpecDefaults`, `existingKeysAreReadUnchanged`, `restoreAppearanceDefaultsResetsOnlyAppearance`. → RED → 구현 → GREEN → 빌드 → 수동 확인(설정 창 각 탭 스크린샷, 글꼴 크기·줄무늬·말줄임·공백 표시가 화면에 반영, Auto Start Recording 끄고 재실행 → 멈춤으로 시작; Auto Override는 시스템 프록시를 바꾸므로 자동 확인 금지 → 수동 점검표) → **커밋** `feat(settings): Proxyman식 General·Appearance 설정`

### Task 9: 설정 창 — Tools·Advanced (앱 + Kit 설정)

**Files:** `SettingsView.swift`, `AppSettings.swift`, 사용처(`CurlExport` `--proxy`, Compose·Repeat 타임아웃, Export 뒤 Finder, Sparkle 자동 확인, 목록 Time 열 24시간·전체 형식, 종료 확인, 하단 바 리소스 표시, 시뮬레이터 Apple 요청 숨김, Stay On Top, 헤더 값 공백 `·`).
- 스펙 §11 Tools·Advanced 표 그대로. "Restore to previous proxy"는 켜진 채 비활성 + 툴팁. "Hide Unnecessary Apple Requests from iOS Simulators"는 Kit 순수 판정(`SimulatorNoise.isAppleNoise(host:clientIsSimulator:)` 이름은 빌더 판단)으로 `.hidden` 주석을 단다(눈 토글로 보임).
- [ ] Step 1 테스트: `curlAddsProxyFlagWhenEnabled`, `timeColumnFormatsFollowSettings`, `appleNoiseHostsDetectedOnlyForSimulators`. → RED → 구현 → GREEN → 빌드 → 수동 확인(각 항목 효과; 종료 확인 알림은 모달 → 수동 점검표) → **커밋** `feat(settings): Proxyman식 Tools·Advanced 설정`

### Task 10: 문서

**Files:** `README.md`(메인 화면 절 재작성: 필터 막대·사이드바·하단 바·탭·설정 창, 단축키 표), 핸드오버 `docs/superpowers/plans/2026-11-10-prog-proxyman-main-view-handover.md`(수동 점검표, 2단계 메모: JSON Path·jq·미니맵, `+` 탭, Custom Filters, Command Palette, Saved, 기기 앱별 묶기).
- [ ] 작성 → `/Users/`·내부 도메인 grep 없음 → **커밋** `docs: Proxyman식 메인 화면 설명과 점검표`
