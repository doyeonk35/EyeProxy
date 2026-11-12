# Prog 세션 탭·Open Recent·기기 이름 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 한 창에 macOS 기본 창 탭을 여러 개 두어 탭마다 보기 상태를 따로 갖게 한다. 라이브 탭은 하나의 라이브 세션을 함께 보고, 파일(세션·HAR)은 새 탭에 열린다. File 메뉴는 Proxyman 6.3처럼 New Session ⌘T, Open Recent, Close All ⌥⌘W를 갖춘다. 원격 기기는 Bonjour로 알리는 이름을 찾아, 직접 붙인 이름이 없으면 IP 대신 보여 준다.

**Architecture:**
- 보기 상태와 그 계산(필터, 선택, 정렬, 사이드바, 파생 목록, 본문 일치)을 `AppModel`에서 새 `SessionTab`(앱 타깃, `@Observable`)으로 옮긴다.
- `AppModel`은 라이브 `SessionStore`와 전역 상태를 갖고, 탭 목록과 앞에 있는 탭(`activeTab`)을 관리한다.
- 메인 씬은 `Window` 대신 `WindowGroup(id: "main", for: UUID.self)`를 쓴다. 각 창은 탭 하나이고, `NSWindow` 탭 묶기로 한 창에 모인다.
- 메뉴, 툴바, 상태 막대 메뉴는 `model.activeTab`에 작용한다.

**Tech Stack:** Swift 6, SwiftUI + AppKit(`NSWindow` 탭, `NSDocumentController` 최근 문서), Network(`NWBrowser` Bonjour), swift-testing(Kit 테스트), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-12-prog-session-tabs-design.md`

## Global Constraints

- **패키지:** 외부 패키지는 허용 목록(swift-nio, swift-nio-ssl, swift-nio-extras, swift-certificates, swift-asn1, swift-crypto, Sparkle) 밖의 것을 추가하지 않는다.
- **모듈 방향:** 앱 → Kit → Core. 역방향 import 금지.
- **App Sandbox:** 끈다. entitlements는 빈 dict 그대로 둔다.
- **커밋 메시지:** `<type>(<scope>): <한국어 요약>`. 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`를 붙인다.
- **공개 레포:** 커밋할 파일에 사내 도메인이나 로컬 사용자 경로를 넣지 않는다. 테스트와 문서의 기기 예시는 문서용 주소(`192.0.2.x`)와 지어낸 이름("거실 Apple TV")만 쓴다. 실제 기기 이름, IP, MAC은 넣지 않는다.
- **플랫폼:** macOS 15+.
- **세션 파일:** 형식은 바꾸지 않는다(`index.json` version 1, 옛 파일도 열려야 한다).
- **메뉴 이름(영어, Proxyman 6.3과 같게):** `New Session`, `Open…`, `Open Recent`, `Clear Menu`, `Save Session…`, `Clear Session`, `Close`, `Close All`, `Select Next Tab`, `Select Previous Tab`, `Open as New Tab`.
- **단축키:**
  - New Session ⌘T
  - Open… ⌘O
  - Save Session… ⌘S
  - Clear Session ⌘K
  - Close ⌘W
  - Close All ⌥⌘W
  - Select Next Tab ⇧⌘]
  - Select Previous Tab ⇧⌘[
- **작업 위치:** 워크트리 브랜치 `feat/session-tabs`에서 작업한다. main에 직접 커밋하지 않는다.
- **빌드·테스트**
  - `swift test --package-path Packages/EyeProxyKit`
  - `xcodegen generate`
  - `xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates`
  - `swift test`가 `Package.resolved`를 바꾸면 `git checkout`으로 되돌린다.
- **UI 확인(에이전트):**
  - 직접 빌드한 Debug 앱만, 포트는 19090/19091을 쓰고(plist 정수), `-SUEnableAutomaticChecks NO`로 실행한다.
  - 입력은 그 앱의 PID가 맨 앞일 때만 보낸다. 끝낼 때도 그 PID만 종료한다.
  - 단계마다 화면 잠금을 먼저 확인한다.
  - 다음은 건드리지 않는다: `/Applications/Prog.app`, 사용자의 Prog-Debug.app, Proxyman, 시스템 프록시·키체인·CA 신뢰.
  - `com.tv.eyeproxy.debug` defaults를 바꿀 때는 미리 백업하고 끝나면 복원한다.
  - 스크린숏은 레포 밖 증거 폴더에 둔다.
  - 위 조건을 지킬 수 없는 단계는 사용자 점검표(Task 6)로 넘긴다. 로컬 네트워크 권한 창 같은 시스템 창에는 응답하지 않는다.

## Review Focus

1. **보이지 않는 탭의 계산:** 탭 3개를 열고 라이브 트래픽을 흘려도, 뒤에 있는 탭은 목록과 트리를 다시 계산하지 않는다. 앞으로 오면 그때 한 번 최신으로 계산한다(Task 3, Step 5 확인).
2. **탭을 닫거나 바꾼 직후의 메뉴 명령:** ⌫, ⌘1, ⇧⌘C, Export가 지금 앞에 있는 탭에 작용한다. 마지막 창을 닫아 `activeTab`이 nil이면 명령은 비활성이고, 앱은 죽지 않는다(Task 3, Step 5 확인).
3. **전역 알림은 한 번만:** 시스템 오류, 정보, 프록시 복원 알림이 탭 수만큼 겹쳐 뜨지 않고, 앞 탭 창에 한 번만 뜬다(Task 3, Step 5 확인).
4. **저장된 필터 규칙 보존:** 새 탭(⌘T, Open as New Tab)을 열어도 `settings.filterRules`가 덮이지 않는다. 다음 실행 때 첫 탭에 마지막 규칙이 복원된다(Task 2·3 확인).
5. **열기 실패 처리:** 같은 파일을 두 번 열면 탭이 하나다. 사라진 파일을 Open Recent에서 고르거나 깨진 세션을 열면 오류 알림만 뜨고, 빈 탭이 남지 않는다(Task 4, Step 6 확인).
6. **공유 라이브 세션 지우기:** 라이브 탭 A에서 Clear나 Delete를 하면, 탭 B가 고르고 있던 요청이 사라져도 탭 B의 상세 패널은 비고 앱이 죽지 않는다(Task 3, Step 5 확인).
7. **직접 붙인 이름 보존과 권한 창:** 자동 이름이 직접 붙인 이름이나 종류를 덮지 않는다. 이 Mac 트래픽만 있으면 Bonjour 찾기가 시작되지 않아 권한 창이 뜨지 않는다. 권한을 거부해도 IP로 보이고 알림은 없다(Task 5 테스트와 사용자 점검표).

앱 타깃에는 테스트 타깃이 없다. 그래서 앱 쪽 확인은 Debug 빌드를 직접 실행해서 하고, 결과를 ledger에 기록한다.

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `Packages/EyeProxyKit/Sources/EyeProxyKit/Export/FlowImport.swift` | HAR `_prog.client` → `Flow.clientAddress` |
| `EyeProxy/SessionTab.swift` (새로) | 탭 하나의 보기 상태와 계산. 옮겨 온 코드 |
| `EyeProxy/SessionTab+Export.swift` (새로, `AppModel+Export.swift`에서 옮김) | 탭 기준 Export, Save Requests, Save Session |
| `EyeProxy/AppModel.swift` | 라이브 세션, 전역 상태, 탭 목록, `activeTab`, 파일 열기, 최근 문서 |
| `EyeProxy/Views/MainWindowHost.swift` (새로) | `NSWindow` 접근: 탭 묶기, 키 창이 된 것, 가림 상태 → `SessionTab` |
| `EyeProxy/EyeProxyApp.swift` | `WindowGroup(for:)`, File·View 메뉴, 서버 시작을 AppDelegate로, `application(_:open:)` |
| `EyeProxy/Views/**`, `EyeProxy/Commands/**` | `model.xxx` 보기 상태 → `tab.xxx` 또는 `model.activeTab?.xxx` |
| `EyeProxy/Info.plist` | `CFBundleDocumentTypes`(Viewer), `NSBonjourServices` 추가 |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/Devices/DeviceRegistry.swift` | `Device.autoName`, 자동 이름 적용, 광고가 먼저 온 기기 기억 |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/Devices/DeviceDiscovery.swift` (새로) | Bonjour 광고 듣기, TXT 해석, IP 알아내기 |
| `README.md` | 세션 탭·Open Recent 절, HAR 클라이언트, 기기 이름 자동 찾기 |

---

### Task 1: HAR 가져오기에서 클라이언트 이름 되살리기 (Kit)

**Files:**
- Modify: `Packages/EyeProxyKit/Sources/EyeProxyKit/Export/FlowImport.swift` (`imported(_:startedAt:)`에서 `Flow(... clientAddress: "" ...)`)
- Test: `Packages/EyeProxyKit/Tests/EyeProxyKitTests/FlowImportTests.swift`, `SidebarTreeTests.swift`

**Interfaces:**
- Produces: `FlowImport.har(_:)`가 돌려주는 `ImportedFlow.flow.clientAddress == (client ?? "")`. `ImportedFlow.client`는 그대로 둔다.

- [ ] **Step 1: 실패하는 테스트 작성**

`FlowImportTests.swift`에 테스트를 추가한다. 같은 파일 `harRoundTripPreservesNumbersCommentsHighlightsTools`가 `ExportItem`을 만드는 방식을 따른다.

```swift
@Test func harRoundTripRestoresClientAsAddress() throws {
    // ExportItem 두 개: client "iPhone 15", 그리고 client ""
    // FlowExport.har → FlowImport.har
    #expect(imported[0].flow.clientAddress == "iPhone 15")
    #expect(imported[1].flow.clientAddress == "")
}
```

`SidebarTreeTests.swift`에도 추가한다.

```swift
@Test func importedFlowsGroupByClientName() {
    // clientAddress가 "iPhone 15", "iPhone 15", "", "Apple TV"인 흐름 4개, attribution 비움, devices 비움
    let names = SidebarTree.build(flows: flows, attribution: [:], devices: [], pinned: [], runtimes: [:]).remoteDevices.map(\.displayName)
    #expect(Set(names) == ["iPhone 15", "Apple TV", "가져온 요청"])
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path Packages/EyeProxyKit --filter "harRoundTripRestoresClientAsAddress|importedFlowsGroupByClientName"`

Expected: `harRoundTripRestoresClientAsAddress`가 FAIL(`"" != "iPhone 15"`). `importedFlowsGroupByClientName`은 이미 지원되는 동작을 고정하는 테스트라서 PASS여도 된다.

- [ ] **Step 3: 구현**

`FlowImport.imported`에서 `clientAddress: p?.client ?? ""`로 바꾼다. `AppModel.importHAR`의 doc 주석 중 "클라이언트 문자열은 이번엔 복원하지 않는다" 문장을 지운다.

- [ ] **Step 4: 통과 확인**

Run: `swift test --package-path Packages/EyeProxyKit`

Expected: 전체 PASS.

- [ ] **Step 5: 커밋**

`feat(import): HAR 가져오기에서 클라이언트 이름 되살리기`

---

### Task 2: 보기 상태를 `SessionTab`으로 옮기기 (창은 아직 하나)

**동작은 바뀌지 않아야 한다.** 이 태스크는 Task 3이 탭을 여러 개 만들 수 있게 하는 구조 이동만 한다.

**Files:**
- Create: `EyeProxy/SessionTab.swift`
- Create: `EyeProxy/SessionTab+Export.swift`. `AppModel+Export.swift`의 `exportItems`, `export`, `saveRequests`를 옮긴다.
- Modify:
  - `EyeProxy/AppModel.swift`
  - `EyeProxy/AppModel+Export.swift`(타입·`importHAR`만 남김)
  - `EyeProxy/AppModel+Tools.swift`
  - `EyeProxy/Views/**`
  - `EyeProxy/Commands/**`
  - `EyeProxy/EyeProxyApp.swift`

**Interfaces:**
- Produces(Task 3·4가 쓴다):

```swift
@MainActor @Observable final class SessionTab: Identifiable {
    let id: UUID
    let session: SessionStore          // 라이브 탭이면 model.liveSession과 같은 인스턴스
    let processes: ProcessRegistry     // 라이브 탭이면 model.processes와 같은 인스턴스
    let fileURL: URL?                  // nil = 라이브
    var isLive: Bool { fileURL == nil }
    var title: String { get }          // 라이브: sidebarSelection 표시 이름, 없거나 .allFlows면 "All Requests" / 파일: 파일 이름(확장자 포함)
    var isOnScreen: Bool               // false면 rowsRefresh·sidebarRefresh가 계산을 미루고, true가 되면 한 번 계산
    init(model: AppModel, session: SessionStore, processes: ProcessRegistry, fileURL: URL?, restoreSavedRules: Bool)
    // AppModel에서 옮겨 온 멤버. 이름과 시그니처는 그대로 둔다.
    // filter, isFilterBarVisible, filterBarHasFocus, focusFlowList, focusFilterBar, appliedRules, bodyMatches(+작업 변수),
    // selectedFlowIDs, selectedFlowID, sortOrder, sidebarSelection, visibleFlows, visibleRows, sidebarTree, sidebarFlowCount,
    // pathTrees, sidebarFilterText, expandedDomains, pendingDeleteAll, commentingFlowID,
    // clear(), deleteFlows(_:), deleteVisibleFlows(), refreshVisibleRows(), showFilterBar(), selectLatestIfAuto(), userSelect(_:),
    // processKey(for:), clientName(for:), sidebarFlows, copyCurl(_:), saveSession(), exportItems(scope:), export(_:scope:), saveRequests()
}
```

- Produces(`AppModel`):
  - `let liveSession: SessionStore`: 지금의 `session`. 이름을 바꾸고 `handle(_:)`이 쓴다.
  - `var activeTab: SessionTab?`: 이 태스크에서는 늘 `mainTab`이다.
  - `func makeTab(fileURL: URL?, session: SessionStore, processes: ProcessRegistry, restoreSavedRules: Bool) -> SessionTab`: 만들어서 `tabs[id]`에 등록한다.
  - `private(set) var tabs: [UUID: SessionTab]`
  - `func tab(_ id: UUID) -> SessionTab?`

- [ ] **Step 1: `SessionTab.swift`를 만들고 멤버를 옮긴다.**
  - **옮길 것:** 위 Produces 목록의 저장 프로퍼티와 메서드를 `AppModel.swift`에서 그대로 옮긴다. 대상은 :32–87, :102–104, :367–401, :405–423, :452–622 범위의 보기 관련 부분이다.
  - **전역을 쓰는 곳:** 옮긴 코드가 전역 상태(`settings`, `devices`, `resolver`, `simulatorRuntimes`, `systemError`)를 쓰는 곳은 `model.`(`unowned let model: AppModel`)로 바꾼다.
  - **`filter`의 `didSet`:** `settings.filterRules`에 쓰는 동작은 그대로 둔다. `init`에서 `restoreSavedRules`가 true일 때만 `settings.filterRules`로 `filter.rules`를 채운다. 지금 `AppModel.init` :172–175가 하는 일이다. 이 대입은 `didSet`을 부르지 않는 초기화 경로여야 한다.
  - **`clear()`:** 라이브 탭이면 `processes.clear()`도 부른다. 지금과 같다.
  - **`openSession()`:** 이 태스크에서는 `activeTab`의 세션을 교체하는 지금 동작을 그대로 `AppModel`에 둔다. 새 탭으로 여는 것은 Task 4에서 한다.

- [ ] **Step 2: `AppModel`을 고친다.**
  - **세션:** `session`을 `liveSession`으로 바꾼다. `init`에서 `mainTab = makeTab(fileURL: nil, session: liveSession, processes: processes, restoreSavedRules: true)`를 만들고 `activeTab = mainTab`로 둔다.
  - **`handle(_:)`:** Auto Select·새로 고침 호출을 모든 라이브 탭에 돌린다(`tabs.values.filter(\.isLive)`).
  - **`enableSSLProxying(forHostsOfApp:)`:** `in tab: SessionTab` 인자를 받게 바꾼다.
  - **`repeatFlows`:** `activeTab`의 세션을 읽게 바꾼다.

- [ ] **Step 3: 뷰와 명령을 고친다.**
  - **`MainWindow`:** `MainWindow(tab: SessionTab)`으로 바꾸고, 하위 뷰에 `.environment(tab)`으로 넘긴다. 하위 뷰는 `@Environment(SessionTab.self) private var tab`으로 받는다. 대상은 `FlowListView`, `FlowDetailView`, `SidebarView`, `FilterBarView`, `FilterRulesBar`, `BottomBar`, `MainToolbar`, `SummaryView`, `CommentSheet`이다.
  - **명령:** `FindCommands`, `ToolsCommands`, `EyeProxyApp`의 명령, `StatusMenu`는 `model.activeTab?.xxx`를 쓰게 하고, `activeTab`이 nil이면 `.disabled`로 둔다.
  - **찾을 곳:** `grep -rn "model\.\(session\|filter\|selectedFlow\|sortOrder\|sidebar\|visible\|pendingDeleteAll\|commentingFlowID\|isFilterBarVisible\|focus\|bodyMatches\|expandedDomains\|pathTrees\|deleteFlows\|deleteVisibleFlows\|clear()\|copyCurl\|export\|saveRequests\|clientName\|userSelect\|selectLatestIfAuto\)" EyeProxy`가 0줄이 될 때까지 고친다.
  - **예외:** `ConnectedDevicesSection`, 하단 바의 속도 표시, Compose는 `model.liveSession`을 쓴다.

- [ ] **Step 4: 빌드하고 Kit 테스트를 돌린다.**

Run: `xcodegen generate && xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates 2>&1 | tail -3` 그리고 `swift test --package-path Packages/EyeProxyKit`

Expected: `** BUILD SUCCEEDED **`, Kit 전체 PASS.

- [ ] **Step 5: 회귀가 없는지 Debug 앱으로 확인한다.** Global Constraints의 UI 확인 조건을 지킨다.
  - **트래픽 흘리기:** `curl -x http://127.0.0.1:19090 http://example.com/`을 세 번 보낸다. 목록에 3행이 보이면 통과다.
  - **필터 막대:** ⌘F로 열고 규칙을 하나 넣는다. 다시 실행해도 규칙이 남아 있으면 통과다.
  - **목록 조작:** 행 선택, ⌫ 삭제, ⌘K Clear, 사이드바 도메인 선택이 모두 지금처럼 동작하면 통과다.

- [ ] **Step 6: 커밋**

`refactor(app): 보기 상태를 SessionTab으로 옮기기`

---

### Task 3: 한 창 안의 세션 탭

**Files:**
- Create: `EyeProxy/Views/MainWindowHost.swift`
- Modify:
  - `EyeProxy/EyeProxyApp.swift`
  - `EyeProxy/AppModel.swift`
  - `EyeProxy/Views/MainWindow.swift`
  - `EyeProxy/Views/Sidebar/SidebarView.swift`
  - `EyeProxy/Views/StatusBar/StatusMenu.swift`

**Interfaces:**
- Consumes: Task 2의 `SessionTab`, `AppModel.makeTab`, `tabs`, `activeTab`.
- Produces(Task 4가 쓴다):
  - `AppModel.newLiveTabID(selecting: SidebarItem? = nil) -> UUID`: 라이브 탭을 만들고 id를 돌려준다. `restoreSavedRules: false`.
  - `AppModel.newTabID(sharing tab: SessionTab, selecting: SidebarItem) -> UUID`: 같은 세션과 귀속 정보를 공유하는 새 탭을 만든다.
  - `AppModel.closeTab(_ id: UUID)`: 목록에서 지우고, `activeTab`이 그 탭이었으면 nil로 둔다.
  - `SessionTab.window: NSWindow?`(weak): 창이 붙으면 채워진다.
  - `AppModel.showMainWindow(openWindow: OpenWindowAction)`: 열린 메인 창이 있으면 앞으로 가져오고, 없으면 `openWindow(id: "main")`.

- [ ] **Step 1: 씬을 바꾼다.**
  - **`WindowGroup`:** `WindowGroup("Prog", id: "main", for: UUID.self) { $id in ... } defaultValue: { model.newLiveTabID() }`로 바꾼다.
  - **첫 창:** 앱의 첫 창은 Task 2의 `mainTab`을 쓴다. 첫 `defaultValue`가 `mainTab.id`를 돌려주도록 한다.
  - **값이 없는 경우:** 본문은 `model.tab(id)`가 nil이면(이미 닫힌 탭) 빈 뷰를 보이고 창을 닫는다.
  - **씬 옵션:** `.restorationBehavior(.disabled)`와 `.handlesExternalEvents(matching: [])`를 붙인다. 외부 URL 열기는 Task 4의 AppDelegate가 처리한다.
  - **옮길 것:** `startServer()`와 `autoOverrideSystemProxyAtLaunch()`는 창 `.task`에서 빼서 `AppDelegate.applicationDidFinishLaunching`의 `Task`로 옮긴다. 외형 `onChange`도 창 밖으로 옮긴다. `model.settings.appearance`를 앱 수준에서 관찰한다.
  - **전역 알림:** `pendingProxyRestoreAlert`, `systemErrorAlert`, `infoMessageAlert`는 `model.activeTab?.id == tab.id`인 창에서만 표시한다.

- [ ] **Step 2: `MainWindowHost.swift`를 만든다.**
  - `NSViewRepresentable`이 `viewDidMoveToWindow`에서 다음을 설정한다.
    - `window.tabbingIdentifier = "prog.main"`
    - `window.tabbingMode = .preferred`
    - `tab.window = window`
  - 같은 창의 알림을 구독한다.
    - `didBecomeKey` → `model.activeTab = tab`
    - `didChangeOcclusionState` → `tab.isOnScreen = window.occlusionState.contains(.visible)`
    - `willClose` → `model.closeTab(tab.id)`
  - `MainWindow`에서 `.background(MainWindowHost(tab:))`와 `.navigationTitle(tab.title)`로 붙인다.
  - **⌘T로 연 창이 따로 뜨는 경우:** 새 창이 기존 창의 탭으로 붙지 않고 따로 뜨면, 앞 창의 `addTabbedWindow(_:ordered: .above)`로 붙인다.

- [ ] **Step 3: 메뉴를 만든다.**
  - `CommandGroup(replacing: .newItem)`에 New Session ⌘T(`openWindow(id: "main", value: model.newLiveTabID())`)를 넣는다. Open…과 Open Recent는 Task 4에서 이 자리에 붙인다.
  - 지금 `after: .newItem`에 있는 세 항목은 이름을 바꾼다. 세션 열기… → `Open…`, 세션 저장… → `Save Session…`, 세션 지우기 → `Clear Session`.
  - **Close ⌘W:** 시스템 기본 Close를 그대로 쓴다.
  - **Close All ⌥⌘W:** `CommandGroup(after: .saveItem)`에 넣는다. 탭 순서대로 `tab.window?.close()`를 부른다.
  - **View 메뉴(`CommandGroup(after: .toolbar)`의 Auto Select 아래):**
    - Select Next Tab ⇧⌘] → `NSApp.keyWindow?.selectNextTab(nil)`
    - Select Previous Tab ⇧⌘[ → `NSApp.keyWindow?.selectPreviousTab(nil)`
    - 키 창에 탭이 하나뿐이면 둘 다 비활성으로 둔다.

- [ ] **Step 4: 사이드바와 상태 막대를 고친다.**
  - `SidebarView`의 앱·기기·도메인·경로 항목 우클릭 메뉴 맨 위에 `Open as New Tab`을 넣는다. 동작은 `openWindow(id: "main", value: model.newTabID(sharing: tab, selecting: item))`.
  - `StatusMenu`의 `openWindow(id: "main")`은 `model.showMainWindow(openWindow:)`로 바꾼다.

- [ ] **Step 5: 빌드하고 Debug 앱으로 확인한다.** 각 항목의 결과를 ledger에 적는다.
  - **⌘T 탭 묶기:** ⌘T를 두 번 누른다. 한 창에 탭 3개가 보이면 통과다. 스크린숏을 남긴다.
  - **탭별 보기 상태:** 탭 1에서 도메인 하나를 고르고 탭 2에서 필터를 넣는다. 서로 다른 탭에 영향이 없으면 통과다. 트래픽 `curl` 3회를 보내면 세 탭 모두 새 요청을 받는다.
  - **탭 제목:** 도메인을 고른 탭의 제목이 그 도메인이고, 나머지는 `All Requests`이면 통과다.
  - **Review Focus 1(뒤 탭 계산):** 뒤 탭의 `rowsRefresh` 계산 횟수가 늘지 않는지 확인한다. 디버그 로그를 임시로 넣어 확인하고, 커밋 전에 지운다.
  - **Review Focus 2(메뉴 명령 대상):** 탭 2를 앞에 두고 ⌫를 누르면 탭 2에서 고른 행이 지워진다. 탭을 모두 닫으면 Flow 메뉴 항목이 비활성이고, 앱과 프록시가 계속 동작한다(`curl` 성공). Dock 아이콘을 누르면 라이브 탭이 하나 다시 열린다.
  - **Review Focus 3(알림 중복):** 탭 3개 상태에서 포트 충돌 같은 시스템 오류를 일으킨다. 예: 19090을 다른 프로세스가 점유한 채로 Advanced에서 포트를 바꾼다. 알림이 한 번만 뜨면 통과다.
  - **Review Focus 4(필터 규칙 보존):** ⌘T로 새 탭을 연 뒤 종료하고 다시 실행한다. 첫 탭에 마지막 규칙이 남아 있으면 통과다.
  - **Review Focus 6(공유 세션 지우기):** 탭 B에서 행을 고른 뒤 탭 A에서 ⌘K를 누른다. 탭 B의 상세 패널이 비고 앱이 죽지 않으면 통과다.
  - **Open as New Tab:** 우클릭해서 연 새 탭에 그 항목이 선택되어 있으면 통과다.

- [ ] **Step 6: 커밋**

`feat(app): 한 창 안의 세션 탭(New Session ⌘T, Close All, 탭 이동, Open as New Tab)`

---

### Task 4: 파일을 새 탭에 열기, Open Recent, Save Session

**Files:**
- Modify:
  - `EyeProxy/AppModel.swift`(`openSession`, `importHAR`)
  - `EyeProxy/AppModel+Export.swift`
  - `EyeProxy/SessionTab+Export.swift`(`saveSession`)
  - `EyeProxy/EyeProxyApp.swift`
  - `EyeProxy/Views/MainWindow.swift`
  - `EyeProxy/Info.plist`

**Interfaces:**
- Consumes: Task 3의 `SessionTab.window`, `openWindow`, `makeTab`.
- Produces:
  - `AppModel.open(_ url: URL) async -> UUID?`
    - 이미 열린 `fileURL`(`standardizedFileURL` 비교)이면 그 탭 창을 `makeKeyAndOrderFront`하고 nil을 돌려준다.
    - 아니면 읽어서 새 파일 탭을 만들고 id를 돌려준다.
    - 실패하면 `systemError`에 이유를 쓰고 nil을 돌려준다. 이때 탭은 만들지 않는다.
  - `AppModel.recentURLs: [URL]`: `NSDocumentController.shared.recentDocumentURLs`를 그대로 비춘다.
  - `AppModel.clearRecent()`
  - `AppModel.noteRecent(_ url: URL)`
  - `AppModel.pendingOpenTabIDs: [UUID]`: AppDelegate가 연 파일의 탭 id. 앞 탭의 `MainWindow`가 `openWindow`로 소비하고 비운다.

- [ ] **Step 1: `Info.plist`에 문서 형식을 넣는다.**
  - `CFBundleDocumentTypes`에 두 항목을 넣는다. `CFBundleTypeRole` = `Viewer`, `LSItemContentTypes`는 `com.tv.eyeproxy.session`(`LSHandlerRank` `Owner`)과 `com.tv.eyeproxy.har`(`LSHandlerRank` `Alternate`).
  - `xcodegen generate`가 이 항목을 지우지 않는지 확인한다. 빌드된 앱의 `Contents/Info.plist`에 `CFBundleDocumentTypes`가 있어야 한다.

- [ ] **Step 2: 파일 읽기를 새 탭용으로 바꾼다.**
  - `AppModel.open(_:)`은 `.har`이면 `FlowImport.har`, 아니면 `SessionDocument.load`로 읽는다. 결과는 새 `SessionStore`와 `ProcessRegistry`에 채운 뒤 `makeTab(fileURL: url, …, restoreSavedRules: false)`로 탭을 만든다.
  - 성공하면 `noteRecent(url)`을 부른다.
  - 지금 `openSession`과 `importHAR`의 "현재 세션 교체" 경로는 지운다.

- [ ] **Step 3: 여는 경로를 연결한다.** 모든 경로는 `open(_:)`이 id를 주면 `openWindow(id: "main", value: id)`를 부른다.
  - **Open… ⌘O:** 패널은 지금과 같다(세션 형식과 HAR 형식).
  - **Open Recent:** `Menu("Open Recent")` 안에 `recentURLs`를 파일 이름 버튼으로 나열하고, `Divider`, `Clear Menu`를 둔다. 사라진 파일을 고르면 `open`이 실패하므로, 오류 알림을 띄우고 목록에서 뺀다. 목록에서 빼는 일은 `NSDocumentController`에 개별 삭제 API가 없으므로 `recentURLs`를 다시 계산할 때 존재하지 않는 파일을 거르는 방식으로 한다.
  - **끌어다 놓기:** `MainWindow`에 `.dropDestination(for: URL.self)`를 붙이고, 확장자가 `eyeproxy`나 `har`인 것만 받는다.
  - **Finder 더블클릭과 `open -a`:** `AppDelegate.application(_:open urls:)`로 받는다. 창 열기는 SwiftUI `openWindow`가 필요하므로, `model.pendingOpenTabIDs`에 쌓아 두고 앞 탭의 `MainWindow`가 `onChange`로 소비한다. 창이 하나도 없으면 먼저 `showMainWindow`를 한다.

- [ ] **Step 4: Save Session을 고친다.**
  - `SessionTab.saveSession()`은 이 탭의 세션 전체를 저장한다. 라이브 탭이면 라이브 세션이고, `processes.attribution`도 함께 저장한다.
  - 기본 파일 이름: 파일 탭은 그 파일 이름, 라이브 탭은 지금처럼 `Prog-yyyyMMdd-HHmm.eyeproxy`.
  - 저장에 성공하면 `noteRecent(url)`을 부른다.
  - Save Requests와 Export도 `noteRecent`를 부른다. 단, `.eyeproxy`와 `.har`에 한하고 CSV는 넣지 않는다.

- [ ] **Step 5: 빌드한다.**

Run: Task 2 Step 4와 같다.

Expected: `** BUILD SUCCEEDED **`. 빌드된 앱의 Info.plist에 `CFBundleDocumentTypes`가 있다.

- [ ] **Step 6: Debug 앱으로 확인한다.**
  - **새 탭으로 열기:** 라이브 탭에서 Save Session…으로 파일을 저장한 뒤 Open…으로 그 파일을 연다. 새 탭이 생기고(제목은 파일 이름) 라이브 탭은 그대로면 통과다.
  - **같은 파일 다시 열기:** 같은 파일을 다시 열면 탭이 늘지 않고 그 탭이 앞으로 오면 통과다.
  - **Open Recent:** 그 파일이 목록에 보이고, Clear Menu를 누르면 목록이 비면 통과다.
  - **HAR 탭:** Export로 HAR을 만들어 연다. 새 탭 사이드바의 Remote devices에 클라이언트 이름이 보이면 통과다.
  - **사라진 파일:** 파일을 지운 뒤 Open Recent에서 고른다. 오류 알림만 뜨고, 탭이 생기지 않고, 목록에서 빠지면 통과다.
  - **깨진 파일:** `index.json`에 `"version": 2`를 넣은 사본을 연다. 오류 알림만 뜨고 탭이 생기지 않으면 통과다.
  - **`open -a`:** `open -a <빌드한 Debug 앱 경로> <파일>`을 실행한다. 새 탭으로 열리면 통과다. Finder 더블클릭은 기본 앱이 `/Applications/Prog.app`일 수 있으므로 사용자 점검표로 넘긴다.
  - **파일 탭 분리:** 파일 탭에서 ⌘K를 누르면 그 탭만 비고, 라이브 탭은 그대로면 통과다.

- [ ] **Step 7: 커밋**

`feat(app): 파일을 새 탭에 열기, Open Recent, Save Session`

---

### Task 5: 원격 기기 이름 자동 찾기

탭과는 따로 선 기능이다. Task 2가 `AppModel.handle`을 옮기므로 그 뒤에, Task 4와 `Info.plist`가 겹치므로 Task 4 뒤에 한다.

**Files:**
- Create:
  - `Packages/EyeProxyKit/Sources/EyeProxyKit/Devices/DeviceDiscovery.swift`
  - `Packages/EyeProxyKit/Tests/EyeProxyKitTests/DeviceDiscoveryTests.swift`
- Modify:
  - `Packages/EyeProxyKit/Sources/EyeProxyKit/Devices/DeviceRegistry.swift`
  - `Packages/EyeProxyKit/Tests/EyeProxyKitTests/DeviceRegistryTests.swift`
  - `EyeProxy/AppModel.swift`(초기화, `handle`)
  - `EyeProxy/Info.plist`

**Interfaces:**
- Produces:
  - `Device.autoName: String?`: 선택 필드다. 이 키가 없는 옛 `devices.json`도 읽힌다.
  - `Device.displayName`: `name`(비어 있지 않으면) → `autoName`(비어 있지 않으면) → 이 Mac이면 "이 Mac", 아니면 `address`.
  - `public struct DiscoveredDevice: Equatable, Sendable { address: String; name: String; kind: DeviceKind? }`
  - `DeviceRegistry.applyDiscovered(_ found: DiscoveredDevice) -> Bool`
    - 그 주소의 기억을 갱신한다. 기억은 저장하지 않는다.
    - 그 주소의 기기가 있으면 `autoName = found.name`을 넣는다. `kind`가 `.unknown`이고 `found.kind`가 있으면 종류도 넣는다. `name`은 건드리지 않는다.
    - 기기 정보가 바뀌었으면 true를 돌려준다.
  - `DeviceRegistry`가 새 기기를 만들 때(`update`) 그 주소의 기억이 있으면 같은 규칙으로 바로 적용한다.
  - `DeviceDiscovery.parse(serviceType: String, serviceName: String, txt: [String: String]) -> (name: String, kind: DeviceKind?)?`: 순수 함수다. 규칙은 스펙 §4.6 표를 따른다. 이름이 비면 nil.
  - `DeviceDiscovery.normalize(_ address: String) -> String`: `::ffff:` 접두어를 뗀다.
  - `@MainActor final class DeviceDiscovery`
    - `init(onFound: @escaping @MainActor (DiscoveredDevice) -> Void)`
    - `start()`: 여러 번 불러도 한 번만 시작한다.
    - `isStarted: Bool`

- [ ] **Step 1: 실패하는 테스트를 쓴다.**

```swift
// DeviceDiscoveryTests.swift
@Test func parsesAirPlayName() {
    let r = DeviceDiscovery.parse(serviceType: "_airplay._tcp", serviceName: "거실 Apple TV", txt: ["model": "AppleTV14,1"])
    #expect(r?.name == "거실 Apple TV"); #expect(r?.kind == .appleTV)
}
@Test func parsesCompanionLinkKind() {
    #expect(DeviceDiscovery.parse(serviceType: "_companion-link._tcp", serviceName: "테스트 iPhone", txt: ["rpMd": "iPhone15,2"])?.kind == .iPhone)
}
@Test func parsesGoogleCastFriendlyName() {
    let r = DeviceDiscovery.parse(serviceType: "_googlecast._tcp", serviceName: "Google-TV-0000", txt: ["fn": "안방 TV", "md": "Chromecast"])
    #expect(r?.name == "안방 TV"); #expect(r?.kind == nil)
}
@Test func googleCastWithoutFriendlyNameIsIgnored() {
    #expect(DeviceDiscovery.parse(serviceType: "_googlecast._tcp", serviceName: "Google-TV-0000", txt: [:]) == nil)
}
@Test func normalizesMappedIPv4() { #expect(DeviceDiscovery.normalize("::ffff:192.0.2.10") == "192.0.2.10") }

// DeviceRegistryTests.swift
@Test func autoNameNeverOverridesManualName()   // name "내 기기" + 자동 "거실 Apple TV" → displayName "내 기기"; rename(name: nil) → "거실 Apple TV"
@Test func autoKindOnlyFillsUnknown()           // 사용자가 .iPad로 둔 기기에 .appleTV 광고 → .iPad 그대로; .unknown 기기는 .appleTV
@Test func discoveryBeforeTrafficIsApplied()    // 192.0.2.20 광고 먼저 → 그 주소의 requestStarted 뒤 displayName == 광고 이름
@Test func autoNamePersistsAndOldFileLoads()    // save → 다시 읽으면 autoName 유지; autoName 키 없는 JSON도 읽힘
```

- [ ] **Step 2: 테스트가 실패하는지 본다.**

Run: `swift test --package-path Packages/EyeProxyKit --filter 'DeviceDiscoveryTests|DeviceRegistryTests'`

Expected: `DeviceDiscovery`, `autoName`, `applyDiscovered`가 없어 컴파일에 실패한다.

- [ ] **Step 3: Kit을 구현한다.**
  - `Device`, `DeviceRegistry`: 위 Interfaces대로.
  - `DeviceDiscovery`: 세 광고 형식마다 `NWBrowser(for: .bonjourWithTXTRecord(type:domain: nil))`를 하나씩 둔다.
    - 결과마다 `NWConnection(to: result.endpoint, using: .tcp)`로 연결한다. `.ready`가 되면 `currentPath?.remoteEndpoint`에서 IPv4를 읽고 `normalize`한 뒤 바로 `cancel`한다. 5초 안에 준비되지 않으면 버린다.
    - 같은 결과가 바뀌면(`.changed`) 다시 알아낸다.
    - 실패하거나 권한이 없으면 조용히 넘긴다.
  - 시스템 프레임워크(Network)만 쓴다. 외부 도구(`adb`, `arp`, `dns-sd`)는 실행하지 않는다.

- [ ] **Step 4: 테스트가 통과하는지 본다.**

Run: `swift test --package-path Packages/EyeProxyKit`

Expected: 모두 통과한다.

- [ ] **Step 5: 앱에 연결한다.**
  - `AppModel`에 `DeviceDiscovery`를 둔다. `onFound`에서 `devices.applyDiscovered`가 true이면 `try? devices.save()`를 한다.
  - 시작 조건: 초기화 때와 `handle`의 `devices.observe(event)` 뒤에, 아직 시작하지 않았고 `devices.devices`에 루프백이 아니면서 비어 있지 않은 주소가 있으면 `start()`를 부른다. 시작했으면 이 검사는 건너뛴다.
  - `Info.plist`에 `NSBonjourServices`로 `_airplay._tcp`, `_companion-link._tcp`, `_googlecast._tcp`를 넣는다. `NSLocalNetworkUsageDescription`을 "같은 네트워크의 기기(Apple TV·iPhone)와 서버에 연결하고 기기 이름을 찾기 위해 필요합니다."로 바꾼다.

- [ ] **Step 6: 빌드한다.**

Run: Task 2 Step 4와 같다.

Expected: `** BUILD SUCCEEDED **`. 빌드된 앱의 Info.plist에 `NSBonjourServices`가 있다.

- [ ] **Step 7: Debug 앱으로 확인한다.**
  - **권한 창이 뜨지 않는 경우:** 원격 기기가 없는 `devices.json`(백업 후 비운 것)으로 실행하고 루프백 트래픽만 보낸다. 로컬 네트워크 권한 창이 뜨지 않으면 통과다.
  - 원격 기기 트래픽, 권한 창, 실제 이름 표시는 에이전트가 할 수 없다. 사용자 점검표(Task 6)로 넘긴다.

- [ ] **Step 8: 커밋**

`feat(devices): Bonjour 광고로 원격 기기 이름 자동 찾기`

---

### Task 6: 문서

**Files:**
- Modify: `README.md`
- Create: `docs/superpowers/plans/2026-11-12-prog-session-tabs-handover.md`

- [ ] **Step 1: README를 고친다.**
  - **"세션 탭" 절을 새로 쓴다.** 담을 내용:
    - ⌘T, ⌘W, ⌥⌘W, ⇧⌘], ⇧⌘[, Open as New Tab
    - 라이브 탭은 하나의 세션을 함께 보고, Clear와 Delete가 모든 라이브 탭에 반영된다는 것
    - 파일 탭은 따로 동작하고, 닫으면 저장 여부를 묻지 않는다는 것
  - **Open Recent와 파일 열기 경로를 적는다.**
  - **HAR 클라이언트 이름 복원을 적는다.**
  - **기기 이름 자동 찾기를 적는다.** 어떤 광고에서 이름을 찾는지, 직접 붙인 이름이 우선이라는 것, 원격 기기가 처음 붙을 때 로컬 네트워크 권한을 묻는다는 것.
  - **알려진 제한에 추가한다.**
    - 가져온 요청의 IP Address 필터는 이름에 걸린다.
    - 탭은 다시 실행할 때 복원되지 않는다.
    - 이름을 알리지 않는 기기는 IP로 보인다. 직접 붙인 이름은 IP에 묶여 있어, 공유기가 IP를 바꾸면 다시 붙여야 한다.
  - **지운 메뉴 이름(세션 열기, 세션 저장, 세션 지우기)을 README에서 찾아 바꾼다.**

- [ ] **Step 2: 핸드오버를 쓴다.** 이전 핸드오버 형식을 따른다.
  - 무엇이 들어갔나
  - 수동 점검표: Finder 더블클릭, 실제 iPhone 트래픽에서 탭 3개, 메모리, Stay On Top과 탭, 전체 화면에서 탭
  - 기기 이름 점검표:
    - Apple TV나 Google TV가 처음 트래픽을 보낼 때 로컬 네트워크 권한 창이 한 번 뜬다.
    - 허용하면 사이드바 Remote devices, Client 열, 설정 "연결된 기기"에 광고 이름이 보인다.
    - 직접 이름을 붙이면 그 이름이 이기고, 지우면 광고 이름으로 돌아간다.
    - 권한을 거부하면 IP로 보이고 알림이 없다.
  - 보류·결정 요약: 스펙의 "(내 판단)" 항목 그대로
  - 다음 묶음: 호스트 그룹 탭

- [ ] **Step 3: 커밋**

`docs: 세션 탭·Open Recent·기기 이름 README와 핸드오버`
