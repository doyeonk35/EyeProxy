# EyeProxy Tools 1차 묶음 (P2 조작 도구) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Proxyman과 같은 동작의 Breakpoint·Map Local·Map Remote·Block/Allow List·No Caching·Network Conditions·Compose/Repeat와 공통 규칙 엔진, Proxyman 규칙 가져오기를 EyeProxy에 넣는다.

**Architecture:** Core에는 도구를 모르는 훅만 더한다(연결 끊기, CONNECT 판정, 흐름 주석, 터널 속도 조절). 규칙 모델·매칭·저장·Proxyman 형식·도구별 인터셉터는 Kit에 두고, `ToolPipeline`이 규칙과 스위치로 `InterceptorChain`을 조립한다. 앱은 Proxyman 배치를 따른 도구 창·편집기·메뉴만 가진다.

**Tech Stack:** Swift 6, SwiftUI(+ AppKit NSTextView), SwiftNIO, Swift Testing, XcodeGen

**Spec:** `docs/superpowers/specs/2026-11-06-eyeproxy-tools-p2-design.md` (상위: `docs/superpowers/specs/2026-11-05-eyeproxy-design.md`)

## Global Constraints

- macOS 15+, Swift 6 strict concurrency(경고 0 유지).
- 모듈 의존: `EyeProxy`(앱) → `EyeProxyKit` → `EyeProxyCore`. 역방향 import 금지. Core는 도구 이름·UI를 모른다.
- 외부 패키지 허용 목록만: swift-nio, swift-nio-ssl, swift-nio-extras, swift-certificates, swift-asn1, swift-crypto, Sparkle. 정규식은 `NSRegularExpression`.
- "Tools는 인터셉터 하나 + 뷰 하나"(CLAUDE.md).
- 커밋 메시지 `<type>(<scope>): <한국어 요약>`, 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- 앱 타깃에 파일을 더하면 `xcodegen generate` 후 빌드.
- 테스트: `swift test --package-path Packages/EyeProxyCore`, `swift test --package-path Packages/EyeProxyKit`. 앱 빌드: `xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates`.
- **Proxyman 데이터 폴더(`~/Library/Application Support/com.proxyman.NSProxy`)에 절대 쓰지 않는다.** 테스트는 픽스처 폴더만 쓴다. 에이전트는 Proxyman 앱을 조작하지 않는다(규칙 추가 시 도구가 자동으로 켜져 사용자 트래픽이 바뀐 사례).
- 에이전트는 시스템 프록시·키체인·CA 설정을 바꾸는 명령을 실행하지 않는다.
- 레포는 공개다. 사내 도메인·로컬 경로를 코드·픽스처·문서에 넣지 않는다(픽스처 host는 `api.example.com` 등).
- UI 문구는 한국어, 도구 이름(Map Local, Breakpoint 등)과 Proxyman 버튼 이름(Continue Original, Apply & Execute 등)은 영어 그대로.
- 새 Map Local·Map Remote 규칙의 "쿼리 무시" 기본값 = 켜짐. Proxyman에서 가져온 규칙 = 꺼짐.
- 가져오기는 도구 스위치를 켜지 않는다. ⌘N은 편집기만 열고 저장 전에는 규칙을 추가하지 않는다.

## Review Focus

1. **Breakpoint로 멈춘 동안 클라이언트가 연결을 끊음** → 대기 목록에서 사라지고 continuation이 새지 않는다. (Task 11 테스트)
2. **Map Local 응답 파일이 요청 시점에 없거나 읽기 실패** → 실제 서버 응답으로 넘기고 흐름에 "Map Local 파일 없음" 주석. 크래시·빈 200 금지. (Task 7 테스트)
3. **망가진 Proxyman JSON**(모르는 노드 종류, 필드 누락, 잘못된 `regex` 값) → 알아는 규칙만 들이고 건너뛴 개수를 돌려준다. JSON이 아닌 파일만 오류. (Task 5 테스트)
4. **잘못된 정규식 패턴** → 그 규칙은 절대 안 맞고 `validationError`가 있다. 크래시 금지. (Task 4 테스트)
5. **비기본 포트·IPv6 리터럴 URL** → 매칭 문자열이 `scheme://host:port/path`, `scheme://[::1]:8080/path`로 만들어져 패턴과 비교된다. (Task 4 테스트)

---

## 파일 구조

```
Packages/EyeProxyCore/Sources/EyeProxyCore/
  Interceptor.swift          (수정) RequestDecision.drop, ResponseDecision, FlowContext 확장, Connect 훅 타입·체인
  Flow.swift                 (수정) FlowAnnotation, Flow.annotations, FlowEvent.annotated
  ProxyServer.swift          (수정) exchange 결과 enum, respond도 응답 체인 통과
  ProxyConnectionHandler.swift (수정) drop 처리, CONNECT 판정 훅, 미기록 터널, MITM 주석
  TunnelGlueHandler.swift    (수정) TunnelShaping 지연
Packages/EyeProxyKit/Sources/EyeProxyKit/
  Rules/MatchRule.swift          매칭 규칙·URL 문자열·호스트 패턴
  Rules/RuleTree.swift           ToolRule 프로토콜, RuleNode/RuleFolder/RuleTree, Proxyman 노드 코덱(관대한 디코드)
  Rules/ToolSwitches.swift       도구 스위치(Codable)
  Rules/RuleStore.swift          @MainActor 저장소(도구별 JSON 파일)
  Tools/MapLocal/{MapLocalRule,HTTPMessageFile,MapLocalInterceptor}.swift
  Tools/MapRemote/{MapRemoteRule,MapRemoteInterceptor}.swift
  Tools/BlockAllow/{BlockRule,AllowRule,BlockAllowInterceptors}.swift
  Tools/NoCaching/NoCachingInterceptor.swift
  Tools/NetworkConditions/{NetworkProfile,NetworkConditionRule,NetworkConditionsInterceptor}.swift
  Tools/Breakpoint/{BreakpointRule,BreakpointCenter,BreakpointInterceptor,BreakpointTemplate}.swift
  Tools/ToolPipeline.swift       체인 조립·자동 복호화 호스트
  Import/{ProxymanImporter,RuleBundle}.swift
  Compose/{CurlParser,ComposeClient}.swift
EyeProxy/
  AppModel+Tools.swift           RuleStore·BreakpointCenter 보유, 파이프라인 적용
  Commands/ToolsCommands.swift   Tools·Flow 메뉴
  Views/Tools/{ToolWindow,MatchRuleFields,TestRuleSheet,MapLocalEditor,HTTPMessageEditor,MapRemoteSheet,
               BreakpointRuleSheet,BreakpointWindow,BreakpointTemplatesWindow,BlockAllowSheets,NetworkConditionsSheet,
               ImportProxymanSheet}.swift
  Views/Compose/ComposeView.swift
```

---

### Task 1: Core — 연결 끊기·응답 판정·흐름 주석

**Files:**
- Modify: `Packages/EyeProxyCore/Sources/EyeProxyCore/Interceptor.swift`, `Flow.swift`, `ProxyServer.swift`, `ProxyConnectionHandler.swift`
- Test: `Packages/EyeProxyCore/Tests/EyeProxyCoreTests/InterceptorChainTests.swift`, `ProxyServerHTTPTests.swift`, `FlowCodableTests.swift`

**Interfaces:**
- Produces:
  - `public enum FlowAnnotation: Codable, Equatable, Sendable { case hidden; case unrecorded; case tool(String); case originalURL(String) }`
  - `Flow.annotations: [FlowAnnotation]` (기본 `[]`; 디코드 시 키가 없으면 `[]` — `init(from:)`에서 `decodeIfPresent`)
  - `FlowEvent.annotated(id: FlowID, FlowAnnotation)`
  - `FlowContext.init(id: FlowID, clientAddress: String, clientPort: Int? = nil, annotate: @escaping @Sendable (FlowAnnotation) -> Void = { _ in })`, 속성 `clientPort`, 메서드 `func annotate(_ a: FlowAnnotation)`
  - `RequestDecision`에 `case drop`
  - `public enum ResponseDecision: Sendable { case `continue`(FlowResponse); case drop }`, `ResponseInterceptor.intercept(...) async -> ResponseDecision`
  - `InterceptorChain.runRequest(...) async -> RequestDecision`(drop에서 중단), `runResponse(...) async -> ResponseDecision`(drop에서 중단)
  - `ProxyServer.exchange(...) async -> ExchangeOutcome`, `enum ExchangeOutcome { case respond(FlowResponse); case drop }` (internal)
- 동작: 요청 체인의 `.respond(res)`도 응답 체인을 거친다(Map Local 응답 → Breakpoint 응답). drop이면 `.failed(id, "규칙으로 연결 끊김")`을 내고 핸들러가 응답 없이 채널을 닫는다. `annotate`는 `.annotated` 이벤트를 즉시 낸다.

- [ ] **Step 1: 실패 테스트 작성**

```swift
// InterceptorChainTests
@Test func dropStopsRequestChain() async {
    struct Drop: RequestInterceptor { func intercept(_ r: FlowRequest, context: FlowContext) async -> RequestDecision { .drop } }
    struct Fail: RequestInterceptor { func intercept(_ r: FlowRequest, context: FlowContext) async -> RequestDecision { Issue.record("ran"); return .continue(r) } }
    let chain = InterceptorChain(request: [Drop(), Fail()])
    guard case .drop = await chain.runRequest(.get("http://a.example/"), context: .init(id: FlowID(), clientAddress: "1.2.3.4")) else { Issue.record("not drop"); return }
}
@Test func responseDropStopsResponseChain() async { /* 같은 모양: ResponseInterceptor가 .drop → runResponse == .drop, 다음 인터셉터 미실행 */ }

// ProxyServerHTTPTests
@Test func respondedRequestPassesResponseChain() async throws {
    // 요청 인터셉터가 .respond(200 "local") / 응답 인터셉터가 X-Seen: 1 헤더 추가
    // fetchViaProxy("http://127.0.0.1:1/x") → status 200, headers["X-Seen"] == "1", body "local" (오리진 없이도 성공)
}
@Test func dropClosesClientWithoutResponse() async throws {
    // 요청 인터셉터 .drop → fetchViaProxy가 오류를 던진다
    // 이벤트: requestStarted 다음 .failed(error == "규칙으로 연결 끊김")
}
@Test func annotateEmitsEvent() async throws {
    // 요청 인터셉터가 context.annotate(.tool("Map Remote")) 후 .continue
    // 이벤트 순서: requestStarted → annotated(id 같음, .tool("Map Remote")) → responseReceived
}

// FlowCodableTests
@Test func decodesFlowWithoutAnnotations() throws {
    // 기존 저장 JSON(annotations 키 없음) 디코드 → flow.annotations == []
    // annotations: [.hidden, .tool("x"), .originalURL("http://a/")] 왕복 동일
}
```

- [ ] **Step 2: 실행해 실패 확인** — `swift test --package-path Packages/EyeProxyCore` → 컴파일 오류(`drop`, `ResponseDecision`, `annotations` 없음).

- [ ] **Step 3: 구현** — 위 Interfaces 그대로. `ProxyConnectionHandler.forward`는 `ExchangeOutcome.drop`이면 `context.close(promise: nil)`. 기존 `CAProfileResponder`·테스트의 `ResponseInterceptor` 구현은 `.continue(...)`로 감싸게 고친다.

- [ ] **Step 4: 통과 확인** — Core 테스트 전부 통과, Kit도 컴파일·통과(`swift test --package-path Packages/EyeProxyKit`).

- [ ] **Step 5: 커밋** — `feat(core): 연결 끊기·응답 판정·흐름 주석 훅`

---

### Task 2: Core — CONNECT 판정 훅과 터널 속도 조절

**Files:**
- Modify: `Interceptor.swift`, `ProxyConnectionHandler.swift`, `TunnelGlueHandler.swift`, `ProxyServer.swift`
- Test: `ProxyServerTunnelTests.swift`, `ProxyServerMITMTests.swift`

**Interfaces:**
- Consumes: Task 1의 `FlowAnnotation`, `FlowContext`.
- Produces:
  - `public struct ConnectContext: Sendable { public let clientAddress: String; public let clientPort: Int? }`
  - `public enum ConnectAction: Sendable, Equatable { case useDefault, decrypt, tunnel, drop }`
  - `public struct TunnelShaping: Sendable, Equatable { public var latencyMS: Int; public var downBytesPerSecond: Int?; public var upBytesPerSecond: Int?; public var blackhole: Bool }`
  - `public struct ConnectVerdict: Sendable, Equatable { public var action: ConnectAction = .useDefault; public var record = true; public var shaping: TunnelShaping? = nil; public var note: String? = nil }`
  - `public protocol ConnectInterceptor: Sendable { func intercept(host: String, port: Int, context: ConnectContext) async -> ConnectVerdict }`
  - `InterceptorChain.connect: [any ConnectInterceptor]`(init 인자 기본 `[]`), `func runConnect(host:port:context:) async -> ConnectVerdict` — 합치기: `action`은 처음 나온 non-`.useDefault`, `record`는 모두 AND, `shaping`·`note`는 처음 non-nil.
- 동작(`ProxyConnectionHandler.connect`):
  - `.drop` → 응답 없이 닫고 `record`면 CONNECT 흐름을 `.failed("규칙으로 연결 끊김")`로 남긴다.
  - `.decrypt` → SSL 목록과 무관하게 MITM. `note`가 있으면 그 연결 안 모든 흐름에 `.tool(note)` 주석.
  - `.tunnel` 또는 기본 판정이 터널 → 터널. `record == false`면 이벤트를 전혀 내지 않는다(기본 판정이 복호화여도 `record == false`면 터널).
  - `shaping`이 있으면 `TunnelGlueHandler`가 각 방향 청크를 `latencyMS + 크기/속도`만큼 늦춰 전달, `blackhole`이면 읽기만 하고 전달하지 않는다. MITM 연결의 shaping은 이 태스크 범위 밖(HTTP는 Task 10 인터셉터가 처리).

- [ ] **Step 1: 실패 테스트** (기존 MITM·터널 테스트 헬퍼 재사용)

```swift
@Test func connectDropClosesWithoutTunnel() // ConnectInterceptor → .drop: rawConnect의 응답이 "HTTP/1.1 200"이 아니고 채널이 닫힌다
@Test func connectDecryptForcesMITMWithEmptySSLList() // sslPolicy 빈 목록 + .decrypt(note: "규칙: R") → HTTPS 요청이 복호화되어 requestStarted.flow.isDecrypted == true, annotated(.tool("규칙: R"))
@Test func unrecordedTunnelEmitsNoEvents() // record=false → 요청 성공, events에 requestStarted가 1초 안에 오지 않는다
@Test func shapingDelaysTunnel() // shaping(latencyMS: 300) → TLS 요청 왕복 시간 >= 300ms
@Test func runConnectMergesVerdicts() // [record=false] + [action=.decrypt, note "a"] → action .decrypt, record false, note "a"
```

- [ ] **Step 2: 실패 확인** — 컴파일 오류.
- [ ] **Step 3: 구현** — 위 동작. 지연은 `context.eventLoop.scheduleTask(in:)`로 순서를 지키며 전달(청크별 누적 예약 시각).
- [ ] **Step 4: 통과 확인** — Core·Kit 테스트 통과.
- [ ] **Step 5: 커밋** — `feat(core): CONNECT 판정 훅과 터널 속도 조절`

---

### Task 3: Kit — 매칭 규칙(MatchRule)

**Files:**
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Rules/MatchRule.swift`
- Test: `Packages/EyeProxyKit/Tests/EyeProxyKitTests/MatchRuleTests.swift`

**Interfaces:**
- Produces:
  - `public enum MatchMode: String, Codable, Sendable { case wildcard = "useWildcard", regex = "useRegex" }`
  - `public enum MethodMatch: Equatable, Sendable { case any; case exact([String]) }`
  - `public struct MatchRule: Equatable, Sendable { url: String; mode: MatchMode; methods: MethodMatch; includeSubpaths: Bool; ignoreQuery: Bool; graphQLQueryName: String? }`, `init(url: String = "", mode: .wildcard, methods: .any, includeSubpaths: false, ignoreQuery: true, graphQLQueryName: nil)`
  - `func matches(_ request: FlowRequest) -> Bool`
  - `var validationError: String?` (정규식 컴파일 실패 문구, 아니면 nil)
  - `var hostPattern: String?` (자동 복호화용, 규칙은 스펙 §4.4)
  - `static func urlString(_ request: FlowRequest, includeQuery: Bool) -> String`
  - `var hasQueryLikePattern: Bool` (`?` 뒤에 `=`나 `*`가 오는 부분이 있음 → 편집기 안내용)
- 알고리즘(스펙 §4.2):
  - URL 문자열: `scheme://host[:port]path` — 기본 포트(http 80, https 443) 생략, IPv6는 `[...]`, `path`는 쿼리 포함(`includeQuery == false`면 첫 `?`부터 뗀다).
  - Wildcard → 정규식: 리터럴 이스케이프, `*`→`.*`, `?`→`.`. 패턴에 `://`가 없으면 앞에 `[a-z][a-z0-9+.-]*://`. 패턴에 `/`가 없으면(host만) 뒤에 `(/.*)?`가 붙은 것처럼(그 host 전체). `includeSubpaths`면 뒤에 `(/.*)?`. 전체 일치(`^…$`), 대소문자 무시. **[내 판단: 대소문자 무시]**
  - Regex: 패턴 그대로 `^(?:…)$`, 대소문자 구분 없음 옵션 없이.
  - `ignoreQuery`면 요청 URL 문자열만 쿼리를 떼고 비교, 패턴은 그대로.
  - 메서드: 대소문자 무시.
  - 컴파일된 정규식은 패턴별로 캐시(락으로 보호한 `[String: NSRegularExpression]`).

- [ ] **Step 1: 실패 테스트(표 기반)**

```swift
@Test(arguments: [
  // (pattern, mode, subpaths, ignoreQuery, method, url, expected)
  ("https://api.example.com/v1/search?*", "w", false, false, "GET", "https://api.example.com/v1/search?q=1", true),
  ("https://api.example.com/v1/search?*", "w", false, false, "GET", "https://api.example.com/v1/search", false), // Proxyman 동일
  ("https://api.example.com/v1/search", "w", false, true,  "GET", "https://api.example.com/v1/search?q=1&p=2", true),
  ("https://api.example.com/v1/search", "w", false, true,  "GET", "https://api.example.com/v1/search", true),
  ("https://api.example.com/v1/search", "w", false, false, "GET", "https://api.example.com/v1/search?q=1", false),
  ("https://api.example.com/v?/users", "w", false, true, "GET", "https://api.example.com/v2/users?x=1", true),
  ("api.example.com/v1/*", "w", false, false, "GET", "http://api.example.com/v1/a/b", true),          // scheme 생략
  ("api.example.com", "w", false, false, "GET", "https://api.example.com/any/path?x=1", true),         // host만
  ("https://api.example.com/v1/user", "w", true, false, "GET", "https://api.example.com/v1/user/9", true),
  ("https://api.example.com/v1/user", "w", true, false, "GET", "https://api.example.com/v1/userX", false),
  ("https:\\/\\/api\\.example\\.com\\/v1\\/.*", "r", false, false, "GET", "https://api.example.com/v1/x?y=1", true),
  ("https:\\/\\/api\\.example\\.com", "r", false, false, "GET", "https://api.example.com/v1", false), // 부분 일치 불가
  ("http://127.0.0.1:8080/x", "w", false, false, "GET", "http://127.0.0.1:8080/x", true),            // 비기본 포트
  ("http://[::1]:8080/x", "w", false, false, "GET", "http://[::1]:8080/x", true),                    // IPv6
  ("HTTPS://API.EXAMPLE.COM/a", "w", false, false, "get", "https://api.example.com/a", true),
])
func matchTable(...) { /* FlowRequest를 url에서 만들어 MatchRule(...).matches == expected */ }

@Test func methodExactFilters() // .exact(["POST"]) → GET 불일치, post 일치
@Test func invalidRegexNeverMatchesAndReportsError() // pattern "([" regex → matches false, validationError != nil
@Test(arguments: [
  ("https://*.example.com/v1/*", "*.example.com"), ("api?.example.com/x", "api?.example.com"),
  ("https://api.example.com:8443/x", "api.example.com"), ("http://api.example.com/x", nil),
  ("*", nil), ("https://*/x", nil),
]) func hostPatternExtraction(...)   // regex 모드는 항상 nil
@Test func queryLikePatternDetection() // "…/search?*" true, "…/v?/users" false, "…?a=1" true
```

- [ ] **Step 2: 실패 확인** — `swift test --package-path Packages/EyeProxyKit --filter MatchRuleTests` → 컴파일 오류.
- [ ] **Step 3: 구현** — 위 시그니처와 알고리즘.
- [ ] **Step 4: 통과 확인**
- [ ] **Step 5: 커밋** — `feat(kit): 규칙 매칭(와일드카드·정규식·쿼리 무시)`

---

### Task 4: Kit — 규칙 트리와 Proxyman 노드 코덱

**Files:**
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Rules/RuleTree.swift`
- Test: `Packages/EyeProxyKit/Tests/EyeProxyKitTests/RuleTreeTests.swift`, 픽스처 `Tests/EyeProxyKitTests/Fixtures/Proxyman/` (Task 5·7에서도 씀)

**Interfaces:**
- Consumes: Task 3 `MatchRule`.
- Produces:
  - `public protocol ToolRule: Codable, Equatable, Sendable, Identifiable where ID == String { var id: String { get }; var name: String { get set }; var isEnabled: Bool { get set }; var match: MatchRule { get set } }`
  - `public struct RuleFolder<Rule: ToolRule>: Codable, Equatable, Sendable, Identifiable { id: String; name: String; isEnabled: Bool; children: [RuleNode<Rule>] }`
  - `public indirect enum RuleNode<Rule: ToolRule>: Codable, Equatable, Sendable, Identifiable { case rule(Rule); case folder(RuleFolder<Rule>) }`
  - `public struct RuleTree<Rule: ToolRule>: Equatable, Sendable { public var nodes: [RuleNode<Rule>] }`
    - `func firstMatch(_ request: FlowRequest) -> Rule?` — 깊이 우선, 꺼진 규칙·꺼진 폴더 하위 건너뜀
    - `var enabledRules: [Rule]` — 같은 순서로 펼친 켜진 규칙
    - `static func decodeLenient(_ data: Data) throws -> (tree: RuleTree, skipped: Int)` — 최상위 `{"nodes":[…]}` 또는 `[…]` 둘 다. 디코드 실패한 노드(모르는 종류·필드 누락)는 건너뛰고 셈. JSON이 아니면 throw.
    - `func encoded() throws -> Data` — `{"nodes":[…]}`, `func encodedAsProxymanExport() throws -> Data` — `[…]`
  - `MatchRule`의 Proxyman 키 코딩 헬퍼: `MatchRule.init(proxymanFields container: KeyedDecodingContainer<ProxymanKey>) throws`, `func encode(proxymanFields:)` — 키 `url`, `regex`(`useWildcard`/`useRegex`; 모르는 값 → wildcard), `method`(`{"any":{}}` | `{"exact":[{"name":"GET"}]}`), `isIncludingPaths`, `graphQLQueryName`, `eyeproxy.ignoreQuery`(없으면 **false**).
  - `public struct ProxymanKey: CodingKey`(문자열 키 아무거나)
- 노드 JSON 모양: 규칙 `{"nodeType":{"node":{"_0":{…규칙 필드…}}}}`. 폴더(확인 안 됨, 가정) `{"nodeType":{"folder":{"_0":{"id","name","isEnabled","children":[…]}}}}`. `nodeType`의 키가 둘 다 아니면 건너뛴 노드로 센다.

- [ ] **Step 1: 실패 테스트** (테스트 전용 `struct TestRule: ToolRule` — id, name, isEnabled, match + 임의 필드 `note: String?`을 Proxyman 키로 디코드)

```swift
@Test func decodesDiskFormatAndExportFormat() // 같은 두 노드를 {"nodes":[…]}와 […]로 → 결과 동일, skipped 0
@Test func skipsUnknownNodeKindsAndBrokenNodes() // ["node" 정상, "weird" 종류, "node"인데 url 누락] → rules 1개, skipped 2
@Test func nonJSONThrows() // Data("hello".utf8) → throws
@Test func firstMatchSkipsDisabledAndDisabledFolders() // [꺼진 R1(match), 꺼진 폴더{R2 match}, 켜진 R3 match, R4 match] → R3
@Test func folderOrderIsDepthFirst() // [폴더{A,B}, C] 모두 match → enabledRules ids == [A,B,C]
@Test func ignoreQueryDefaultsFalseWhenAbsentAndRoundTrips() // eyeproxy 키 없음 → false; true로 인코드 후 디코드 → true
@Test func methodAndRegexFieldsRoundTrip() // {"any":{}}, {"exact":[{"name":"GET"},{"name":"POST"}]}, "useRegex", 모르는 regex 값 "useFoo" → wildcard
```

- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현**
- [ ] **Step 4: 통과 확인**
- [ ] **Step 5: 커밋** — `feat(kit): 규칙 트리와 Proxyman 노드 코덱`

---

### Task 5: Kit — 도구 스위치와 규칙 저장소

**Files:**
- Create: `Rules/ToolSwitches.swift`, `Rules/RuleStore.swift`
- Modify: `Packages/EyeProxyKit/Sources/EyeProxyKit/AppSettings.swift`
- Test: `RuleStoreTests.swift`, `AppSettingsTests.swift`

**Interfaces:**
- Consumes: Task 4 `RuleTree`. 도구별 규칙 타입은 Task 7~11이 만든다. 이 태스크에서는 저장소를 **제네릭 슬롯**으로 만든다.
- Produces:
  - `public struct ToolSwitches: Codable, Equatable, Sendable { breakpoint, mapLocal, mapRemote, blockList, allowList, networkConditions, noCaching, repeatNoCache: Bool }` 기본 모두 false.
  - `AppSettings.toolSwitches: ToolSwitches` — UserDefaults 키 `eyeproxy.toolSwitches`(JSON).
  - `@MainActor @Observable public final class RuleStore`:
    - `public init(directory: URL)` — `~/Library/Application Support/com.tv.eyeproxy/rules/`(앱이 전달, 테스트는 임시 폴더)
    - `public func tree<R: ToolRule>(_ file: RuleFile<R>) -> RuleTree<R>` / `public func set<R>(_ tree: RuleTree<R>, for file: RuleFile<R>)` — set은 즉시 디스크에 원자적 저장(`.atomic`)하고 `revision`을 올린다.
    - `public private(set) var revision: Int` — 앱이 파이프라인 재조립 트리거로 관찰.
    - `public private(set) var loadWarnings: [String]` — 손상 파일은 `<name>.broken-<날짜>`로 옮기고 빈 트리로 시작, 경고 기록.
  - `public struct RuleFile<R: ToolRule>: Sendable { public let name: String }` — 각 도구 태스크가 `extension RuleFile where R == MapLocalRule { public static var mapLocal: Self { .init(name: "map-local.json") } }`처럼 **계산 속성**으로 선언(제네릭 타입에는 static 저장 속성을 둘 수 없다). 아래 태스크의 `RuleFile.xxx = "…"` 표기는 모두 이 뜻.
  - `RuleStore.mapLocalDirectory: URL` = `directory/../map-local/`(Task 7이 응답 파일 저장에 사용).

- [ ] **Step 1: 실패 테스트**

```swift
@Test @MainActor func savesAndReloadsTree() // set(tree, for: .test) → 새 RuleStore(directory: 같은 폴더).tree(.test) == tree, revision 증가
@Test @MainActor func brokenFileIsMovedAsideWithWarning() // "test.json"에 "{" 기록 → tree 빈 값, loadWarnings 1개, "test.json.broken-…" 존재
@Test @MainActor func toolSwitchesPersist() // AppSettings(defaults: 임시).toolSwitches.mapLocal = true → 새 AppSettings에서 true, 기본은 모두 false
```

- [ ] **Step 2~4**: 실패 확인 → 구현 → 통과.
- [ ] **Step 5: 커밋** — `feat(kit): 도구 스위치와 규칙 저장소`

---

### Task 6: Kit — HTTP 메시지 파일

**Files:**
- Create: `Tools/MapLocal/HTTPMessageFile.swift`
- Test: `HTTPMessageFileTests.swift`

**Interfaces:**
- Produces:
  - `public enum HTTPMessageFile`
    - `static func parse(_ data: Data, fileURLBase: URL?) throws -> FlowResponse` — 상태줄 `HTTP/1.1 200 OK`, 헤더, 빈 줄(`\r\n\r\n` 또는 `\n\n`), 본문. 헤더 줄 `<FILE_URL="경로">`(대소문자 무시, `~` 확장, 상대 경로면 `fileURLBase` 기준)가 있으면 본문을 그 파일로 바꾼다(헤더 목록에서는 뺀다). `Content-Length`는 실제 본문 길이로 다시 쓰고 `Transfer-Encoding`은 뺀다. 상태줄이 없거나 망가지면 `HTTPMessageFileError.badStatusLine` throw.
    - `static func serialize(_ response: FlowResponse) -> Data` — `HTTP/1.1 <status> <reason>\n헤더\n\n본문`(Proxyman과 같은 `\n`).
    - `static func response(forLocalFile url: URL) throws -> FlowResponse` — 200, `Content-Type`은 `UTType(filenameExtension:)`의 preferredMIMEType, 없으면 `application/octet-stream`.

- [ ] **Step 1: 실패 테스트**

```swift
@Test func parsesProxymanDefaultMessage() // "HTTP/1.1 200 OK\nContent-Type: application/json; charset=utf-8\n\n{\n  \"status\": \"ok\"\n}" → 200, 헤더 2개(Content-Length 재계산 포함), body 일치
@Test func parsesCRLF()
@Test func fileURLReplacesBody() // 임시 파일 "abc" + <FILE_URL="상대.json"> → body "abc", 헤더에 FILE_URL 없음
@Test func missingFileURLThrows() // 없는 경로 → throws
@Test func badStatusLineThrows() // "hello\n\nx" → .badStatusLine
@Test func serializeRoundTrips() // serialize → parse == 원본(Content-Length 포함)
@Test func localFileGuessesContentType() // .json → application/json, .png → image/png, 확장자 없음 → application/octet-stream
```

- [ ] **Step 2~4**, **Step 5: 커밋** — `feat(kit): HTTP 메시지 파일 파서`

---

### Task 7: Kit — Map Local

**Files:**
- Create: `Tools/MapLocal/MapLocalRule.swift`, `Tools/MapLocal/MapLocalInterceptor.swift`
- Test: `MapLocalTests.swift`, 픽스처 `Fixtures/Proxyman/MapLocalFiles-RuleTree.json`(스펙 §3의 규칙 JSON, host `api.example.com`, 경로는 픽스처 폴더 상대 → 테스트에서 치환)

**Interfaces:**
- Consumes: Task 3·4·5·6.
- Produces:
  - `public struct MapLocalRule: ToolRule` — `id, name, isEnabled, match`, `useLocalFile: Bool`(`isLocalFileEnable`), `localFile: LocalFileRef?`(`{name, path}`), `useDirectory: Bool`(`isDirectoryFileEnable`), `directoryPath: String?`(`directoryFile` — 객체면 `path` 키, 문자열이면 그대로 **[가정]**), `delaySeconds: Int?`(`advanceSettings.delayTimePreset`, 단위 초 **[가정]**). Proxyman 키로 인코드/디코드(Task 4 헬퍼).
  - `extension RuleFile { static let mapLocal = RuleFile<MapLocalRule>(name: "map-local.json") }`
  - `public static let MapLocalRule.delayPresets: [Int?] = [nil, 1, 2, 3, 5, 10, 30]` (No Delay 포함) **[내 판단]**
  - `func MapLocalRule.relativePath(for request: FlowRequest) -> String?` — 디렉터리 모드 상대 경로(스펙 §5.2: 일치 접두 제거, host만 패턴이면 전체 경로, regex는 첫 캡처 그룹, 쿼리 제외).
  - `public struct MapLocalInterceptor: RequestInterceptor { init(rules: RuleTree<MapLocalRule>, readFile: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }) }`
    - 첫 일치 규칙이 파일 모드: `HTTPMessageFile.parse`(경로가 `.http`/`.json`이면 메시지로 시도, 실패하면 `response(forLocalFile:)`로 본문 취급) → 지연 → `.respond`, 주석 `.tool("Map Local: <이름>")`.
    - 디렉터리 모드: `directoryPath/relativePath` 파일이 있으면 `response(forLocalFile:)`, **없으면 `.continue`**(실제 서버).
    - 파일 모드에서 파일이 없거나 읽기 실패: `.continue` + 주석 `.tool("Map Local 파일 없음: <이름>")`. (Review Focus 2)

- [ ] **Step 1: 실패 테스트**

```swift
@Test func decodesProxymanFixture() // 픽스처 → 규칙 1개, match.url == "https://api.example.com/v1/search?*", methods .exact(["GET"]), ignoreQuery false, delaySeconds 10, localFile.name "default_message"
@Test func respondsWithMessageFile() async // 규칙 + 메시지 파일 → .respond(status 200, body), annotation .tool("Map Local: R")
@Test func missingFileContinuesWithAnnotation() async // 없는 경로 → .continue(원 요청), annotation .tool("Map Local 파일 없음: R")
@Test func plainFileBecomesBody() async // a.png 선택 → Content-Type image/png
@Test(arguments: [
  ("api.example.com/build/v1/*", "w", "https://api.example.com/build/v1/js/main.js?v=3", "js/main.js"),
  ("api.example.com", "w", "https://api.example.com/build/v1/index.html", "build/v1/index.html"),
  ("https:\\/\\/api\\.example\\.com\\/build\\/v1\\/(.*)", "r", "https://api.example.com/build/v1/a/b.css", "a/b.css"),
]) func directoryRelativePath(...)
@Test func directoryMissingFileFallsThrough() async // 폴더에 파일 없음 → .continue
@Test func delayIsApplied() async // delaySeconds 1 → 소요 >= 1초
```

- [ ] **Step 2~4**, **Step 5: 커밋** — `feat(kit): Map Local 규칙과 인터셉터`

---

### Task 8: Kit — Map Remote

**Files:**
- Create: `Tools/MapRemote/MapRemoteRule.swift`, `Tools/MapRemote/MapRemoteInterceptor.swift`
- Test: `MapRemoteTests.swift`

**Interfaces:**
- Produces:
  - `public struct MapRemoteRule: ToolRule` — `match`(새 규칙 기본 `includeSubpaths = true`), `mapTo: MapTarget`(`scheme, host, port: Int?, path, query: String?` — 빈 값 = 유지), `preserveHostHeader: Bool`, `preserveOriginalURL: Bool`. Proxyman 키 **[가정, 스펙 §9.2]**: `mapTo`→`toURL` 객체 `{protocol, host, port, path, query}`, `isPreserveHostHeader`, `isPreserveOriginalURL`. 모르면 건너뛴 노드.
  - `static let RuleFile.mapRemote = RuleFile<MapRemoteRule>(name: "map-remote.json")`
  - `static func MapTarget.parse(pastedURL: String) -> MapTarget` — Host 칸에 URL 붙여넣기 분해.
  - `public struct MapRemoteInterceptor: RequestInterceptor { init(rules: RuleTree<MapRemoteRule>) }` — 일치하면 바뀐 요청으로 `.continue`. `includeSubpaths`이고 `mapTo.path`가 있으면 일치 접두 경로만 교체하고 나머지 하위 경로를 이어 붙인다. `preserveHostHeader == false`면 `Host` 헤더를 새 `host[:port]`로. 주석 `.tool("Map Remote: <이름>")`, `preserveOriginalURL`이면 `.originalURL(원래 URL)`도.
- 루프백 차단은 업스트림 단계에서 이미 바뀐 목적지에 적용됨(별도 작업 없음, 테스트로 확인).

- [ ] **Step 1: 실패 테스트**

```swift
@Test func replacesHostKeepsPathAndQuery() async // match https://api.example.com/v1/user (subpaths), mapTo host staging.example.com → https://staging.example.com/v1/user/9?id=1, Host 헤더 "staging.example.com"
@Test func preserveHostHeaderKeepsOriginalHost() async
@Test func subpathPrefixReplacement() async // match /v1/* path→"v2/api" : /v1/a/b → /v2/api/a/b
@Test func emptyFieldsKeepComponents() async // mapTo scheme "http", port 8080만 → host·path·query 유지
@Test func queryReplacement() async // mapTo.query "id=123" → 쿼리 교체
@Test func pastedURLParsing() // "https://staging.example.com:8443/v2/api?x=1" → 5칸 분해
@Test func annotations() async // .tool("Map Remote: R") (+ preserveOriginalURL이면 .originalURL)
```

- [ ] **Step 2~4**, **Step 5: 커밋** — `feat(kit): Map Remote 규칙과 인터셉터`

---

### Task 9: Kit — Block List·Allow List

**Files:**
- Create: `Tools/BlockAllow/BlockRule.swift`, `AllowRule.swift`, `BlockAllowInterceptors.swift`
- Test: `BlockAllowTests.swift`

**Interfaces:**
- Produces:
  - `public enum BlockAction: String, Codable, Sendable { case blockAndHide, blockAndDisplay, hideOnly }` (Proxyman 키 `blockAction` **[가정]**)
  - `public struct BlockRule: ToolRule` — `match`, `action: BlockAction`, `appPath: String?`(Block App, 앱 번들 경로)
  - `public struct AllowRule: ToolRule` — `match`
  - `RuleFile.blockList = "block-list.json"`, `RuleFile.allowList = "allow-list.json"`
  - `public struct BlockInterceptor: RequestInterceptor, ConnectInterceptor { init(rules: RuleTree<BlockRule>, appPath: @escaping @Sendable (_ clientAddress: String, _ clientPort: Int?) async -> String?) }`
    - 요청: 첫 일치(URL 규칙 또는 appPath 일치) → `blockAndHide`: `.hidden` 주석 + `.drop` / `blockAndDisplay`: `.tool("Blocked: <이름>")` + `.drop` / `hideOnly`: `.hidden` + `.continue`.
    - CONNECT: **경로 없는 host 전용 규칙**(패턴에 host 뒤 `/`가 없거나 `/*`뿐)과 app 규칙만 판정 → `blockAndHide`: `ConnectVerdict(action: .drop, record: false)` / `blockAndDisplay`: `.drop` / `hideOnly`: `record: false`. 경로 있는 규칙은 `.useDefault`(자동 복호화 후 요청 단계에서 판정).
    - `appPath`는 app 규칙이 하나라도 있을 때만 호출(lsof 비용). **ponytail:** 요청마다 조회, 느리면 포트별 캐시.
  - `public struct AllowInterceptor: RequestInterceptor, ConnectInterceptor { init(rules: RuleTree<AllowRule>) }`
    - 요청: 아무 규칙에도 안 맞으면 `.unrecorded` 주석 + `.continue`.
    - CONNECT: host가 어떤 규칙의 `hostPattern`에도 안 맞으면 `ConnectVerdict(action: .tunnel, record: false)`, 맞으면 `.useDefault`.

- [ ] **Step 1: 실패 테스트**

```swift
@Test func blockActionsOnRequest() async // 세 액션 각각 → (drop, [.hidden]) / (drop, [.tool("Blocked: R")]) / (continue, [.hidden])
@Test func hostOnlyRuleBlocksAtConnect() async // "ads.example.com" → connect verdict .drop, record false(blockAndHide)
@Test func pathRuleDefersAtConnect() async // "api.example.com/ads/*" → .useDefault
@Test func blockAppByPath() async // appPath 클로저가 "/Applications/Foo.app" 반환 + 규칙 appPath 같음 → drop; 다른 앱 → continue
@Test func appLookupSkippedWithoutAppRules() async // app 규칙 없으면 클로저 호출 0회
@Test func allowListUnrecordsNonMatching() async // 규칙 api.example.com/* : other.example.com 요청 → .unrecorded, connect → (.tunnel, record false); api.example.com connect → .useDefault
```

- [ ] **Step 2~4**, **Step 5: 커밋** — `feat(kit): Block List·Allow List 인터셉터`

---

### Task 10: Kit — No Caching·Network Conditions

**Files:**
- Create: `Tools/NoCaching/NoCachingInterceptor.swift`, `Tools/NetworkConditions/NetworkProfile.swift`, `NetworkConditionRule.swift`, `NetworkConditionsInterceptor.swift`
- Test: `NoCachingTests.swift`, `NetworkConditionsTests.swift`, 픽스처 `Fixtures/Proxyman/NetworkThrottlingService.json`(스펙 §3 예시, host `img.example.com`)

**Interfaces:**
- Produces:
  - `public struct NoCachingInterceptor: RequestInterceptor, ResponseInterceptor` — 스펙 §5.6 표의 헤더 제거·추가(이름 비교 대소문자 무시, 추가는 정확히 `Pragma: no-cache`, `Cache-Control: no-cache` / `Expires: 0`, `Cache-Control: no-cache`, 기존 같은 이름은 교체).
  - `public struct NetworkProfile: Codable, Equatable, Sendable` — Proxyman 키 그대로: `name, profileType, downloadBandwidth, uploadBandwidth`(B/s, 상한), `downloadBandwidthTitle, uploadBandwidthTitle, delay`(ms), `minimumWaitTime`(보존만), `packageDrop`(%), `isAllLostConnection` + EyeProxy 전용 `eyeproxy.downloadMin`, `eyeproxy.uploadMin`(B/s, 없으면 상한의 50%).
  - `public static let NetworkProfile.presets: [NetworkProfile]` — 스펙 §5.7 이름·대역(Mbps→B/s = ×125000), 지연·손실 표. 이름 순서도 스펙 순서.
  - `public struct NetworkConditionRule: Codable, Equatable, Sendable, Identifiable` — `id, name, url`(host 문자열), `isEnabled, isSystemWide, networkProfile` (배열 파일, 트리 아님). `RuleStore`에는 `networkConditions: [NetworkConditionRule]` 전용 접근자(`"network-conditions.json"`)를 이 태스크에서 더한다. 하나를 켜면 나머지를 끄는 `func RuleStore.activateNetworkCondition(id:)`. 사용자 프로필(Custom Profile…)은 `RuleStore.customNetworkProfiles: [NetworkProfile]`(`"network-profiles.json"`)에 저장.
  - `public struct NetworkConditionsInterceptor: RequestInterceptor, ResponseInterceptor, ConnectInterceptor { init(rule: NetworkConditionRule, random: @escaping @Sendable () -> Double = { .random(in: 0..<1) }) }`
    - 대상: `isSystemWide` 또는 `request.host`가 `rule.url`과 같음(대소문자 무시, `*.` 와일드카드 허용 — `SSLProxyingPolicy`와 같은 규칙).
    - 요청: `isAllLostConnection`이면 취소될 때까지 대기(`Task.sleep` 반복, 취소 시 `.drop`). 아니면 `delay + 요청 크기/업로드속도` 대기 + `packageDrop%` 확률로 1초 추가 → `.continue`.
    - 응답: `delay + 응답 크기/다운로드속도` 대기(+손실) → `.continue`.
    - CONNECT: 대상이면 `shaping: TunnelShaping(latencyMS: delay, down/up: 무작위 속도, blackhole: isAllLostConnection)`.
    - 속도 = `min + (max - min) * random()`.

- [ ] **Step 1: 실패 테스트**

```swift
@Test func noCachingRequestHeaders() async // If-None-Match·If-Modified-Since 제거, Pragma·Cache-Control 추가(기존 cache-control: max-age=60 교체)
@Test func noCachingResponseHeaders() async // ETag·Last-Modified·Expires 제거, Expires: 0, Cache-Control: no-cache
@Test func decodesProxymanThrottlingFixture() // 픽스처 → name "Very Bad Network", downloadBandwidth 125000, delay 1400, packageDrop 10; 다시 인코드하면 Proxyman 키 유지
@Test func presetsMatchSpecNames() // presets.map(\.name) == ["100% Loss","Very Bad Network","Slow Network","Medium Network","2G (EDGE)","3G","4G (LTE)","5G","Wi-Fi","Wi-Fi 802.11ac"]
@Test func delayAppliesOnlyToTargetHost() async // rule url img.example.com, delay 300 → img 요청 >= 300ms, 다른 host 즉시
@Test func bandwidthDelayScalesWithSize() async // 다운로드 100_000 B/s(min=max), 응답 50_000 B, delay 0, random 0 → >= 500ms
@Test func totalLossHangsUntilCancelled() async // isAllLostConnection → 0.5초 후 Task 취소 → .drop 반환
@Test @MainActor func activatingOneDeactivatesOthers()
@Test @MainActor func customProfilesPersist() // 추가 → 새 RuleStore에서 동일
```

- [ ] **Step 2~4**, **Step 5: 커밋** — `feat(kit): No Caching·Network Conditions`

---

### Task 11: Kit — Breakpoint

**Files:**
- Create: `Tools/Breakpoint/BreakpointRule.swift`, `BreakpointCenter.swift`, `BreakpointInterceptor.swift`, `BreakpointTemplate.swift`
- Test: `BreakpointTests.swift`

**Interfaces:**
- Produces:
  - `public struct BreakpointRule: ToolRule` — `match`, `onRequest: Bool`(`isRequest`), `onResponse: Bool`(`isResponse`) **[가정 키]**. `RuleFile.breakpoint = "breakpoint.json"`.
  - `public enum BreakpointPhase: Sendable { case request, response }`
  - `public struct PausedItem: Identifiable, Sendable { id: UUID; flowID: FlowID; phase; ruleName: String; request: FlowRequest; response: FlowResponse? }`
  - `public enum BreakpointResolution: Sendable, Equatable { case continueOriginal; case executeRequest(FlowRequest); case executeResponse(FlowResponse); case drop; case abort(status: Int) }` — abort는 429 또는 503.
  - `@MainActor @Observable public final class BreakpointCenter`
    - `public private(set) var pending: [PausedItem]`
    - `public func pause(_ item: PausedItem) async -> BreakpointResolution` — 목록 추가 후 resolve까지 대기. 호출 Task가 취소되면 목록에서 빼고 `.continueOriginal`. (Review Focus 1)
    - `public func resolve(_ id: UUID, with: BreakpointResolution)`
    - `public func releaseAll()` — 전부 `.continueOriginal`(앱 종료 시)
  - `public struct BreakpointInterceptor: RequestInterceptor, ResponseInterceptor { init(rules: RuleTree<BreakpointRule>, center: BreakpointCenter) }`
    - 요청 단계(`onRequest`): continueOriginal → `.continue(원본)`, executeRequest → `.continue(편집본)` + `.tool("Breakpoint 편집됨")`, drop → `.drop`, abort(s) → `.respond(FlowResponse(status: s, reason: s == 429 ? "Too Many Requests" : "Service Unavailable"))`.
    - 응답 단계(`onResponse`): executeResponse → 편집본, drop → `.drop`, abort(s) → s 응답으로 교체.
  - `public struct BreakpointTemplate: Codable, Equatable, Sendable, Identifiable { id; name; kind: BreakpointPhase(Codable 문자열); method: String?; url: String?; status: Int?; headers: [HTTPHeader] }` — 저장 `"breakpoint-templates.json"`(EyeProxy 전용 형식), `RuleStore.breakpointTemplates` 접근자.
  - `func BreakpointTemplate.apply(to request: FlowRequest) -> FlowRequest` / `apply(to response: FlowResponse) -> FlowResponse` — 값이 있는 것만 바꾸고 헤더는 통째로 교체.

- [ ] **Step 1: 실패 테스트**

```swift
@Test @MainActor func pauseWaitsForResolve() async // 인터셉터 실행 Task → center.pending 1개 → resolve(.executeRequest(편집)) → .continue(편집), pending 0
@Test @MainActor func cancellationRemovesPending() async // Task 취소 → pending 0, 결과 .continue(원본)
@Test @MainActor func abortReturns429And503() async
@Test @MainActor func responsePhaseEdits() async // onResponse → executeResponse(status 418) → .continue(418)
@Test @MainActor func releaseAllContinuesOriginal() async // 2건 대기 → releaseAll → 둘 다 원본
@Test func templateApplyReplacesOnlySetFields()
```

- [ ] **Step 2~4**, **Step 5: 커밋** — `feat(kit): Breakpoint 규칙·대기열·템플릿`

---

### Task 12: Kit+App — 파이프라인 조립·자동 복호화·숨김/미기록 반영

**Files:**
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Tools/ToolPipeline.swift`, `EyeProxy/AppModel+Tools.swift`
- Modify: `SessionStore.swift`, `FlowFilter.swift`, `FlowRow.swift`(주석 필드 노출), `EyeProxy/AppModel.swift`(서버 시작 시 체인), `EyeProxy/Views/Toolbar/MainToolbar.swift`(검색 옆 "숨김 포함" 토글), `EyeProxy/Views/Detail/FlowHeaderBar.swift`(주석 표시)
- Test: `ToolPipelineTests.swift`, `SessionStoreTests.swift`, `FlowFilterTests.swift`

**Interfaces:**
- Consumes: Task 3~11 전부, Task 1·2 Core 타입.
- Produces:
  - `public struct RuleSet: Sendable { mapLocal, mapRemote, breakpoint, block, allow: RuleTree<…>; networkConditions: [NetworkConditionRule] }`, `@MainActor var RuleStore.ruleSet: RuleSet`
  - `public enum ToolPipeline`
    - `static func chain(rules: RuleSet, switches: ToolSwitches, breakpoints: BreakpointCenter, appPath: @escaping @Sendable (String, Int?) async -> String?, base: [any RequestInterceptor]) -> InterceptorChain`
      - connect: `[Allow?, Block?, AutoDecrypt, NetworkConditions?]`
      - request: `base + [Allow?, Block?, NoCaching?, MapRemote?, MapLocal?, Breakpoint?, NetworkConditions?]`
      - response: `[NoCaching?, Breakpoint?, NetworkConditions?]` (`?` = 스위치 켜짐일 때만, Network Conditions는 켜진 규칙이 있을 때만)
    - `static func autoDecryptHosts(rules: RuleSet, switches: ToolSwitches) -> [(pattern: String, ruleName: String)]` — 스위치 켜진 Breakpoint·Map Local·Map Remote·Block(경로 있는 규칙)·Allow(경로 있는 규칙)의 켜진 규칙 `hostPattern`.
    - `struct AutoDecryptInterceptor: ConnectInterceptor` — host가 패턴에 맞으면 `ConnectVerdict(action: .decrypt, note: "자동 복호화(규칙: <이름>)")`.
  - `SessionStore.apply(.annotated(id, a))`: `.unrecorded` → 그 흐름을 목록에서 제거, 그 외 → `flows[i].annotations.append(a)`.
  - `FlowFilter.includeHidden: Bool = false` — false면 `.hidden` 주석 흐름 제외.
  - `AppModel`: `rules: RuleStore`, `breakpoints: BreakpointCenter` 보유. 서버 시작·`rules.revision`·`settings.toolSwitches` 변화 때 `server.update(interceptors: ToolPipeline.chain(...))`. `appPath`는 `ProcessResolver.resolve(port:proxyPort:)` 결과의 `path`(루프백 클라이언트만). `applicationShouldTerminate`에서 `breakpoints.releaseAll()`.
  - 상세 헤더 바: 주석 `.tool`·`.originalURL`을 회색 캡슐로 표시("Map Remote: R · 원래 URL …").
  - 툴바 상태 캡슐: `breakpoints.pending.count > 0`이면 "⏸ N건 대기" 추가, 누르면 Breakpoint 창 열기(Task 16의 창 id `"breakpoints"`).

- [ ] **Step 1: 실패 테스트**

```swift
@Test @MainActor func chainOrderFollowsSpec() // 모든 스위치 켬 → request 타입 순서 == [CAProfileResponder, Allow, Block, NoCaching, MapRemote, MapLocal, Breakpoint, NetworkConditions]
@Test @MainActor func disabledToolsAreAbsent() // 스위치 모두 끔 → request == [base], connect == [AutoDecrypt]
@Test func autoDecryptHostsSkipRegexAndWildcardOnly() // map local "https://api.example.com/x"(켬), regex 규칙, "https://*/x" → [("api.example.com","R")]
@Test func autoDecryptRespectsSwitches() // mapLocal 스위치 끔 → 그 규칙 호스트 없음
@Test @MainActor func unrecordedAnnotationRemovesFlow() // requestStarted → annotated(.unrecorded) → flows 비어 있음, number nil
@Test @MainActor func hiddenFlowsFilteredByDefault() // .hidden 주석 흐름 → FlowFilter() 불일치, includeHidden true면 일치
@Test func mapRemoteThenMapLocalMatchesNewURL() async // 체인: Map Remote(a→b) + Map Local(b 규칙) → Map Local 응답
```

- [ ] **Step 2~4**: 실패 확인 → 구현 → Kit 테스트 통과 + `xcodegen generate` + 앱 빌드 경고 0.
- [ ] **Step 5: 커밋** — `feat: 도구 파이프라인 조립과 자동 복호화`

---

### Task 13: Kit — Proxyman 가져오기·규칙 번들 내보내기

**Files:**
- Create: `Import/ProxymanImporter.swift`, `Import/RuleBundle.swift`
- Test: `ProxymanImporterTests.swift`, 픽스처 `Fixtures/Proxyman/user-data/`(MapLocal·NetworkThrottling·SSLList·빈 MapRemote/Breakpoint) + `Fixtures/Proxyman/map-local/api.example.com_19A8BA07.json` + 내보내기 픽스처 `proxyman_map_local_tree_rules.config`(노드 배열)

**Interfaces:**
- Produces:
  - `public struct ProxymanImportPreview: Sendable { mapLocal, mapRemote, breakpoint, block, allow: [rule]; networkConditions: [NetworkConditionRule]; sslHosts: [String]; skipped: Int; missingFiles: [String] }`
  - `public enum ProxymanImporter`
    - `static let defaultDirectory: URL` = `~/Library/Application Support/com.proxyman.NSProxy`
    - `static func preview(proxymanDirectory: URL) throws -> ProxymanImportPreview` — **읽기 전용**(파일 열기만). 파일: `user-data/MapLocalFiles-RuleTree`, `MapRemoteService-RuleTree`, `BreakpointFiles-RuleTree`, `NetworkThrottlingService`, `SSLList-*`(첫 파일, `nodes[].kind.domain[].url`). Block/Allow는 파일 이름 미확인 → `user-data/` 안에서 `Block`/`Allow`를 포함한 이름을 시도, 없으면 빈 값.
    - `@MainActor static func apply(_ preview: ProxymanImportPreview, selection: ImportSelection, into store: RuleStore, settings: AppSettings) -> ImportResult` — 각 트리 **끝에 추가**, 같은 `id`가 이미 있으면 건너뜀, `ignoreQuery`는 디코드 기본(false) 그대로, **`settings.toolSwitches`는 건드리지 않음**, SSL 호스트는 `settings.sslPatterns`에 없는 것만 추가. `graphQLQueryName`이 있는 규칙은 `isEnabled = false`로 들이고 결과의 `graphQLDeferred` 개수로 알린다(2차 지원). Map Local 응답 파일이 Proxyman `map-local/` 안이면 `store.mapLocalDirectory`로 복사하고 경로 교체, 밖이면 그대로, 없으면 규칙 `isEnabled = false` + `missingFiles`.
    - `static func previewFile(_ url: URL) throws -> ProxymanImportPreview` — 한 도구의 내보내기 파일(`.config` 노드 배열 또는 `{"nodes":…}`) 또는 EyeProxy 번들 폴더.
  - `public enum RuleBundle` — `static func export<R: ToolRule>(_ tree: RuleTree<R>, toolName: String, mapLocalDirectory: URL?, to folder: URL) throws` → `<folder>/rules.config`(노드 배열) + 참조 응답 파일을 `<folder>/map-local/`로 복사하고 경로를 `map-local/<파일명>` 상대 경로로. `previewFile`이 번들 폴더면 상대 경로를 절대 경로로 되돌린다.

- [ ] **Step 1: 실패 테스트**

```swift
@Test func previewReadsAllFiles() // 픽스처 → mapLocal 1, networkConditions 1, sslHosts == ["img.example.com", …], skipped 0
@Test func previewNeverWrites() // 픽스처를 임시 폴더로 복사, 권한 0o555로 막은 뒤 preview 성공 + 파일 목록·내용 변화 없음
@Test @MainActor func applyAppendsAndDedupes() // 두 번 apply → 규칙 수 그대로
@Test @MainActor func applyLeavesSwitchesOff() // apply 후 settings.toolSwitches == ToolSwitches()
@Test @MainActor func copiesResponseFileFromProxymanFolder() // 규칙 localFile.path가 store.mapLocalDirectory 안으로 바뀌고 파일 존재
@Test @MainActor func missingResponseFileDisablesRule() // 없는 경로 → isEnabled false, missingFiles 1
@Test @MainActor func graphQLRulesImportDisabled() // graphQLQueryName "GetUser" 규칙 → isEnabled false, graphQLDeferred 1
@Test func previewExportFileArray() // .config 노드 배열 → mapLocal 1
@Test func bundleRoundTrip() // export → previewFile(번들) → 응답 파일 경로 존재, 규칙 동일
@Test func brokenFileCountsSkipped() // 노드 하나 망가진 RuleTree → skipped 1 (Review Focus 3)
```

- [ ] **Step 2~4**, **Step 5: 커밋** — `feat(kit): Proxyman 규칙 가져오기와 규칙 번들`

---

### Task 14: App — 공통 도구 창·매칭 필드·Test your Rule·Tools 메뉴

**Files:**
- Create: `EyeProxy/Views/Tools/ToolWindow.swift`, `MatchRuleFields.swift`, `TestRuleSheet.swift`, `EyeProxy/Commands/ToolsCommands.swift`
- Modify: `EyeProxy/EyeProxyApp.swift`(Window 장면·commands), `EyeProxy/Views/FlowList/FlowListView.swift`(우클릭 Tools ▸)

**Interfaces:**
- Consumes: Task 5 `RuleStore`, `ToolSwitches`, Task 3 `MatchRule`.
- Produces:
  - `struct ToolWindow<Rule: ToolRule, Columns: TableColumnContent, Editor: View>: View` — 스펙 §6.2 레이아웃 그대로: `Toggle("Enable \(title) Tool")`(→ `settings.toolSwitches` 해당 값), 설명 한 줄, 회색 안내 "Each request is checked against the rules from top to bottom, stopping when a match is found." (Network Conditions는 별도 뷰), 규칙 표(폴더 접기, 드래그 순서 변경, 더블클릭 편집, 체크박스 = isEnabled), 빈 표 `Click "+" or ⌘N to add new entry`, 단축키 줄 `New: ⌘N  Edit: ⌘↩  Delete: ⌘⌫  Duplicate: ⌘D  Toggle: ␣`, 하단 `+ −`, `New Folder`, `?`, `Filter`(이름·URL 텍스트 필터), `More ▾`(Import…, Export…, 도구별 항목 슬롯). 삭제 확인 시트 "선택한 규칙을 삭제할까요? 되돌릴 수 없습니다."(취소/삭제).
    - 생성자 인자: `title: String, description: String, file: RuleFile<Rule>, newRule: () -> Rule, editor: (Binding<Rule>, _ onSave: @escaping (Rule) -> Void, _ onCancel: @escaping () -> Void) -> Editor, columns: …, editorStyle: .sheet | .window(id:)`.
    - ⌘N은 `newRule()`로 편집기를 열 뿐, 저장 전에는 트리에 넣지 않는다. 스위치를 바꾸지 않는다.
  - `struct MatchRuleFields: View` — `Name`, `URL`(placeholder `api.example.com/v1/*`), `[Method ▾]`(ANY / GET·POST·PUT·PATCH·DELETE·HEAD·OPTIONS 다중), `[Use Wildcard ▾ | Use Regex]`, "와일드카드 * 와 ? 지원" + `Test your Rule` 링크, `☐ Include all subpaths of this URL`, `☑ 쿼리 무시 (쿼리가 달라도 같은 규칙으로 처리)`, `validationError` 빨간 글씨, `hasQueryLikePattern && ignoreQuery`면 안내 문구(스펙 §4.2), 자동 복호화 표시: `hostPattern`이 있으면 회색 "이 호스트는 자동으로 복호화됩니다", regex·와일드카드뿐이면 주황 "SSL Proxying 목록에 호스트를 추가해야 동작합니다 [목록에 추가]".
  - `TestRuleSheet` — 패턴(현재 규칙 복사) + 샘플 URL 여러 줄(첫 줄 = 메인 목록 선택 요청 URL), 줄마다 `Matched`/`Not Matched`.
  - `ToolsCommands: Commands` — 스펙 §6.1 Tools 메뉴(이 태스크에서 만든 창들 + 이후 태스크 창 id 자리: `"tool-map-local"`, `"tool-map-remote"`, `"tool-breakpoint-rules"`, `"breakpoints"`, `"breakpoint-templates"`, `"tool-block"`, `"tool-allow"`, `"tool-network"`, `"compose"`, 시트 `"import-proxyman"`), `Enable/Disable Tools ▸` 체크 메뉴, No Caching 체크 ⌥⌘N. No Caching이 켜져 있으면 툴바 상태 캡슐에 "No Caching" 배지(스펙 §5.6의 상태줄 배지를 EyeProxy 툴바 캡슐로 대신 — **[내 판단]**). 이 태스크는 Block/Allow 창까지 연결하고(편집기는 Task 16), 나머지 항목은 해당 태스크가 채운다.
  - 우클릭 메뉴: `Tools ▸ Breakpoint… / Map Local… / Map Remote… / Block List… / Allow List… / Network Conditions…` — 선택 요청 URL로 미리 채운 새 규칙 편집기 열기(앱 상태 `model.pendingNewRule`).

- [ ] **Step 1: 빌드 가능한 최소 창** — Block List 창이 ToolWindow로 열리고 규칙 표·버튼·문구가 보인다(편집기는 임시 시트로 Name·MatchRuleFields만).
- [ ] **Step 2: 확인** — `xcodegen generate` + 앱 빌드 경고 0. 앱 실행 → Tools 메뉴 구성이 스펙 §6.1과 같고, Block List 창에서 ⌘N → 편집기 → 취소 시 규칙 0개, 저장 시 1개, 스위치는 그대로. Test your Rule에서 스펙 Task 3 표의 두 줄이 기대대로 표시. (스크린샷을 남긴다)
- [ ] **Step 3: 커밋** — `feat(app): 공통 도구 창·매칭 필드·Tools 메뉴`

---

### Task 15: App — Map Local 편집기·HTTP 메시지 편집기·Map Remote 시트

**Files:**
- Create: `EyeProxy/Views/Tools/MapLocalEditor.swift`, `HTTPMessageEditor.swift`, `MapRemoteSheet.swift`
- Modify: `EyeProxy/Views/Detail/CodeTextView.swift`(편집 가능 모드 `isEditable: Bool = false`, 변경 콜백), `ToolsCommands.swift`

**Interfaces:**
- Consumes: Task 7 `MapLocalRule`, `HTTPMessageFile`, Task 8 `MapRemoteRule`, `MapTarget.parse`, Task 14 `ToolWindow`, `MatchRuleFields`.
- Produces:
  - Map Local 창(`"tool-map-local"`, 열: Name(체크) · Method · Matching Rule("Wildcard: <url>"/"Regex: …") · Map from("File: <path>" / "Directory: <path>")), 설명 "Map a Response with a Local File or Directory. Support Status Code, Headers and Body."
  - `MapLocalEditor` — 별도 창 `WindowGroup(id: "map-local-editor", for: String.self)`(규칙 id, 새 규칙은 임시 id), 제목 "Map Local Editor: <이름>". 구성은 스펙 §6.3. 메시지 편집기는 `HTTPMessageEditor`(CodeTextView 편집 모드 + 저장 상태 점 "HTTP 메시지 형식(저장됨)" / "(수정됨)"), `Save ⌘S`로 규칙과 응답 파일(`<host>_<id>.http`) 저장. `Select Local File`, `[Local File | Local Directory]`, `Delay Response ▾`(`MapLocalRule.delayPresets`), More ▸ Default Local File Folder(Choose Folder / Use Default Folder / Reveal in Finder).
  - 우클릭 ▸ Tools ▸ Map Local…: 선택 흐름의 응답을 `HTTPMessageFile.serialize`로 채운 새 규칙.
  - Map Remote 창(`"tool-map-remote"`, 열: Enabled · Name · Method · Matching Rule · To), 설명 "Map Requests to different Host, Path, Port. Useful to map from Localhost ↔ Production.", 표 아래 회색 "localhost 요청이 안 보이면 /etc/hosts에 도메인 별칭을 설정하세요".
  - `MapRemoteSheet` — 스펙 §6.3 그대로, Host 칸 붙여넣기 시 `MapTarget.parse`로 칸 채우기, `[Cancel] [Add ⌘↩]`.
- [ ] **Step 1: 구현**
- [ ] **Step 2: 확인** — 빌드 경고 0. 앱에서 http://httpbin.org/json 요청 → 우클릭 Map Local… → 본문 수정 → ⌘S → 도구 켜기 → curl로 재요청 시 수정 본문(쿼리 무시 켬: `?x=1` 붙여도 적용). Map Remote: `http://httpbin.org/get` → host `postman-echo.com` → 응답이 postman-echo. 스크린샷 남김. (확인용 요청은 `curl -x http://127.0.0.1:<포트>` — 시스템 프록시를 바꾸지 않는다)
- [ ] **Step 3: 커밋** — `feat(app): Map Local 편집기와 Map Remote`

---

### Task 16: App — Breakpoint 창·템플릿, Block/Allow·Network Conditions 시트

**Files:**
- Create: `EyeProxy/Views/Tools/BreakpointRuleSheet.swift`, `BreakpointWindow.swift`, `BreakpointTemplatesWindow.swift`, `BlockAllowSheets.swift`, `NetworkConditionsSheet.swift`
- Modify: `ToolsCommands.swift`, `ToolWindow.swift`(Network Conditions 변형)

**Interfaces:**
- Consumes: Task 9·10·11 타입, Task 12 `model.breakpoints`.
- Produces:
  - Breakpoint 규칙 창(`"tool-breakpoint-rules"`, 열: Name · Method · Matching Rule · Request · Response, 하단에 `Templates…`), 설명 "Modify the Request/Response on the fly. Support URL, Method, Status Code, Headers, and Body.", 시트 = MatchRuleFields + `☐ Request ☐ Response`.
  - `BreakpointWindow`(`"breakpoints"`) — 왼쪽 대기 목록(메서드·URL·단계), 오른쪽 편집: 요청(URL 칸들·Method·Header 표·Query 표·Body·Raw) / 응답(Status·Header·Body·Raw), 버튼 `Continue Original ⌘.`, `Drop Connection ⌘\` + ▾(Abort: 429 / Abort: 503), `Apply & Execute ⌘↩`, Raw 탭 `Templates ▾`(목록 적용, Save as Template…, Reset to the Original). 새 대기 건이 생기면 창을 자동으로 앞으로(`openWindow`).
  - `BreakpointTemplatesWindow`(`"breakpoint-templates"`) — 스펙 §5.1(Request Templates / Response Templates 트리, ⌘N / ⇧⌘N).
  - Block 시트: MatchRuleFields + `Action ▾`(Block & Hide Request / Block & Display Requests / Hide, but not Block) + `Block App [Select App…]`(NSOpenPanel `.app`). Allow 시트: MatchRuleFields.
  - Network Conditions 창(`"tool-network"`, 열: Enabled · Name · Status(● Active) · Host · Network Profile), 주황 "Only 1 Rule can be activated at once.", 시트: Name, `☐ Apply System-wide` / Host, `Network Profile ▾`(presets + 저장된 사용자 프로필) + `Custom Profile…`(↓·↑ Mbps, 지연 ms, 손실 %).
- [ ] **Step 1: 구현**
- [ ] **Step 2: 확인** — 빌드 경고 0. Breakpoint: httpbin.org/get 규칙(요청+응답) → curl 요청 → 창 뜸, 헤더 추가 후 Apply & Execute → 응답 echo에 헤더 존재, 응답 단계 상태 418로 바꿔 Apply → curl 418. Abort 429 동작. Block & Display → 목록 "Blocked", curl 실패. Network: 3G 규칙 → 요청 시간이 늘어남. 스크린샷 남김.
- [ ] **Step 3: 커밋** — `feat(app): Breakpoint 창과 Block/Allow·Network Conditions 편집`

---

### Task 17: Kit+App — Compose·Repeat·Edit and Repeat·cURL 파서

**Files:**
- Create: `Packages/EyeProxyKit/Sources/EyeProxyKit/Compose/CurlParser.swift`, `ComposeClient.swift`, `EyeProxy/Views/Compose/ComposeView.swift`
- Modify: `ToolsCommands.swift`(Flow 메뉴), `FlowListView.swift`(우클릭 Repeat / Edit and Repeat…), `SettingsView.swift`(도구 탭: ☐ Repeat 요청에 No-Cache 사용)
- Test: `CurlParserTests.swift`, `ComposeClientTests.swift`

**Interfaces:**
- Produces:
  - `public enum CurlParser { static func parse(_ command: String) -> FlowRequest? }` — `curl` 접두, 작은·큰따옴표, `\` 줄바꿈, `-X/--request`, `-H/--header`, `-d/--data/--data-raw/--data-binary`(있으면 기본 POST), `--url`, `-G`(데이터를 쿼리로), `--compressed`·`-s`·`-k`·`-L` 무시. `CurlExport.command(for:)`의 출력과 왕복.
  - `public struct ComposeClient: Sendable { init(proxyPort: Int, trustRootDER: [UInt8]) ; func send(_ request: FlowRequest, timeout: TimeInterval?) async throws -> FlowResponse }` — URLSession(ephemeral, `connectionProxyDictionary`로 127.0.0.1:proxyPort HTTP·HTTPS, 서버 신뢰는 EyeProxy 루트만 추가 허용). 즉 Compose·Repeat 요청도 EyeProxy를 거쳐 목록에 기록되고 모든 도구가 적용된다.
  - Compose 창(`"compose"`, ⌥⌘C): 스펙 §5.8 레이아웃, Template ▾ 6종 + Import from cURL…, History ▾(최근 100개, `compose-history.json`), (…) ▸ Request Timeout 15/30/60/사용자 지정/없음.
  - Flow 메뉴: `Repeat ⌘↩`(선택 여러 건), `Edit and Repeat… ⌥⌘↩`(Compose를 그 요청으로 채워 열기). `toolSwitches.repeatNoCache`면 Repeat 요청에 No Caching 요청 헤더 규칙 적용.
- [ ] **Step 1: 실패 테스트**

```swift
@Test func parsesExportedCurl() // CurlExport.command(for: POST JSON 요청) → parse == 원 요청(메서드·URL·헤더·본문)
@Test(arguments: [
  ("curl https://api.example.com/a", "GET"),
  ("curl -d 'a=1' https://api.example.com/a", "POST"),
  ("curl -G -d 'q=1' https://api.example.com/s", "GET"),   // url ?q=1
  ("curl -X PUT -H 'X-A: b' --data-raw \"{\\\"k\\\":1}\" https://api.example.com/a", "PUT"),
  ("curl 'https://api.example.com/a' \\\n  -H 'Accept: */*' --compressed", "GET"),
]) func curlVariants(...)
@Test func garbageReturnsNil() // "ls -la" → nil
@Test func composeGoesThroughProxy() async throws // ProxyServer + TestOrigin, ComposeClient.send(http) → 200, server.events에 requestStarted
```

- [ ] **Step 2~4**: 실패 확인 → 구현 → 통과 + 앱 빌드 경고 0, 앱에서 Compose로 httpbin.org/post 전송·Repeat 확인.
- [ ] **Step 5: 커밋** — `feat: Compose·Repeat·cURL 가져오기`

---

### Task 18: App — Proxyman 가져오기 시트·내보내기·문서

**Files:**
- Create: `EyeProxy/Views/Tools/ImportProxymanSheet.swift`
- Modify: `ToolsCommands.swift`(Import Settings ▸ From Proxyman…), `ToolWindow.swift`(More ▸ Import… / Export…), `README.md`(도구 절과 Proxyman 가져오기), `docs/superpowers/plans/2026-11-05-eyeproxy-p1-handover.md` 옆에 `2026-11-08-eyeproxy-tools-p2-handover.md`(수동 검증 목록)

**Interfaces:**
- Consumes: Task 13 `ProxymanImporter`, `RuleBundle`.
- Produces:
  - `ImportProxymanSheet` — `ProxymanImporter.preview(defaultDirectory)` 결과를 도구별 개수 체크 목록으로(Map Local n, Map Remote n, Breakpoint n, Block n, Allow n, Network Conditions n, `☑ SSL Proxying 목록도 가져오기`), 건너뛴 수·없는 응답 파일·GraphQL 규칙(2차에서 지원, 꺼진 채로 추가) 경고, 안내 "가져온 도구는 꺼진 상태로 추가됩니다. 각 도구 창에서 켜세요.", `[취소] [가져오기]`, 결과 요약. Proxyman 폴더가 없으면 "Proxyman 데이터를 찾지 못했습니다".
  - More ▸ Import…: NSOpenPanel(`.config`, `.json`, `.eyeproxyrules` 폴더) → 같은 시트(해당 도구만). More ▸ Export…: NSSavePanel → `RuleBundle.export`.
  - handover 문서: 수동 E2E 목록(사용자 실행) — ① 실제 Proxyman 데이터 가져오기 후 Map Local 13개 동일 표시·도구 꺼짐 확인 ② Map Local `?*` 규칙이 Proxyman과 같은 요청에 적용 ③ 자동 복호화: SSL 목록에 없는 host의 Map Local 동작 ④ Apple TV 실기기에서 Breakpoint ⑤ Network Conditions 3G 체감 ⑥ 팀원에게 번들 내보내기 → 다른 Mac에서 가져오기.
- [ ] **Step 1: 구현**
- [ ] **Step 2: 확인** — 빌드 경고 0. Kit 픽스처 폴더를 대상으로 시트를 띄워(디버그 메뉴 또는 `ProxymanImporter.preview(proxymanDirectory:)`에 픽스처 경로 주입) 개수·경고 표시 확인. **실제 Proxyman 폴더 가져오기는 사용자가 실행**(에이전트는 실행하지 않는다).
- [ ] **Step 3: 커밋** — `feat(app): Proxyman 가져오기와 규칙 내보내기`
