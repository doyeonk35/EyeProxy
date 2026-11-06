# EyeProxy Flow 화면 가독성 — 설계

작성 2026-11-05. 기준: `2026-11-05-eyeproxy-design.md` §4.3, P1 핸드오버 3절 백로그, Proxyman 캡처 4장(`~/Desktop/proxyman_ref/`), 브레인스토밍 목업 v2(`.superpowers/brainstorm/*/content/flow-screen-v2.html`)에서 사용자가 고른 **A안(정돈형)**.

## 1. 의도

사용자는 Proxyman을 매일 쓰다가 EyeProxy로 갈아타려는 사람이다. P1에서 트래픽은 보이지만 Flow 화면이 Proxyman보다 읽기 어려워 "지우고 이걸 쓴다"에 못 미친다. 네 가지가 걸린다.

1. 목록 순서가 불안정하다 — `#`이 필터 위치 기반이라 필터를 걸면 번호가 바뀌고, 헤더 클릭 정렬이 없다.
2. Mac 트래픽이 앱별로 안 나뉜다 — Safari·시뮬레이터·Xcode가 "이 Mac" 하나에 섞인다.
3. 상세(요청/응답)가 읽기 어렵다 — 모노스페이스 굵은 키, 구획 없음, 색 없음.
4. 긴 값이 가로로 늘어난다 — URL·헤더 값·본문이 줄바꿈 없이 가로 스크롤.

성공 = 사용자가 앱을 띄워 Proxyman 캡처와 나란히 놓고 "이 정도면 된다"고 말한다.

## 2. 목표 · 비목표 · 안티골

**목표**
- 고정 `#` ID(수신 순)와 컬럼 헤더 정렬.
- 사이드바를 트리로: 고정 호스트 → 기기(이 Mac은 앱별, 그 아래 도메인; 원격 기기는 도메인) → 전체 도메인.
- 상세 영역을 A안 스타일로: Method·Status 캡슐, 줄바꿈되는 색 입힌 URL, Key/Value 헤더 표, 줄번호·색상이 있는 본문, 쿠키 탭, 복사·cURL 버튼.
- 줄바꿈 기본, 토글로 끔. 라이트/다크 모두 자연스럽게.

**비목표**
- Tools(P2 기능) 일체. 다중 필터·Regex. Custom Previewer Tab. Pin/Comment(요청 단위 핀은 P2 — 여기의 "고정"은 **호스트** 고정).
- Pretty 본문 안에서의 접기(Tree 탭이 접기를 담당한다). 컬럼 너비 저장(기존 `TableColumnCustomization`이 이미 한다).
- 앱별 귀속의 영속 보장 — 연결이 lsof 전에 닫히면 "기타"로 간다. 100%는 노리지 않는다.

**안티골(기술적으로 돼도 실패인 것)**
- 시스템 설정을 바꾸는 명령 실행(`networksetup`·`scutil` 등은 이 작업에서 손대지 않는다).
- Core에 UI·프로세스 개념을 넣는 것. Core 변경은 전송 사실(클라이언트 포트) 한 필드뿐.
- 큰 본문(2MB)에서 UI가 멈추는 것. 지금 되는 것(2MB 컷·NSTextView 폴백)은 유지한다.
- 빌드 경고, 기존 테스트 실패, Localizable.xcstrings 누락.

## 3. 제약

- `EyeProxy`(앱) → `EyeProxyKit` → `EyeProxyCore` 단방향. Core는 UI 무관. Kit는 AppKit을 import하지 않는다(현재도 안 함). 아이콘·NSRunningApplication은 앱 레이어.
- 외부 패키지 추가 금지. 락 금지(actor·MainActor).
- 문자열은 `EyeProxy/Localizable.xcstrings`(ko) — 새 UI 문자열은 카탈로그에 항목을 추가한다(값이 비어 있어도 된다, 기존 `"#" : {}` 처럼).
- 사용자가 main 체크아웃에서 앱을 실행 중 → 전용 worktree 브랜치 `worktree-flow-readability`에서 작업, PR로 마무리.
- 시스템 명령은 읽기 전용(`lsof`, `simctl list`)만.

## 4. 결정 사항(사용자가 정한 것)

- **정렬**: Proxyman과 동일. `#` ID는 수신 순(1, 2, 3…)으로 고정되고 필터를 걸어도 유지된다. 기본 정렬 `#` 오름차순(최신이 아래). 컬럼 헤더 클릭으로 `#`·Method·URL·Status·Size·Time 정렬 전환, 다시 누르면 역순.
- **사이드바**: 트리. "이 Mac" 아래 앱(프로세스), 그 아래 도메인. 원격 기기 아래 도메인. 맨 위에 **고정 호스트** 영역(우클릭 "고정"/"고정 해제", 순서 저장, 0건이어도 표시). 맨 아래 "도메인" 섹션 유지.
- **스타일**: A안(정돈형). Proxyman과 똑같을 필요 없음. 라이트/다크 둘 다(시스템 외관 따라감).
- **줄바꿈**: 기본 켬. 끄면 가로 스크롤(Proxyman 방식).
- **시뮬레이터**: 시뮬레이터 앱은 "TVING (tvOS 시뮬레이터)"처럼 별도 앱 노드로.

## 5. 설계

### 5.1 고정 `#`와 정렬 (Kit + 앱)

- `SessionStore`가 `requestStarted`마다 단조 증가 번호를 매긴다: `numbers: [FlowID: Int]`, `number(_ id:) -> Int?`. `clear()`는 0으로 리셋, `replace(flows:)`는 배열 순서대로 1…n 재부여(저장 세션에는 번호를 쓰지 않는다 — 열 때 순서가 곧 번호).
- Kit에 `FlowRow`(Sendable, Identifiable by FlowID): `number`, `flow`, 그리고 정렬용 파생값 `status: Int`(응답 없음 = -1, 오류 = -2), `size: Int`(응답 없음 = -1), `durationMS: Int`(미완 = -1), `url: String`, `method: String`. `KeyPathComparator<FlowRow>`로 SwiftUI `Table(sortOrder:)`에 바로 쓴다.
- `AppModel.visibleRows: [FlowRow]` = `visibleFlows` → `FlowRow` → `sorted(using: sortOrder)`. `sortOrder`는 `AppModel`의 상태(기본 `[KeyPathComparator(\.number)]`), 저장하지 않는다.
- 테스트(Kit): 번호가 필터와 무관하게 유지, clear 후 리셋, replace 후 재부여; `FlowRow` 파생값과 정렬(응답 없음이 맨 앞/뒤에 안정적으로).

### 5.2 앱별 귀속 (Core 1필드 + Kit `ProcessResolver`)

**Core(최소 변경)**: `Flow.clientPort: Int`(기본 0). `ProxyConnectionHandler`가 `context.channel.remoteAddress?.port`를 읽어 `ProxyServer.exchange`(일반 흐름이 만들어지는 곳)와 CONNECT 터널 항목에 넘긴다. MITM 복호화 요청도 같은 클라이언트 채널 위라 포트가 같다. `init(from:)`은 `decodeIfPresent`로 옛 세션 파일을 그대로 읽는다. `ConnectionLogEntry`는 손대지 않는다.

**Kit `ProcessResolver`(actor)**: 로컬 클라이언트(127.0.0.1/::1)의 `clientPort`를 PID로 바꾼다.
- 호출: `resolve(port:) async -> ProcessIdentity?`. 내부는 **100ms 디바운스 후 lsof 1회**로 대기 중인 포트를 한꺼번에 푼다: `/usr/sbin/lsof -nP -iTCP:<proxyPort> -F pcn`. 출력의 `n` 줄 `127.0.0.1:<clientPort>->127.0.0.1:<proxyPort>`에서 `clientPort → (pid, command)`를 만든다. 자기 자신(EyeProxy pid)은 제외.
- **헬퍼 프로세스 → 책임 앱** [내 판단]: macOS에서 Safari·WKWebView 앱의 소켓은 `com.apple.WebKit.Networking`이, 백그라운드 URLSession은 `nsurlsessiond`가 연다. 그대로 두면 Safari 노드가 생기지 않는다. 그래서 lsof가 준 pid를 `responsibility_get_pid_responsible_for_pid`(libquarantine에 있는 비공개 함수 — `dlsym`으로 찾고, 없거나 실패하면 원래 pid 그대로)로 책임 pid로 바꾼 뒤 그 pid의 경로를 쓴다. Proxyman·Little Snitch가 쓰는 방식이고 사내 배포 앱이라 App Store 심사 문제는 없다. `nsurlsessiond`처럼 책임 pid가 자기 자신인 시스템 데몬은 그 이름 그대로 노드가 된다.
- `ProcessIdentity: Codable, Hashable, Sendable { pid: Int32, name: String, path: String?, simulator: SimulatorRef? }`. `path`는 `proc_pidpath`(Foundation만으로 호출 가능, 확인함)로 얻는다. `name`은 lsof의 `c` 필드(15자 절단)가 아니라 `path`에서 뽑는다: 경로에 `.app` 번들이 있으면 그 번들 이름, 없으면 마지막 경로 요소. `path`에 `/CoreSimulator/Devices/<UDID>/`가 있으면 `simulator = (udid, appName)`이고 `name`은 `.app` 번들 이름("TVING"). 표시명은 Kit의 순수 함수 `ProcessIdentity.displayName(runtime:)`: 시뮬레이터면 `"<앱> (<플랫폼> 시뮬레이터)"`(플랫폼은 `SimulatorDevice.runtime`의 첫 단어, 모르면 "시뮬레이터"), 아니면 `name`.
- 캐시: `port → ProcessIdentity`(포트 재사용은 드물고, 같은 keep-alive 연결의 후속 요청이 즉시 맞는다). 실패(연결이 이미 닫힘)는 캐시하지 않는다.
- 결과는 `ProcessRegistry`(@Observable @MainActor, Kit): `attribution: [FlowID: ProcessIdentity]`. `AppModel.handle(event)`가 `requestStarted`에서 로컬 클라이언트면 `Task { await resolver.resolve(port:) }` 후 등록한다.
- 세션 저장: `SessionDocument.Index`에 `processes: [String(FlowID uuid): ProcessIdentity]?`(옵션 키, 없으면 무시). `save(flows:connectionLog:processes:)`/`load`가 반환. 버전은 1 유지(추가 키만).
- 그룹 키: `ProcessIdentity.groupKey` = 시뮬레이터면 `"sim:<udid>:<appName>"`, 아니면 `path ?? name`(같은 앱의 재실행이 같은 노드로 모이게 pid는 키에 안 넣는다).
- 테스트(Kit): lsof `-F pcn` 출력 파싱(포트→pid, 자기 pid 제외, `f` 줄 무시, IPv6 `[::1]:port` 형식), 시뮬레이터 경로 파싱, 경로→이름, displayName, groupKey, SessionDocument 왕복(processes 있을 때/없을 때). Core: `clientPort` 없는 JSON 디코드. (책임 pid 조회는 시스템 호출이라 단위 테스트하지 않고 실행으로 확인.)

### 5.3 사이드바 트리 (Kit `SidebarTree` + 앱)

- Kit 순수 함수 `SidebarTree.build(flows:, attribution:, devices:, pinned:) -> SidebarTree`:
  - `pinned: [HostNode]` — 설정 순서대로, count는 현재 세션 기준(0 허용).
  - `devices: [DeviceNode { address, displayName, kind, count, apps: [AppNode], hosts: [HostNode] }]` — **현재 세션의 흐름에서** 만든다(`clientAddress`별 그룹, count는 세션 기준). 레지스트리는 이름·종류를 붙이는 데만 쓰고, 세션에 흐름이 없는 기기는 보이지 않는다(핀 호스트와 달리 사용자가 고른 것이 아니므로). 저장 세션을 열면 그 안의 기기가 레지스트리에 없어도 노드가 생기고, 루프백 주소는 어느 Mac에서 저장했든 "이 Mac"으로 본다. 기기 정렬은 마지막 흐름 시각 내림차순. [내 판단 — 지금 사이드바 배지가 누적 flowCount인 것은 핸드오버 백로그의 불일치 항목이기도 하다. 누적 수치는 기기 창에 그대로 남는다.] `kind == .thisMac`이면 `apps`(각 `AppNode { groupKey, displayName, path, count, hosts }`, count 내림차순, 귀속 없는 흐름은 `groupKey = "unknown"`, 이름 "기타")를 채우고 `hosts`는 비운다. 원격 기기는 `hosts`만.
  - `hosts: [HostNode]` — 전체 도메인, 사전순.
- `SidebarItem`을 `.allFlows | .host(String) | .scope(FlowScope)`로 바꾼다. `FlowScope: Hashable { device: String?, process: String?, host: String? }`. `FlowFilter`에 `process: String?`를 추가하고 `matches(_ flow:, process: String?)`로 귀속을 받는다(기존 `matches(_:)`는 `process: nil`로 위임).
- 앱 `SidebarView`: `List(selection:)` + `Section` + `DisclosureGroup`(기기·앱 노드). 핀/기기/앱/도메인 행 모두 `.tag(SidebarItem)`. 호스트 행 우클릭 → "고정"/"고정 해제"(`AppSettings.pinnedHosts: [String]`, UserDefaults). 아이콘: 앱 노드는 `NSWorkspace.shared.icon(forFile: path)`(없으면 `app`), 기기는 기존, 핀은 `pin.fill`.
- 선택 유지: `clear()`·세션 열기 시 `.scope`는 `.allFlows`로 돌린다(기존 `.host` 처리와 같은 이유).
- 테스트(Kit): build 결과(이 Mac 앱 분리·기타 노드·원격 기기 도메인·핀 0건·카운트), `FlowFilter` process 매칭.

### 5.4 상세 영역 (앱)

- **FlowHeaderBar**(두 pane 위, `FlowDetailView` 상단): `MethodTag` + `StatusTag` + URL `Text`(AttributedString: 스킴·호스트 primary/semibold, 경로 accent, 쿼리 키 primary·값 secondary; 줄바꿈, `.textSelection`), 오른쪽에 "복사"(URL)·"cURL" 버튼. 레이아웃 B(좌우)에서도 상단 한 줄.
- **태그**: `MethodTag(method)` / `StatusTag(flow)` — 11pt semibold, 캡슐, 전경색 + 15% 배경. 색은 Asset Catalog 색 세트(라이트/다크 각각): `MethodGet`(파랑) `MethodPost`(주황) `MethodPut`(보라) `MethodDelete`(빨강) `MethodOther`(회색), `StatusSuccess`(초록) `StatusRedirect`(노랑) `StatusError`(빨강) `StatusPending`(회색). 목록 Method·Status 컬럼과 헤더 바가 같은 뷰를 쓴다.
- **탭**: 요청 = 헤더 · 쿼리 · 본문 · 쿠키, 응답 = 헤더 · 본문 · 쿠키. 기존 segmented `Picker` 유지. 쿠키 = 요청 `Cookie` 헤더를 `;`로 나눈 name=value, 응답 `Set-Cookie` 헤더마다 첫 `name=value`(속성은 값 뒤에 secondary로 붙임). 파서는 Kit `CookieParser`(테스트).
- **KeyValueTable**(헤더·쿼리·쿠키 공용): `ScrollView { LazyVStack(spacing: 0) }`, 행 = `HStack(alignment: .firstTextBaseline) { key(160pt 고정, secondary, semibold, 줄바꿈 허용) ; value(primary, 줄바꿈, textSelection) }`, 행 사이 `Divider`, 호버 시 배경 `quaternary`, 우클릭 "값 복사"·"이름: 값 복사". 시스템 폰트 13pt. 빈 목록은 기존 `ContentUnavailableView`.
- **본문**: 모드 Pretty · Tree · Raw(JSON일 때), 텍스트는 Raw만, HTML은 기존 미리보기/소스. 오른쪽에 `줄바꿈` 체크(`AppSettings.wrapLongLines`, 기본 true) · 크기/인코딩 캡션(기존 summary 이동). **줄바꿈 토글은 본문에만 적용**된다 [내 판단, 목업 A와 동일]: 헤더·쿼리·쿠키 값과 상단 URL은 항상 줄바꿈이다(짧은 값이 대부분이고 표에서 가로 스크롤은 읽기를 더 해친다).
  - `CodeTextView`(NSViewRepresentable, NSTextView): 읽기 전용·선택 가능, 모노스페이스 12.5pt, 줄번호 거터(`NSRulerView` 서브클래스, `textBackgroundColor`보다 한 단계 어두운 배경), `wrap`이면 `widthTracksTextView = true`·수평 스크롤 끔, 아니면 반대. 기존 `LargeText`를 흡수한다(256KB 경계 제거 — NSTextView 하나로 통일).
  - JSON 색: Kit `JSONHighlighter.tokens(_ pretty: String) -> [JSONToken { range: Range<String.Index>, kind: .key | .string | .number | .keyword | .punctuation }]`(pretty 출력 형식 `"key" : value`를 전제로 한 1패스 스캐너). 앱이 kind → Asset 색(`JSONKey` `JSONString` `JSONNumber` `JSONKeyword`)으로 `NSAttributedString`을 만든다. 256KB 초과 본문은 색 없이(성능) 표시한다.
  - Raw = 디코드 전 원문 문자열. `DecodedBody.json(pretty:raw:)`로 Kit가 둘 다 돌려준다.
  - Tree: 기존 `JSONTreeView` 유지하되 키 순서는 원문 순서(핸드오버 백로그) — `JSONSerialization` 대신 pretty 텍스트를 `JSONHighlighter`와 같은 스캐너로 노드화. 접기는 여기서.
- `BodyView`의 2MB 컷·hex 덤프·이미지 미리보기는 유지.

### 5.5 목록 (앱)

- `Table(rows, selection:, sortOrder: $model.sortOrder, columnCustomization:)` over `[FlowRow]`. 컬럼: `#`(`\.number`, 우측 정렬, secondary) · Method(`MethodTag`) · URL(호스트 primary + 경로·쿼리 secondary, 한 줄·중간 생략) · Status(`StatusTag`) · Size · Time · 숨김 컬럼(Host·Content-Type·기기·시작 시각·**앱**). 각 컬럼에 `KeyPathComparator`를 준다.
- `.alternatingRowBackgrounds(.disabled)`, 행 구분선은 Table 기본.
- 기존 컨텍스트 메뉴(SSL 프록싱·cURL) 유지.

### 5.6 라이트/다크

시스템 외관을 따른다. 색은 전부 semantic(`.primary` `.secondary` `NSColor.textBackgroundColor` `controlBackgroundColor`) 또는 Asset Catalog 색 세트(Any/Dark 두 값)로 둔다. 하드코딩 `Color.green/.red`는 없앤다.

### 5.7 설정 추가(`AppSettings`)

`pinnedHosts: [String]`(기본 []), `wrapLongLines: Bool`(기본 true). 둘 다 UserDefaults, 기존 패턴(`didSet` 저장)대로. 테스트 추가.

## 6. 빌더에게 맡기는 것

- `DisclosureGroup` 펼침 상태 저장 여부(기본: 저장 안 함, 처음엔 모두 펼침).
- `CodeTextView`의 줄번호 거터 폭·색 세부, 탭 전환 시 스크롤 위치.
- lsof 디바운스 시간(100ms 제안)과 실패 재시도(1회 제안: 첫 조회에 없으면 300ms 후 한 번 더).
- 큰 본문에서 색 끄는 경계(256KB 제안).
- 컬럼 정렬 중 새 흐름이 들어올 때의 선택 유지(선택은 `FlowID`라 자연히 유지됨 — 확인만).

## 7. 검증

- `swift test`(Core·Kit) 전부 통과 + 새 테스트. `xcodebuild` 경고 0.
- 사용자가 앱을 실행해 Proxyman 캡처와 비교: (1) 필터 걸어도 `#` 유지·헤더 정렬, (2) Safari·시뮬레이터 앱·Apple TV가 사이드바에서 갈라짐, (3) 상세 영역 가독성, (4) 긴 Cookie·URL이 줄바꿈되고 본문은 줄바꿈 토글로 꺼짐, (5) 라이트/다크 전환.
