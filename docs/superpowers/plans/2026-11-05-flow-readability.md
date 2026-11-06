# Flow 화면 가독성 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flow 화면을 고정 `#`·헤더 정렬, 앱별 트리 사이드바(고정 호스트 포함), A안 스타일 상세 영역(태그·줄바꿈 URL·Key/Value 표·줄번호 본문·쿠키 탭), 줄바꿈 기본으로 바꾼다.

**Architecture:** Core는 `Flow.clientPort` 한 필드만 추가. Kit에 순수 로직(번호·정렬 행, lsof 파싱·PID 귀속, 사이드바 트리, 쿠키·JSON 토큰·JSON 트리 노드)을 넣고 `swift test`로 검증한다. 앱 레이어는 Kit 결과를 그리기만 한다(SwiftUI + NSTextView 하나).

**Tech Stack:** Swift 6, SwiftUI(macOS 15), AppKit(NSTextView·NSRulerView), SwiftNIO(기존), `lsof`·`proc_pidpath`·`responsibility_get_pid_responsible_for_pid`(dlsym).

**Spec:** `docs/superpowers/specs/2026-11-05-flow-readability-design.md`

## Global Constraints

- 모듈 방향 `EyeProxy` → `EyeProxyKit` → `EyeProxyCore`. Core는 UI 무관. Kit는 `import AppKit` 금지.
- 외부 패키지 추가 금지. 락 금지(actor·`@MainActor`).
- 새 사용자 문자열은 `EyeProxy/Localizable.xcstrings`에 `"<문자열>" : { }` 항목 추가(sourceLanguage ko).
- 시스템 설정 변경 명령 실행 금지. 시스템 명령은 `lsof`·`simctl list`처럼 읽기 전용만.
- 커밋 메시지 `<type>(<scope>): <한국어 요약>`, 끝에 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- 작업 디렉터리는 worktree `/Users/kimdoyeon/personal/EyeProxy/.claude/worktrees/flow-readability`(브랜치 `worktree-flow-readability`). main 체크아웃으로 `cd` 금지.
- 테스트: `swift test --package-path Packages/EyeProxyKit`(기준 75) / `Packages/EyeProxyCore`(기준 36). 앱 빌드: `xcodegen generate && xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates 2>&1 | grep -E "warning:|error:|BUILD"` → 경고 0.
- 기존 동작 유지: 2MB 본문 컷, hex 덤프, 이미지·HTML 미리보기, 컬럼 가시성 저장, 컨텍스트 메뉴(SSL 프록싱·cURL), 레이아웃 A/B.

## Review Focus

1. **lsof 전에 닫힌 연결** — 귀속 실패가 "기타"로 가고, 재시도 1회 뒤 조용히 포기해야 한다(UI 멈춤·에러 alert 없음). → Task 4 테스트 `resolverReturnsNilWhenPortAbsent`.
2. **IPv6 루프백 `::1` 클라이언트** — "이 Mac"으로 묶이고 `.scope(device:)` 필터가 127.0.0.1과 같이 통과해야 한다. → Task 5 `treeMergesLoopbackAddresses`, `filterProcessAndLoopback`.
3. **깨진 Cookie 헤더(`=` 없음·빈 조각·공백)** — 행이 비거나 크래시하면 안 된다. → Task 6 `cookieParserTolerates`.
4. **긴 한 줄 JSON 문자열(비ASCII 포함)에서의 색 범위** — UTF-16 오프셋이 어긋나 색이 밀리면 안 된다. → Task 6 `highlighterRangesSurviveNonASCII`.
5. **정렬 중 응답 없는 행** — Status/Size/Time 정렬에서 미완 행이 한쪽 끝에 안정적으로 모여야 한다(크래시·뒤섞임 없음). → Task 2 `rowsSortPendingToOneEnd`.

---

### Task 1: Core — `Flow.clientPort`

**Files:**
- Modify: `Packages/EyeProxyCore/Sources/EyeProxyCore/Flow.swift:83-108`
- Modify: `Packages/EyeProxyCore/Sources/EyeProxyCore/ProxyServer.swift:116-119`
- Modify: `Packages/EyeProxyCore/Sources/EyeProxyCore/ProxyConnectionHandler.swift:103-106,183`
- Test: `Packages/EyeProxyCore/Tests/EyeProxyCoreTests/ProxyServerHTTPTests.swift:14-30`, 새 파일 `Packages/EyeProxyCore/Tests/EyeProxyCoreTests/FlowCodableTests.swift`

**Interfaces:**
- Produces: `Flow.clientPort: Int?`(init 파라미터 `clientPort: Int? = nil`, `clientAddress` 바로 뒤), `ProxyServer.exchange(_:clientAddress:clientPort:upstream:isDecrypted:)`(`clientPort: Int? = nil`).

- [ ] **Step 1: 실패 테스트 작성**

`FlowCodableTests.swift`:
```swift
@Test func decodesFlowWithoutClientPort() throws {
    let json = #"{"id":{"rawValue":"00000000-0000-0000-0000-000000000001"},"clientAddress":"127.0.0.1","startedAt":0,"request":{"method":"GET","scheme":"https","host":"a","port":443,"path":"/","headers":[],"body":""},"isDecrypted":false,"isTunnel":false}"#
    let d = JSONDecoder(); d.dateDecodingStrategy = .deferredToDate
    let f = try d.decode(Flow.self, from: Data(json.utf8))
    #expect(f.clientPort == nil && f.clientAddress == "127.0.0.1")
}
```
`forwardsPlainHTTPAndEmitsEvents`의 `requestStarted` guard 뒤에 `#expect((flow.clientPort ?? 0) > 0)` 추가.

- [ ] **Step 2: 실패 확인** — `swift test --package-path Packages/EyeProxyCore --filter "decodesFlowWithoutClientPort|forwardsPlainHTTPAndEmitsEvents"` → 컴파일 실패(`clientPort` 없음).

- [ ] **Step 3: 구현** — `Flow`에 `public let clientPort: Int?` 추가(합성 Codable이 옵셔널은 `decodeIfPresent`로 읽는다; 커스텀 init 불필요). `exchange`에 `clientPort` 파라미터를 받아 `Flow(...)`에 넣고, 핸들러 103행에서 `let clientPort = context.channel.remoteAddress?.port`를 읽어 106행 호출과 183행 터널 `Flow`에 넘긴다. `FlowContext`는 손대지 않는다.

- [ ] **Step 4: 통과 확인** — `swift test --package-path Packages/EyeProxyCore` → 37 passed. `swift test --package-path Packages/EyeProxyKit` → 75 passed(기존 픽스처는 기본값 nil).

- [ ] **Step 5: 커밋** — `feat(core): Flow에 클라이언트 포트 추가`

---

### Task 2: Kit — 고정 번호와 `FlowRow` 정렬

**Files:**
- Modify: `Packages/EyeProxyKit/Sources/EyeProxyKit/SessionStore.swift`
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/FlowRow.swift`
- Test: `Packages/EyeProxyKit/Tests/EyeProxyKitTests/SessionStoreTests.swift`, 새 파일 `.../FlowRowTests.swift`

**Interfaces:**
- Produces:
  ```swift
  // SessionStore
  public func number(_ id: FlowID) -> Int?            // 1부터, requestStarted 순. clear()→리셋, replace→배열 순 재부여
  // FlowRow.swift
  public struct FlowRow: Identifiable, Sendable {
      public let flow: Flow; public let number: Int
      public var id: FlowID { flow.id }
      public let method: String, url: String, host: String, startedAt: Date
      public let status: Int        // 응답 있음 = status, 오류 = -2, 대기 = -1
      public let size: Int          // 응답 바디 바이트, 없으면 -1
      public let durationMS: Int    // (completedAt-startedAt)*1000 반올림, 미완 -1
      public init(flow: Flow, number: Int)
  }
  ```

- [ ] **Step 1: 실패 테스트 작성**

`SessionStoreTests.swift`에 추가:
```swift
@Test @MainActor func storeNumbersFlowsInArrivalOrderAndResets() {
    let s = SessionStore(); let a = Flow.fixture(client: "1", decrypted: false), b = Flow.fixture(client: "2", decrypted: false)
    s.apply(.requestStarted(a)); s.apply(.requestStarted(b))
    #expect(s.number(a.id) == 1 && s.number(b.id) == 2)
    s.clear(); let c = Flow.fixture(client: "3", decrypted: false); s.apply(.requestStarted(c))
    #expect(s.number(c.id) == 1 && s.number(a.id) == nil)
    s.replace(flows: [b, a]); #expect(s.number(b.id) == 1 && s.number(a.id) == 2)
}
```
`FlowRowTests.swift`:
```swift
@Test func rowDerivesSortKeys() {
    var f = Flow.fixture(url: "https://api.tving.com/v2?x=1", method: "POST", status: 404)
    f.response?.body = Data(count: 12); f.completedAt = f.startedAt.addingTimeInterval(0.0634)
    let r = FlowRow(flow: f, number: 7)
    #expect(r.number == 7 && r.method == "POST" && r.host == "api.tving.com" && r.status == 404 && r.size == 12 && r.durationMS == 63)
    var p = Flow.fixture(client: "1", decrypted: false); #expect(FlowRow(flow: p, number: 1).status == -1 && FlowRow(flow: p, number: 1).size == -1 && FlowRow(flow: p, number: 1).durationMS == -1)
    p.error = "x"; #expect(FlowRow(flow: p, number: 1).status == -2)
}
@Test func rowsSortPendingToOneEnd() {
    let done = FlowRow(flow: Flow.fixture(url: "https://a/", method: "GET", status: 200), number: 1)
    let pending = FlowRow(flow: Flow.fixture(client: "1", decrypted: false), number: 2)
    let asc = [done, pending].sorted(using: [KeyPathComparator(\FlowRow.status)])
    #expect(asc.map(\.number) == [2, 1])
    let desc = [done, pending].sorted(using: [KeyPathComparator(\FlowRow.status, order: .reverse)])
    #expect(desc.map(\.number) == [1, 2])
}
```

- [ ] **Step 2: 실패 확인** — `swift test --package-path Packages/EyeProxyKit --filter "storeNumbers|rowDerives|rowsSort"` → 컴파일 실패.

- [ ] **Step 3: 구현** — `SessionStore`에 `@ObservationIgnored private var numbers: [FlowID: Int]`, `private var next = 1`; `requestStarted`에서 부여, `replace`에서 `enumerated` 순으로 재부여하고 `next = flows.count + 1`. `FlowRow` init은 파생값을 전부 계산해 저장(정렬 비교마다 재계산 안 함). `url`은 `flow.request.url`, `host`는 `flow.request.host`.

- [ ] **Step 4: 통과 확인** — `swift test --package-path Packages/EyeProxyKit` → 78 passed.

- [ ] **Step 5: 커밋** — `feat(kit): 세션 고정 번호와 정렬용 FlowRow`

---

### Task 3: Kit — `AppSettings.pinnedHosts`·`wrapLongLines`

**Files:**
- Modify: `Packages/EyeProxyKit/Sources/EyeProxyKit/AppSettings.swift`
- Test: `Packages/EyeProxyKit/Tests/EyeProxyKitTests/AppSettingsTests.swift`

**Interfaces:**
- Produces: `public var pinnedHosts: [String]`(기본 `[]`, 키 `eyeproxy.pinnedHosts`), `public var wrapLongLines: Bool`(기본 `true`, 키 `eyeproxy.wrapLongLines`), `public func togglePin(_ host: String)`(있으면 제거, 없으면 끝에 추가).

- [ ] **Step 1: 실패 테스트** — `settingsDefaultsAndPersistence`에 추가:
```swift
#expect(s.pinnedHosts.isEmpty && s.wrapLongLines)
s.togglePin("api.tving.com"); s.togglePin("gw.tving.com"); s.togglePin("api.tving.com"); s.wrapLongLines = false
#expect(AppSettings(defaults: d).pinnedHosts == ["gw.tving.com"] && !AppSettings(defaults: d).wrapLongLines)
```
- [ ] **Step 2: 실패 확인** — `--filter settingsDefaultsAndPersistence` → 컴파일 실패.
- [ ] **Step 3: 구현** — 기존 `didSet` 저장 패턴 그대로.
- [ ] **Step 4: 통과 확인** — Kit 78 passed.
- [ ] **Step 5: 커밋** — `feat(kit): 고정 호스트·줄바꿈 설정`

---

### Task 4: Kit — PID 귀속(`ProcessIdentity`·`ProcessResolver`·`ProcessRegistry`·세션 저장)

**Files:**
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Processes/ProcessIdentity.swift`
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Processes/ProcessResolver.swift`
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Processes/ProcessRegistry.swift`
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/System/ResponsiblePID.swift`
- Modify: `Packages/EyeProxyKit/Sources/EyeProxyKit/SessionDocument.swift`
- Test: 새 파일 `.../EyeProxyKitTests/ProcessIdentityTests.swift`, `.../ProcessResolverTests.swift`; `SessionDocumentTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct SimulatorRef: Codable, Hashable, Sendable { public let udid: String; public let appName: String }
  public struct ProcessIdentity: Codable, Hashable, Sendable {
      public let pid: Int32; public let name: String; public let path: String?; public let simulator: SimulatorRef?
      public init(pid: Int32, path: String?)                       // name·simulator를 path에서 파생. path nil이면 name = "pid \(pid)"
      public var groupKey: String                                  // simulator → "sim:<udid>:<appName>", 아니면 path ?? name
      public func displayName(runtimes: [String: String]) -> String // udid→"tvOS 18.1". 시뮬레이터면 "<appName> (<첫 단어> 시뮬레이터)", 모르면 "<appName> (시뮬레이터)"
      static func name(fromPath: String) -> String                 // 첫 ".app" 요소의 이름(확장자 제거), 없으면 마지막 경로 요소
      static func simulatorRef(fromPath: String) -> SimulatorRef?  // "/CoreSimulator/Devices/<UDID>/" 포함 시
  }
  public enum ProcessLookup {
      static func parseLsof(_ output: String, proxyPort: Int, excludingPID: Int32) -> [Int: Int32]  // clientPort → pid
  }
  public actor ProcessResolver {
      public init()
      public func resolve(port: Int, proxyPort: Int) async -> ProcessIdentity?
  }
  @Observable @MainActor public final class ProcessRegistry {
      public private(set) var attribution: [FlowID: ProcessIdentity] = [:]
      public init()
      public func set(_ identity: ProcessIdentity, for id: FlowID)
      public func replace(_ all: [FlowID: ProcessIdentity])
      public func clear()
  }
  enum ResponsiblePID { static func lookup(_ pid: Int32) -> Int32 }   // dlsym 실패·반환 ≤ 0이면 pid 그대로
  // SessionDocument
  public static func save(flows:connectionLog:processes: [FlowID: ProcessIdentity] = [:], to:) throws
  public static func load(from:) throws -> (flows: [Flow], connectionLog: [ConnectionLogEntry], processes: [FlowID: ProcessIdentity])
  ```

- [ ] **Step 1: 실패 테스트 작성**

`ProcessIdentityTests.swift`:
```swift
@Test func identityDerivesNameAndSimulatorFromPath() {
    let sim = ProcessIdentity(pid: 10, path: "/Users/me/Library/Developer/CoreSimulator/Devices/ABCD-1234/data/Containers/Bundle/Application/X/TVING.app/TVING")
    #expect(sim.name == "TVING" && sim.simulator == SimulatorRef(udid: "ABCD-1234", appName: "TVING") && sim.groupKey == "sim:ABCD-1234:TVING")
    #expect(sim.displayName(runtimes: ["ABCD-1234": "tvOS 18.1"]) == "TVING (tvOS 시뮬레이터)" && sim.displayName(runtimes: [:]) == "TVING (시뮬레이터)")
    let safari = ProcessIdentity(pid: 11, path: "/Applications/Safari.app/Contents/MacOS/Safari")
    #expect(safari.name == "Safari" && safari.simulator == nil && safari.groupKey == "/Applications/Safari.app/Contents/MacOS/Safari" && safari.displayName(runtimes: [:]) == "Safari")
    let daemon = ProcessIdentity(pid: 12, path: "/usr/libexec/nsurlsessiond"); #expect(daemon.name == "nsurlsessiond")
    #expect(ProcessIdentity(pid: 13, path: nil).name == "pid 13")
}
```
`ProcessResolverTests.swift`:
```swift
@Test func parseLsofMapsClientPortToPidAndSkipsSelf() {
    let out = "p100\ncEyeProxy\nf5\nn*:9090\nf6\nn127.0.0.1:9090->127.0.0.1:52001\np200\ncSafari\nf7\nn127.0.0.1:52001->127.0.0.1:9090\np300\ncWebKit\nf8\nn[::1]:52002->[::1]:9090\nf9\nn127.0.0.1:52003->127.0.0.1:443\n"
    let m = ProcessLookup.parseLsof(out, proxyPort: 9090, excludingPID: 100)
    #expect(m == [52001: 200, 52002: 300])
}
@Test func resolverReturnsNilWhenPortAbsent() async {
    let r = ProcessResolver()
    let t = ContinuousClock.now
    #expect(await r.resolve(port: 1, proxyPort: 1) == nil)      // 아무도 안 듣는 포트 → lsof 결과 없음 → 재시도 1회 후 nil
    #expect(ContinuousClock.now - t < .seconds(8))
}
```
`SessionDocumentTests.swift`에 추가:
```swift
@Test func roundTripProcessesAndToleratesMissingKey() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).eyeproxy"); defer { try? FileManager.default.removeItem(at: url) }
    let f = Flow.fixture(client: "127.0.0.1", decrypted: false); let p = ProcessIdentity(pid: 1, path: "/Applications/Safari.app/Contents/MacOS/Safari")
    try SessionDocument.save(flows: [f], connectionLog: [], processes: [f.id: p], to: url)
    #expect(try SessionDocument.load(from: url).processes == [f.id: p])
    try SessionDocument.save(flows: [f], connectionLog: [], to: url)
    #expect(try SessionDocument.load(from: url).processes.isEmpty)
}
```
기존 테스트의 `SessionDocument.load(from:)` 튜플 사용처(`loaded.flows` 등)는 그대로 컴파일된다.

- [ ] **Step 2: 실패 확인** — `--filter "identityDerives|parseLsof|resolverReturns|roundTripProcesses"` → 컴파일 실패.

- [ ] **Step 3: 구현**
  - `parseLsof`: `p`로 pid 전환, `n` 줄을 `->`로 나눠 왼쪽(로컬) `host:port`의 포트를 뽑되 오른쪽 포트가 `proxyPort`인 줄만 채택. `[::1]:port` 형식은 마지막 `:` 뒤를 포트로. `f`·`c` 줄은 무시. `excludingPID`는 건너뜀.
  - `ProcessResolver.resolve`: 캐시 `[Int: ProcessIdentity]` 히트면 즉시 반환. 아니면 pending에 넣고 배치 Task(없으면 생성: `Task.sleep(100ms)` → `Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(proxyPort)", "-F", "pcn"])` → `parseLsof(excludingPID: ProcessInfo.processInfo.processIdentifier)` → 각 pid를 `ResponsiblePID.lookup`으로 바꾸고 `proc_pidpath`로 경로를 얻어 `ProcessIdentity(pid:path:)`를 캐시)를 await. 없으면 `Task.sleep(300ms)` 후 배치 한 번 더, 그래도 없으면 nil(캐시하지 않음). `proc_pidpath`는 `import Foundation`만으로 호출된다(`[CChar](repeating: 0, count: Int(MAXPATHLEN))`).
  - `ResponsiblePID.lookup`: `dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")`을 `@convention(c) (pid_t) -> pid_t`로 캐스팅해 1회 캐시(`static let`). nil이거나 결과 ≤ 0이면 입력 pid.
  - `SessionDocument.Index`에 `var processes: [String: ProcessIdentity]?`(키 `FlowID.rawValue.uuidString`). 버전 1 유지.

- [ ] **Step 4: 통과 확인** — Kit 82 passed.

- [ ] **Step 5: 커밋** — `feat(kit): lsof 기반 로컬 프로세스 귀속과 세션 저장`

---

### Task 5: Kit — `FlowScope`·`FlowFilter.process`·`SidebarTree`

**Files:**
- Modify: `Packages/EyeProxyKit/Sources/EyeProxyKit/FlowFilter.swift`
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/SidebarTree.swift`
- Test: `FlowFilterTests.swift`, 새 파일 `SidebarTreeTests.swift`

**Interfaces:**
- Consumes: `ProcessIdentity`(Task 4), `Device`/`DeviceKind`(기존).
- Produces:
  ```swift
  public struct FlowScope: Hashable, Sendable { public var device: String?; public var process: String?; public var host: String?; public init(device: String? = nil, process: String? = nil, host: String? = nil) }
  // FlowFilter
  public var process: String?                                 // groupKey. 귀속 없는 흐름의 키는 "unknown"
  public func matches(_ flow: Flow, process: String?) -> Bool  // 기존 matches(_:)는 process: nil로 위임
  public static func sameDevice(_ a: String, _ b: String) -> Bool  // 둘 다 루프백("127.0.0.1"/"::1")이면 true, 아니면 ==
  public static let unknownProcessKey = "unknown"
  // SidebarTree.swift
  public struct HostNode: Identifiable, Hashable, Sendable { public let host: String; public let count: Int; public var id: String { host } }
  public struct AppNode: Identifiable, Sendable { public let groupKey: String; public let displayName: String; public let path: String?; public let count: Int; public let hosts: [HostNode]; public var id: String { groupKey } }
  public struct DeviceNode: Identifiable, Sendable { public let address: String; public let displayName: String; public let kind: DeviceKind; public let count: Int; public let apps: [AppNode]; public let hosts: [HostNode]; public var id: String { address } }
  public struct SidebarTree: Sendable {
      public let pinned: [HostNode]; public let devices: [DeviceNode]; public let hosts: [HostNode]
      public static func build(flows: [Flow], attribution: [FlowID: ProcessIdentity], devices: [Device], pinned: [String], runtimes: [String: String]) -> SidebarTree
  }
  ```

- [ ] **Step 1: 실패 테스트 작성**

`FlowFilterTests.swift`에 추가:
```swift
@Test func filterProcessAndLoopback() {
    let f = Flow.fixture(client: "::1", decrypted: true)
    #expect(FlowFilter(device: "127.0.0.1").matches(f)); #expect(FlowFilter.sameDevice("::1", "127.0.0.1") && !FlowFilter.sameDevice("::1", "10.0.0.1"))
    var p = FlowFilter(); p.process = "/a/Safari"
    #expect(p.matches(f, process: "/a/Safari") && !p.matches(f, process: nil) && !p.matches(f, process: "/b"))
    p.process = FlowFilter.unknownProcessKey; #expect(p.matches(f, process: nil))
}
```
`SidebarTreeTests.swift`:
```swift
private func flow(_ client: String, _ url: String) -> Flow { var f = Flow.fixture(url: url, method: "GET", status: 200); f = Flow(id: f.id, clientAddress: client, startedAt: f.startedAt, request: f.request, response: f.response); return f }

@Test func treeSplitsMacByAppAndRemoteByHost() {
    let a = flow("127.0.0.1", "https://www.tving.com/"), b = flow("127.0.0.1", "https://api.tving.com/x"), c = flow("::1", "https://api.tving.com/y"), d = flow("192.168.0.9", "https://api.tving.com/z")
    let safari = ProcessIdentity(pid: 1, path: "/Applications/Safari.app/Contents/MacOS/Safari")
    let sim = ProcessIdentity(pid: 2, path: "/x/CoreSimulator/Devices/U1/data/TVING.app/TVING")
    let t = SidebarTree.build(flows: [a, b, c, d], attribution: [a.id: safari, b.id: sim], devices: [Device(address: "192.168.0.9", name: "거실 TV", kind: .appleTV, lastSeen: .now)], pinned: ["gw.tving.com", "api.tving.com"], runtimes: ["U1": "tvOS 18.1"])
    #expect(t.pinned.map(\.host) == ["gw.tving.com", "api.tving.com"] && t.pinned.map(\.count) == [0, 3])
    #expect(t.devices.count == 2)
    let mac = t.devices.first { $0.address == "127.0.0.1" }!
    #expect(mac.displayName == "이 Mac" && mac.kind == .thisMac && mac.count == 3 && mac.hosts.isEmpty)
    #expect(mac.apps.map(\.displayName) == ["Safari", "TVING (tvOS 시뮬레이터)", "기타"] || mac.apps.map(\.displayName) == ["TVING (tvOS 시뮬레이터)", "Safari", "기타"])
    #expect(mac.apps.last!.groupKey == FlowFilter.unknownProcessKey && mac.apps.last!.hosts == [HostNode(host: "api.tving.com", count: 1)])
    let tv = t.devices.first { $0.address == "192.168.0.9" }!
    #expect(tv.displayName == "거실 TV" && tv.kind == .appleTV && tv.apps.isEmpty && tv.hosts == [HostNode(host: "api.tving.com", count: 1)])
    #expect(t.hosts.map(\.host) == ["api.tving.com", "www.tving.com"])
}
@Test func treeMergesLoopbackAddresses() {
    let t = SidebarTree.build(flows: [flow("::1", "https://a/"), flow("127.0.0.1", "https://a/")], attribution: [:], devices: [], pinned: [], runtimes: [:])
    #expect(t.devices.count == 1 && t.devices[0].address == "127.0.0.1" && t.devices[0].count == 2)
}
```

- [ ] **Step 2: 실패 확인** — `--filter "filterProcess|treeSplits|treeMerges"` → 컴파일 실패.

- [ ] **Step 3: 구현** — `build`: 흐름을 `sameDevice` 기준으로 묶되 루프백은 키 `"127.0.0.1"`. 기기 표시명·종류는 `devices`에서 주소가 같은 항목(없으면 루프백 → "이 Mac"/`.thisMac`, 아니면 주소/`.unknown`). 기기 정렬은 그 기기 흐름의 최대 `startedAt` 내림차순. `.thisMac`이면 `attribution[flow.id]?.groupKey ?? unknownProcessKey`로 앱 노드(count 내림차순, "기타"는 항상 마지막, 표시명은 `displayName(runtimes:)`, "기타"의 path nil), 각 앱 아래 호스트 사전순. 원격은 호스트 사전순. `pinned`는 설정 순서, count는 전체 흐름 중 해당 호스트 수. `hosts`는 전체 사전순.

- [ ] **Step 4: 통과 확인** — Kit 85 passed.

- [ ] **Step 5: 커밋** — `feat(kit): 사이드바 트리와 프로세스 필터`

---

### Task 6: Kit — `CookieParser`·`JSONHighlighter`·`JSONTreeNode`·`DecodedBody.json(pretty:raw:)`

**Files:**
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Text/CookieParser.swift`
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Text/JSONHighlighter.swift`
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Text/JSONTreeNode.swift`
- Modify: `Packages/EyeProxyKit/Sources/EyeProxyKit/BodyDecoder.swift:5,16`
- Test: 새 `CookieParserTests.swift`, `JSONHighlighterTests.swift`, `JSONTreeNodeTests.swift`; `BodyDecoderTests.swift`의 `.json(pretty:)` 비교 → `.json(pretty: …, raw: …)`로 갱신

**Interfaces:**
- Produces:
  ```swift
  public enum DecodedBody { case empty, json(pretty: String, raw: String), text(String), image(Data), html(String), binary(Data) }   // raw = 압축 해제 후 원문
  public enum CookieParser {
      public static func requestCookies(_ cookieHeader: String) -> [HTTPHeader]       // "a=1; b=2" → [a:1, b:2]. "="없는 조각은 name만·value "". 빈 조각 무시, 앞뒤 공백 제거
      public static func responseCookies(_ setCookieHeaders: [String]) -> [HTTPHeader] // 각 헤더 첫 "name=value" + 나머지 속성은 value 뒤에 "; Path=/; HttpOnly"로 그대로
  }
  public struct JSONToken: Equatable, Sendable { public enum Kind: Sendable { case key, string, number, keyword }; public let kind: Kind; public let range: NSRange /* UTF-16 */ }
  public enum JSONHighlighter { public static func tokens(_ pretty: String) -> [JSONToken] }   // BodyDecoder pretty 출력("key" : value) 전제. 문자열 뒤에 공백·":"가 오면 key
  public struct JSONTreeNode: Identifiable, Sendable {
      public let id: Int; public let key: String; public let preview: String; public let children: [JSONTreeNode]?
      public static func parse(pretty: String) -> [JSONTreeNode]   // 원문 키 순서. 객체 "{N keys}", 배열 "[N items]", 그 외 리터럴 원문. 루트가 스칼라면 [그 노드]
  }
  ```

- [ ] **Step 1: 실패 테스트 작성**

```swift
// CookieParserTests.swift
@Test func cookieParserTolerates() {
    #expect(CookieParser.requestCookies(" a=1;  b=x=y;;novalue ; ") == [.init(name: "a", value: "1"), .init(name: "b", value: "x=y"), .init(name: "novalue", value: "")])
    #expect(CookieParser.responseCookies(["sid=abc; Path=/; HttpOnly", "bad"]) == [.init(name: "sid", value: "abc; Path=/; HttpOnly"), .init(name: "bad", value: "")])
}
// JSONHighlighterTests.swift
@Test func highlighterClassifiesPrettyJSON() {
    let s = "{\n  \"k\" : \"v\",\n  \"n\" : -1.5e3,\n  \"b\" : true,\n  \"z\" : null\n}"
    let t = JSONHighlighter.tokens(s)
    #expect(t.map(\.kind) == [.key, .string, .key, .number, .key, .keyword, .key, .keyword])
    #expect((s as NSString).substring(with: t[1].range) == "\"v\"" && (s as NSString).substring(with: t[3].range) == "-1.5e3")
}
@Test func highlighterRangesSurviveNonASCII() {
    let s = "{\n  \"한글\" : \"é\\\"x\",\n  \"n\" : 1\n}"
    let t = JSONHighlighter.tokens(s)
    #expect((s as NSString).substring(with: t[0].range) == "\"한글\"" && (s as NSString).substring(with: t[1].range) == "\"é\\\"x\"" && (s as NSString).substring(with: t[3].range) == "1")
}
// JSONTreeNodeTests.swift
@Test func treeNodesKeepOriginalOrderAndLiterals() {
    let n = JSONTreeNode.parse(pretty: "{\n  \"z\" : [\n    1,\n    {}\n  ],\n  \"a\" : 12345678901234567890,\n  \"s\" : \"x\"\n}")
    #expect(n.map(\.key) == ["z", "a", "s"] && n[0].preview == "[2 items]" && n[0].children?.map(\.preview) == ["1", "{0 keys}"] && n[1].preview == "12345678901234567890" && n[2].preview == "\"x\"" && n[2].children == nil)
    #expect(JSONTreeNode.parse(pretty: "\"s\"").map(\.preview) == ["\"s\""])
}
```

- [ ] **Step 2: 실패 확인** — `--filter "cookieParser|highlighter|treeNodes"` → 컴파일 실패.

- [ ] **Step 3: 구현** — 토크나이저 하나(`JSONScanner`, 내부)를 `Array(pretty.utf16)` 위에서 돌려 `(kind, NSRange)`를 내고, `JSONHighlighter`와 `JSONTreeNode.parse`가 공유한다. 문자열은 `"`에서 `\` 이스케이프를 건너뛰며 닫는 `"`까지; 숫자는 `-0-9.eE+`; 키워드 `true/false/null`. 트리는 `{`/`[` 스택으로 구성, 배열 자식 key는 인덱스 문자열. `BodyDecoder.decode`의 json 분기에서 `raw: s`를 함께 돌려준다.

- [ ] **Step 4: 통과 확인** — Kit 89 passed(기존 BodyDecoder 테스트 갱신 포함).

- [ ] **Step 5: 커밋** — `feat(kit): 쿠키 파서·JSON 토큰·원문 순서 JSON 트리`

---

### Task 7: 앱 — `AppModel` 배선

**Files:**
- Modify: `EyeProxy/AppModel.swift`(14-18 `SidebarItem`, 32-35, 180-200 `handle`/`clear`, 208-232 세션 저장·열기, 246-260 목록)
- Modify: `EyeProxy/Views/Sidebar/SidebarView.swift`, `EyeProxy/Views/FlowList/FlowListView.swift` — 컴파일만 유지(`.device`/`.host` 태그를 아래 새 `SidebarItem`에 맞춤; 모양은 Task 9·10에서)

**Interfaces:**
- Consumes: Task 2–6 전부.
- Produces(앱 내부):
  ```swift
  enum SidebarItem: Hashable { case allFlows, host(String), scope(FlowScope) }
  // AppModel
  let processes = ProcessRegistry(); @ObservationIgnored let resolver = ProcessResolver()
  var sortOrder: [KeyPathComparator<FlowRow>] = [KeyPathComparator(\.number)]
  var visibleRows: [FlowRow]          // visibleFlows → FlowRow(number: session.number) → sorted(using: sortOrder)
  var sidebarTree: SidebarTree        // SidebarTree.build(flows: session.flows, attribution: processes.attribution, devices: devices.devices, pinned: settings.pinnedHosts, runtimes:)
  var simulatorRuntimes: [String: String]   // computed: bootedSimulators의 udid → runtime(기기 창을 연 적 없으면 [:])
  func processKey(for flow: Flow) -> String?  // processes.attribution[flow.id]?.groupKey
  ```

- [ ] **Step 1: 구현**
  - `visibleFlows`: `.scope(s)`면 `f.device = s.device; f.process = s.process; f.host = s.host`, 필터는 `f.matches(flow, process: processKey(for: flow))`. `.host(h)`는 기존대로.
  - `handle(event)`: `requestStarted(flow)`이고 `FlowFilter.sameDevice(flow.clientAddress, "127.0.0.1")`이고 `flow.clientPort != nil`이고 `runningPort != nil`이면 `Task { if let id = await resolver.resolve(port:proxyPort:) { processes.set(id, for: flow.id) } }`.
  - `clear()`: `processes.clear()`, `.scope`도 `.allFlows`로. `openSession`: `processes.replace(loaded.processes)`, `.allFlows`. `saveSession`: `processes: processes.attribution` 전달.
  - `hosts`는 제거(사이드바가 `sidebarTree.hosts`를 씀).
  - `SidebarView`/`FlowListView`에서 `.device(...)`/`number[...]` 참조를 `.scope(FlowScope(device:))`/`row.number`로 바꿔 컴파일만 통과(`Table(rows...)`는 `model.visibleRows`로, 컬럼 클로저 타입은 `FlowRow`).

- [ ] **Step 2: 빌드 확인** — `xcodegen generate && xcodebuild build … | grep -E "warning:|error:|BUILD"` → `BUILD SUCCEEDED`, 경고 0.

- [ ] **Step 3: 커밋** — `feat(app): 프로세스 귀속·정렬·트리 상태 배선`

---

### Task 8: 앱 — 색 세트·태그·목록

**Files:**
- Create: `EyeProxy/Assets.xcassets/Colors/<이름>.colorset/Contents.json` × 13
- Create: `EyeProxy/Views/Shared/Tags.swift`
- Modify: `EyeProxy/Views/FlowList/FlowListView.swift`

**Interfaces:**
- Consumes: `FlowRow`, `AppModel.visibleRows`·`sortOrder`(Task 7).
- Produces: `struct MethodTag: View { let method: String }`, `struct StatusTag: View { let flow: Flow }`, `enum FlowColors { static func method(_ m: String) -> Color; static func status(_ flow: Flow) -> Color }`.

- [ ] **Step 1: 색 세트** — 이름·(라이트, 다크) hex:
  `MethodGet`(#1A6FD1, #6DB3FF) `MethodPost`(#C2690A, #FFB04D) `MethodPut`(#7A3FC4, #C49BFF) `MethodDelete`(#C62828, #FF7B7B) `MethodOther`(#6E6E73, #9A9AA0) `StatusSuccess`(#1F8A3F, #5FD08A) `StatusRedirect`(#B26A00, #FFC46B) `StatusError`(#C62828, #FF7B7B) `StatusPending`(#6E6E73, #9A9AA0) `JSONKey`(#0B4FA8, #9CDCFE) `JSONString`(#A31515, #CE9178) `JSONNumber`(#098658, #B5CEA8) `JSONKeyword`(#0000FF, #569CD6).
  각 `Contents.json`(예: MethodGet):
  ```json
  {"colors":[{"color":{"color-space":"srgb","components":{"alpha":"1.000","blue":"0xD1","green":"0x6F","red":"0x1A"}},"idiom":"universal"},{"appearances":[{"appearance":"luminosity","value":"dark"}],"color":{"color-space":"srgb","components":{"alpha":"1.000","blue":"0xFF","green":"0xB3","red":"0x6D"}},"idiom":"universal"}],"info":{"author":"xcode","version":1}}
  ```
  `Colors` 폴더에도 `{"info":{"author":"xcode","version":1}}` Contents.json.

- [ ] **Step 2: 태그** — `Tags.swift`: 캡슐, `.font(.system(size: 11, weight: .semibold)).monospacedDigit()`, `padding(.horizontal, 6).padding(.vertical, 1)`, `foregroundStyle(color)`, `background(color.opacity(0.15), in: Capsule())`. Method 매핑 GET→MethodGet, POST→MethodPost, PUT/PATCH→MethodPut, DELETE→MethodDelete, 그 외 MethodOther. Status: 2xx Success, 3xx Redirect, ≥400·오류 Error(오류 텍스트 "오류"), 대기 Pending("…"). `StatusTag`가 기존 `StatusText`를 대체한다.

- [ ] **Step 3: 목록** — `Table(model.visibleRows, selection:, sortOrder: $model.sortOrder, columnCustomization:)`. 컬럼 `#`(`value: \.number`, `Text(row.number…).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)`), Method(`\.method`, `MethodTag`), URL(`\.url`, `Text(host).foregroundStyle(.primary) + Text(pathAndQuery).foregroundStyle(.secondary)`, 한 줄·중간 생략), Status(`\.status`, `StatusTag`), Size(`\.size`, 기존 `bytes`), Time(`\.durationMS`), 숨김: Host(`\.host`)·Content-Type·기기·시작 시각(`\.startedAt`)·**앱**(`model.processes.attribution[row.id]?.displayName(runtimes:)`, 기본 숨김, customizationID "app"). `.alternatingRowBackgrounds(.disabled)`. 컨텍스트 메뉴 유지.

- [ ] **Step 4: 빌드 확인** — 경고 0.
- [ ] **Step 5: 커밋** — `feat(app): Method·Status 태그와 정렬 가능한 목록`

---

### Task 9: 앱 — 트리 사이드바

**Files:**
- Modify: `EyeProxy/Views/Sidebar/SidebarView.swift`

**Interfaces:**
- Consumes: `AppModel.sidebarTree`, `settings.pinnedHosts`·`togglePin`, `SidebarItem.scope`.

- [ ] **Step 1: 구현** — `List(selection: $model.sidebarSelection)`:
  - 맨 위 "전체"(`tray.full`, badge `session.flows.count`, `.allFlows`).
  - `Section("고정")`: `tree.pinned` 각각 `Label(host, systemImage: "pin.fill")`, badge, `.tag(SidebarItem.host(host))`. 비어 있으면 `Text("호스트를 우클릭해 고정").foregroundStyle(.secondary)`.
  - `Section("기기")`: `tree.devices` 각 `DisclosureGroup`(기본 펼침, `@State expanded: Set<String>`은 두지 않고 `DisclosureGroup(isExpanded:)` 없이 기본 펼침) 라벨 = 기기(`laptopcomputer`/`appletv`(appleTV)/`iphone`/`ipad`/`display`), `.tag(.scope(FlowScope(device: address)))`. 자식: `.thisMac`이면 앱 노드 `DisclosureGroup`(아이콘 `path.map { Image(nsImage: NSWorkspace.shared.icon(forFile: $0)) }`를 16×16으로, 없으면 `app.dashed`; `.tag(.scope(.init(device:, process: groupKey)))`), 그 아래 호스트 `.tag(.scope(.init(device:, process:, host:)))`. 원격은 호스트 `.tag(.scope(.init(device:, host:)))`.
  - `Section("도메인")`: `tree.hosts` → `.tag(.host(host))`.
  - 호스트가 있는 모든 행에 `.contextMenu { Button(pinned ? "고정 해제" : "고정") { settings.togglePin(host) } }`.
  - 새 문자열 "고정"·"고정 해제"·"호스트를 우클릭해 고정"·"기타"(Kit에서 쓰므로 Kit 쪽은 `String(localized:)` 없이 리터럴 — Kit는 카탈로그가 없다)를 xcstrings에 추가.

- [ ] **Step 2: 빌드 확인** — 경고 0.
- [ ] **Step 3: 커밋** — `feat(app): 고정 호스트·기기·앱 트리 사이드바`

---

### Task 10: 앱 — 상세 상단 바·Key/Value 표·쿠키 탭

**Files:**
- Create: `EyeProxy/Views/Detail/FlowHeaderBar.swift`
- Create: `EyeProxy/Views/Detail/KeyValueTable.swift`(기존 `HeadersView.swift` 삭제)
- Modify: `EyeProxy/Views/Detail/FlowDetailView.swift`

**Interfaces:**
- Consumes: `MethodTag`/`StatusTag`(Task 8), `CookieParser`(Task 6), `CurlExport`.
- Produces: `struct KeyValueTable: View { let rows: [HTTPHeader]; let emptyTitle: LocalizedStringKey }`, `struct FlowHeaderBar: View { let flow: Flow }`.

- [ ] **Step 1: `FlowHeaderBar`** — `HStack(alignment: .firstTextBaseline, spacing: 10)`: `MethodTag` · `StatusTag` · URL `Text(attributed)`(`AttributedString`: `scheme://` secondary, host `.primary`+`.semibold`, path `Color.accentColor`, 쿼리는 `?`·`&`·`=` secondary, 키 primary, 값 secondary; `.font(.system(.body, design: .monospaced))`, 줄바꿈, `.textSelection(.enabled)`) · `Spacer` · `Button("복사") { pasteboard ← flow.request.url }` · `Button("cURL") { model.copyCurl(flow.id) }`(`.buttonStyle(.accessoryBar)`). `padding(.horizontal, 12).padding(.vertical, 8)`, 배경 `Color(nsColor: .controlBackgroundColor)`, 아래 `Divider`.

- [ ] **Step 2: `KeyValueTable`** — `ScrollView { LazyVStack(spacing: 0) { ForEach(rows.indices) { row } } }`. 행 = `HStack(alignment: .firstTextBaseline, spacing: 12) { Text(name).fontWeight(.semibold).foregroundStyle(.secondary).frame(width: 160, alignment: .leading) ; Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }`, `padding(.horizontal, 12).padding(.vertical, 5)`, `onHover`로 `Color(nsColor: .quaternaryLabelColor).opacity(…)` 배경, 행 사이 `Divider().opacity(0.5)`, `.contextMenu { "값 복사", "이름: 값 복사" }`. 비어 있으면 `ContentUnavailableView(emptyTitle, systemImage: "list.bullet")`.

- [ ] **Step 3: `FlowDetailView`** — 선택된 흐름이 있으면 `VStack(spacing: 0) { FlowHeaderBar(flow) ; 기존 HSplit/VSplit }`. `MessagePane`: `Tab`에 `.cookies` 추가; 요청 탭 헤더·쿼리·본문·쿠키, 응답 탭 헤더·본문·쿠키. 쿠키 rows = 요청 `CookieParser.requestCookies(header("Cookie") ?? "")`, 응답 `responseCookies(headers.filter { name ~= "Set-Cookie" }.map(\.value))`. `MessagePane` 상단 `summary` Text는 제거(헤더 바가 대신한다), 제목 + Picker만 남긴다. 새 문자열 "쿠키"·"복사"·"값 복사"·"이름: 값 복사"·"쿼리 없음"·"쿠키 없음"을 xcstrings에 추가.

- [ ] **Step 4: 빌드 확인** — 경고 0. 앱을 띄워 Cookie 값이 줄바꿈되고 URL이 상단에서 줄바꿈되는지 눈으로 확인.
- [ ] **Step 5: 커밋** — `feat(app): 상세 상단 바·Key/Value 표·쿠키 탭`

---

### Task 11: 앱 — `CodeTextView`와 본문(Pretty·Tree·Raw·줄바꿈)

**Files:**
- Create: `EyeProxy/Views/Detail/CodeTextView.swift`
- Modify: `EyeProxy/Views/Detail/BodyView.swift`(`MonoText`·`LargeText` 제거, `JSONBody`·`HTMLBody` 수정)
- Modify: `EyeProxy/Views/Detail/JSONTreeView.swift`(`JSONNode` 삭제, Kit `JSONTreeNode` 사용)

**Interfaces:**
- Consumes: `JSONHighlighter`, `JSONTreeNode`, `DecodedBody.json(pretty:raw:)`(Task 6), `settings.wrapLongLines`(Task 3).
- Produces: `struct CodeTextView: NSViewRepresentable { let text: NSAttributedString; let wrap: Bool }`.

- [ ] **Step 1: `CodeTextView`** — `NSTextView.scrollableTextView()`; 읽기 전용·선택 가능, `font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)`, `textContainerInset = (8, 6)`, `backgroundColor = .textBackgroundColor`, `textColor = .textColor`. `wrap`: true → `textContainer.widthTracksTextView = true`, `containerSize.width = scroll.contentSize.width`, `isHorizontallyResizable = false`, `hasHorizontalScroller = false`; false → 반대(`containerSize = (.greatestFiniteMagnitude, …)`, `maxSize` 동일). `updateNSView`는 `text`가 바뀌면 `textStorage.setAttributedString`, `wrap`이 바뀌면 재설정. 줄번호: `final class LineNumberRuler: NSRulerView`(`ruleThickness` = 자릿수×8+12, `drawHashMarksAndLabels`에서 보이는 glyph 범위의 각 줄 첫 글자 rect에 번호를 `secondaryLabelColor`·11pt 모노로 그림, 배경 `windowBackgroundColor`), `scroll.hasVerticalRuler = true; rulersVisible = true`, 텍스트 변경·스크롤·프레임 변경 시 `needsDisplay`.

- [ ] **Step 2: `BodyView`** — 상단 바 `HStack { 모드 Picker(JSON일 때 Pretty·Tree·Raw; 그 외 없음) ; Spacer ; Toggle("줄바꿈", isOn: $settings.wrapLongLines).toggleStyle(.checkbox) ; Text(summary).font(.caption).foregroundStyle(.secondary) }`. 본문 텍스트는 전부 `CodeTextView`: Pretty = `NSAttributedString(pretty)` + 토큰에 `.foregroundColor` 적용(`NSColor(named:)` JSONKey 등; `pretty.utf8.count > 256_000`이면 색 없이), Raw = `raw`, 텍스트/바이너리 hex = 그대로, HTML 소스 = `CodeTextView`. 2MB 컷·"…(2MB까지만 표시)"·이미지 미리보기 유지. `.task(id: data.count)` 안에서 토큰 계산까지 `Task.detached`로.

- [ ] **Step 3: `JSONTreeView`** — `OutlineGroup(nodes, children: \.children)`에 `JSONTreeNode`; `JSONBody`의 `.task(id: mode)`에서 `JSONTreeNode.parse(pretty:)`.

- [ ] **Step 4: 빌드·확인** — 경고 0. 앱에서 JSON 응답 선택: 줄번호·색·줄바꿈 토글 동작, Tree 키 순서가 원문과 같음, 1MB 이상 JSON에서 멈추지 않음(`curl -o` 없이 큰 응답은 image.tving.com 같은 바이너리로 hex 확인).

- [ ] **Step 5: 커밋** — `feat(app): 줄번호·색·줄바꿈 본문 뷰`

---

### Task 12: 마무리 — 문자열·문서·전체 검증

**Files:**
- Modify: `EyeProxy/Localizable.xcstrings`(누락 문자열 점검)
- Modify: `docs/superpowers/plans/2026-11-05-eyeproxy-p1-handover.md` 3절(해결된 백로그 항목에 "→ flow-readability에서 해결" 표시: `#` 컬럼 안정 ID, 앱별 그룹 PID 귀속, JSON Tree 키 순서, 기기 배지 카운트 불일치)
- Modify: `README.md` "기기 연결" 아래 한 줄: 사이드바가 Mac 트래픽을 앱별로 나누며 Safari 등은 책임 앱으로 묶인다.

- [ ] **Step 1: 문자열 점검** — `grep -rhoE 'Text\("[^"]+"\)|Label\("[^"]+"|Button\("[^"]+"|Section\("[^"]+"|Toggle\("[^"]+"' EyeProxy/Views | sort -u`로 뽑은 리터럴이 전부 xcstrings에 있는지 확인, 없으면 추가.
- [ ] **Step 2: 전체 테스트** — Core 37, Kit 89 passed.
- [ ] **Step 3: 전체 빌드** — 경고 0. `git status`에 `.superpowers/`·`.claude/`가 없음.
- [ ] **Step 4: 커밋** — `docs: 핸드오버 백로그·README 갱신`
- [ ] **Step 5: 사용자 확인 요청** — worktree의 Debug 앱을 실행해 Proxyman 캡처(`~/Desktop/proxyman_ref/`)와 비교: 스펙 §7의 5항목. 확인 뒤 PR(`superpowers:finishing-a-development-branch`).
