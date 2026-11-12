# Prog 호스트 그룹 탭·탭 복원·기기 이름·Android 안내·SSL 묶음 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 이번 묶음에서 다섯 가지를 넣는다.
- **호스트 그룹 탭:** 도메인 패턴과 이 Mac 앱을 묶은 그룹을 탭 하나로 본다. File ▸ New Domain or App ⇧⌘K로 만들고 사이드바 Favorites ▸ Groups에 둔다.
- **탭 복원:** 종료할 때 열린 탭을 다음 실행에 다시 연다.
- **기기 이름:**
  - 원격 기기는 ARP 표의 MAC으로 알아본다. IP가 바뀌어도 이름이 따라간다.
  - 이 Mac의 LAN IP에는 컴퓨터 이름을 붙인다.
  - Android TV·Google TV·Android 폰 종류를 둔다.
- **Android 안내:** TV·Google TV는 "디버그 빌드에 CA 넣기"로 안내한다.
- **SSL Proxying 호스트 목록:** 평문 파일로 가져오고 내보내며, 한 번에 켠다.

**Architecture:**
- **Kit(테스트 있음):** 순수 로직을 먼저 Kit에 넣는다.
  - 호스트 패턴 매처는 Core에 둔다.
  - 호스트 목록 파일, `HostGroup`과 필터·사이드바 연결, 탭 저장본과 복원 순서
  - 기기 종류 호환 인코딩, ARP 표 해석과 MAC 맞추기
  - Android 스니펫
- **앱:** Kit 위에 UI와 연결을 얹는다.
  - SSL 가져오기·내보내기
  - 그룹 시트·사이드바, 복원 연결
  - 기기 연결, Android 화면
- **빌드 유지:** Kit 태스크가 앱 컴파일을 깨는 부분은 그 태스크 안에서 최소로 고쳐, 커밋마다 앱이 빌드되게 한다.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Darwin(`sysctl` 라우팅 표), SystemConfiguration(컴퓨터 이름), swift-testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-13-prog-host-tabs-devices-ssl-design.md`

## 내가 정한 것 (스펙의 "(내 판단)" 요약)

1. **호스트 그룹의 모양:** 도메인 패턴 목록과 이 Mac 앱 목록이고, 둘 중 하나에 맞으면 맞다(OR). 사이드바 선택의 한 종류(`SidebarItem.group`)라서 탭 출처는 하나라는 Proxyman 규칙을 따른다.
2. **New Domain or App ⇧⌘K 시트:**
   - 이름이 비면 "첫 항목 외 N"이다.
   - 세션의 도메인·앱을 골라 넣을 수 있고, 앞 탭의 선택으로 미리 채운다.
   - "Favorites에 저장"은 기본 켬이다.
   - Open은 앞 탭과 같은 세션을 보는 새 탭을 연다.
3. **와일드카드 `?`:** SSL·그룹 패턴에 `?`(한 글자)를 넣어 Proxyman 문법과 맞춘다.
4. **그룹 지우기·내보내기:**
   - Delete는 확인 없이 지우고, 그 그룹을 보던 탭은 그대로 둔다.
   - 그룹 Export에는 도메인 패턴만 넣는다(앱 키는 Mac마다 다를 수 있다).
5. **탭 복원:**
   - General ▸ Restore Tabs at Launch(기본 켬)로 켜고 끈다. 종료가 확정될 때 저장한다.
   - 저장하는 것은 탭 종류, 파일 경로, 사이드바 선택, 필터 규칙과 AND/OR, 앞 탭 위치다.
   - 복원은 한 창에 모으고 라이브 탭을 맨 앞에 둔다.
   - 사라진 파일은 알림 없이 건너뛴다.
6. **MAC 맞추기:**
   - ARP 표는 `sysctl`로 읽고, 같은 주소는 60초에 한 번만 읽는다.
   - 기록은 지우지 않는다. 주소마다 가장 최근 기록이 그 주소를 대표한다.
   - `Device.id`는 `mac ?? address`다.
7. **이 Mac LAN IP의 이름:** Bonjour 대신 `SCDynamicStoreCopyComputerName`으로 읽는다. 그래서 권한 창이 없다.
8. **Cast 광고 `md` → 종류:**
   - "Google TV"가 들어 있거나 "Chromecast"로 시작하면 Google TV.
   - Google Home·Nest 계열은 종류를 비운다.
   - 나머지는 Android TV.
   - Android 폰은 직접 고른다.
9. **`devices.json` 호환:** 새 종류는 `kind: "unknown"`과 `extendedKind`로 쓴다. 모르는 `kind` 값은 "알 수 없음"으로 읽는다.
10. **Android TV·Google TV 탭:** CA push와 "인증서 설치 화면 열기"를 뺀다. "디버그 빌드에 CA 넣기" 절이 중심이다.
11. **호스트 목록 파일:**
    - UTF-8 평문, 한 줄에 패턴 하나, `#` 주석. URL은 호스트만, 포트는 뗀다. 허용 글자 밖의 줄은 버린다.
    - 1 MB 상한. Proxyman SSL JSON(`{"nodes":…}`)도 읽는다.
    - 가져오기는 확인 알림을 거쳐 기존 목록에 더하기(Append)만 한다. `*`는 경고한다. "호스트 그룹으로도 저장"은 기본 켬이다.
12. **Enable SSL Proxying for All Domains:** 기기·앱 우클릭에서 쓴다. 이 탭 세션에서 그 기기·앱이 쓴 호스트를 더한다.

## Global Constraints

- **패키지:** 외부 패키지는 허용 목록(swift-nio, swift-nio-ssl, swift-nio-extras, swift-certificates, swift-asn1, swift-crypto, Sparkle) 밖의 것을 추가하지 않는다. 시스템 프레임워크(Darwin, Network, SystemConfiguration)는 괜찮다.
- **모듈 방향:** 앱 → Kit → Core. 역방향 import 금지.
- **App Sandbox:** 끈다. entitlements는 빈 dict 그대로 둔다.
- **커밋 메시지:** `<type>(<scope>): <한국어 요약>`. 끝에 빈 줄과 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`를 붙인다. `git add`는 그 태스크의 파일만 한다.
- **공개 레포:**
  - 커밋할 파일에 회사 도메인, 사내 호스트 목록, 로컬 사용자 경로, 실제 기기 IP·MAC·코드명을 넣지 않는다.
  - 예시는 다음만 쓴다: `example.com`·`example.org`·`example.net`, 주소 `192.0.2.x`, 문서용 MAC `00:00:5e:00:53:xx`, 지어낸 이름("거실 TV", "테스트 Mac").
  - 팀 공용 목록은 레포 밖 파일이다. 프리셋을 코드에 넣지 않는다.
  - 커밋 전에 `git diff --cached | grep -nE '/Use[r]s/|192[.]168[.]|tving[.]com'`이 아무것도 내지 않아야 한다. 대괄호는 이 문서 자체가 걸리지 않게 하려는 것이다.
  - 실제 기기 코드명·사내 호스트는 패턴으로 다 잡을 수 없으므로, 문구와 테스트 값을 눈으로도 본다.
- **플랫폼:** macOS 15+.
- **세션 파일:** 형식은 바꾸지 않는다(`index.json` version 1).
- **`devices.json`:** 사용자의 릴리스 앱(옛 코드)도 읽는 파일이다.
  - `kind`에는 옛 값(`thisMac`, `appleTV`, `iPhone`, `iPad`, `unknown`)만 쓴다.
  - 새 정보는 새 키(`extendedKind`, `mac`)에만 쓴다.
- **메뉴 이름(영어):** `New Domain or App…`, `Groups`, `Enable SSL Proxying for All Domains`, `Restore Tabs at Launch`.
- **단축키:** New Domain or App… ⇧⌘K. 이번에 새로 쓰는 단축키는 이것뿐이다. 지난 묶음의 단축키는 그대로 둔다.
- **작업 위치:**
  - 워크트리 `EyeProxy-next`(메인 체크아웃 옆 폴더, 절대 경로는 실행을 맡긴 쪽이 알려 준다), 브랜치 `feat/host-tabs-devices-ssl`에서 작업한다.
  - main에 직접 커밋하지 않는다.
  - 다른 체크아웃(메인 체크아웃 포함)은 건드리지 않는다.
- **빌드·테스트**(워크트리 루트에서):
  - `swift test --package-path Packages/EyeProxyCore`
  - `swift test --package-path Packages/EyeProxyKit`
  - `xcodegen generate`
  - `xcodebuild build -scheme EyeProxy -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates 2>&1 | tail -3`
  - `swift test`가 `Package.resolved`를 바꾸면 `git checkout`으로 되돌린다.
- **Debug 앱 규칙(에이전트):**
  - 에이전트는 Debug 앱을 **실행하지 않는다.** 이유는 셋이다.
    - Debug 앱은 사용자의 릴리스 앱과 `~/Library/Application Support/com.tv.eyeproxy`(`devices.json`, CA, 규칙)를 같이 쓴다.
    - 기기 이름 기능 이후로는, 실행하면 원격 기기가 든 `devices.json` 때문에 로컬 네트워크 권한 창이 뜬다. 에이전트는 그 창에 응답하면 안 된다.
    - 실행 중에 `devices.json`을 다시 쓰게 된다.
  - 실행하지 않고 할 수 있는 확인만 한다. Kit 테스트, 앱 빌드, 빌드된 `Contents/Info.plist`를 `plutil -p`로 보기, 소스 grep이다.
  - 앱 화면 확인은 모두 사용자 점검표(Task 12 핸드오버)로 넘긴다.
  - 다음은 건드리지 않는다: 지원 폴더의 파일, `/Applications/Prog.app`, 사용자의 Prog-Debug.app, Proxyman, `~/Library/Application Support/com.proxyman.NSProxy`, 시스템 프록시·키체인·CA 신뢰, `com.tv.eyeproxy*` defaults.
  - 테스트는 임시 폴더와 `UserDefaults(suiteName: UUID().uuidString)`만 쓴다.

## Review Focus

1. **`devices.json` 아래 호환:**
   - 새 코드가 쓴 파일에서 `kind` 값은 늘 옛 다섯 값 중 하나다.
   - 모르는 `kind` 값(`"smartFridge"`)이 든 파일을 읽어도 손상 처리(옆으로 옮기기)가 일어나지 않는다.
   - 확인: Task 4 테스트 `androidKindIsWrittenCompatibly`, `unknownKindValueDoesNotCorruptFile`.
2. **MAC 맞추기에서 이름 보존:**
   - 어떤 경로에서도 직접 붙인 이름이 지워지거나 다른 MAC의 기록으로 옮겨지지 않는다.
   - 같은 주소에 기록이 둘이어도 `Device.id`가 겹치지 않는다. `ForEach`와 이름 바꾸기가 id로 동작한다.
   - 확인: Task 5 테스트 네 개, Task 10의 `rename(id:)`.
3. **그룹 필터 성능:**
   - 정규식은 `PreparedFilter`나 `SidebarTree.build`마다 한 번만 만든다. 흐름마다 만들지 않는다.
   - 와일드카드 없는 패턴은 집합으로 본다.
   - 확인: Task 1·2 코드 리뷰. `HostPatternSet`을 반복문 밖에서 만드는지 본다.
4. **복원 경계:**
   - 저장은 종료가 확정된 뒤 한 번만 한다. 종료 확인에서 취소하면 저장하지 않는다.
   - 라이브 탭이 늘 맨 앞이다.
   - 필터 규칙을 `settings.filterRules`에 쓰는 탭은 `mainTab` 하나뿐이다.
   - 사라진 파일 탭은 알림도 빈 탭도 남기지 않는다.
   - 확인: Task 3 테스트, Task 9 코드 리뷰, 사용자 점검표.
5. **가져오기 신뢰 경계:**
   - 파일은 남이 준 것이다. 1 MB 상한, 허용 글자 검사, 확인 알림을 거친 뒤에만 반영한다.
   - `*`는 경고 문구로 알린다.
   - 네트워크를 쓰지 않는다.
   - 확인: Task 1 테스트, Task 7 코드 리뷰.
6. **권한 창:**
   - 이 Mac 이름은 Bonjour를 시작하지 않는다.
   - ARP 읽기는 권한이 필요 없다.
   - `startDiscoveryIfRemoteDeviceSeen`의 조건은 바뀌지 않는다.
   - 확인: Task 10 diff.
7. **공개 레포 문자열:** 모든 커밋에서 Global Constraints의 grep이 빈 결과다. 특히 Android 안내 문구와 테스트 값을 본다.

앱 타깃에는 테스트 타깃이 없다. 앱 쪽 동작은 사용자 점검표로 확인한다(Debug 앱 규칙).

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `Packages/EyeProxyCore/Sources/EyeProxyCore/HostPattern.swift` (새로) | `HostPatternSet`: `*`·`?` 와일드카드 매처(한 번 컴파일) |
| `Packages/EyeProxyCore/Sources/EyeProxyCore/SSLProxyingPolicy.swift` | 매칭을 `HostPatternSet`으로 |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/HostList.swift` (새로) | 호스트 목록 파일 해석, 쓰기, 합치기 |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/HostGroup.swift` (새로) | `HostGroup`, `HostGroupMatcher` |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/FlowFilter.swift` | `FlowScope: Codable`, `FlowFilter.group`, `PreparedFilter`의 그룹 판정 |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/SidebarTree.swift` | `SidebarItem.group`·`Codable`, `GroupNode`, `groups` |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/TabSnapshot.swift` (새로) | `TabSnapshot`, `OpenTabs`, `RestorePlan` |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/AppSettings.swift` | `hostGroups`, `openTabs`, `restoreTabsAtLaunch` |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/Devices/DeviceRegistry.swift` | Android 종류, 호환 인코딩, `mac`, MAC 맞추기, `markThisMac` |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/Devices/DeviceDiscovery.swift` | Cast `md` → 종류 |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/Devices/ARPTable.swift` (새로) | `sysctl` ARP 표 읽기·해석 |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/Onboarding/AndroidSetup.swift` | CA 번들 XML, 명령, TV 명령 |
| `Packages/EyeProxyKit/Sources/EyeProxyKit/Import/ProxymanImporter.swift` | `sslHosts(_:)`를 모듈 안에서 쓸 수 있게(`private` → 내부) |
| `EyeProxy/AppModel+HostList.swift` (새로) | SSL 가져오기·내보내기, 호스트 목록 저장 패널 |
| `EyeProxy/AppModel.swift` | `enableSSLProxying(forHosts:)`, 복원, 기기 연결 |
| `EyeProxy/SessionTab.swift` | 그룹 제목, 그룹 시트 요청, `initialFilter` |
| `EyeProxy/Views/Sidebar/HostGroupSheet.swift` (새로) | New Domain or App 시트 |
| `EyeProxy/Views/Sidebar/SidebarView.swift` | Groups 줄, 우클릭 메뉴, 기기 아이콘 |
| `EyeProxy/Views/Settings/SettingsView.swift` | SSL 가져오기·내보내기 버튼, Restore Tabs at Launch |
| `EyeProxy/Views/Devices/ConnectedDevicesSection.swift` | 새 종류 이름, id로 이름 바꾸기, MAC·"이전" 표시 |
| `EyeProxy/Views/Certificate/AndroidSection.swift` | Android 안내 개편 |
| `EyeProxy/AppModel+Certificate.swift` | `proxy_ca.crt` 저장, `adbSetProxy` |
| `EyeProxy/EyeProxyApp.swift`, `EyeProxy/Views/MainWindow.swift`, `EyeProxy/Views/MainWindowHost.swift` | ⇧⌘K 메뉴, 시트 띄우기, 복원 시작·앞 탭 |
| `README.md`, `docs/superpowers/plans/2026-11-13-prog-host-tabs-devices-ssl-handover.md` | 문서 |

---

### Task 1: 호스트 패턴 매처(`?`)와 호스트 목록 파일 (Core·Kit)

**Files:**
- Create:
  - `Packages/EyeProxyCore/Sources/EyeProxyCore/HostPattern.swift`
  - `Packages/EyeProxyKit/Sources/EyeProxyKit/HostList.swift`
  - `Packages/EyeProxyKit/Tests/EyeProxyKitTests/HostListTests.swift`
- Modify:
  - `Packages/EyeProxyCore/Sources/EyeProxyCore/SSLProxyingPolicy.swift`
  - `Packages/EyeProxyCore/Tests/EyeProxyCoreTests/SSLProxyingPolicyTests.swift`
  - `Packages/EyeProxyKit/Sources/EyeProxyKit/Import/ProxymanImporter.swift`(`sslHosts`의 `private` 제거)

**Interfaces:**

```swift
// Core
public struct HostPatternSet: Sendable {
    public init(_ patterns: [String])          // 대소문자 무시. 와일드카드 없는 패턴은 Set, 나머지는 정규식 하나로 미리 컴파일
    public var isEmpty: Bool { get }
    public func matches(_ host: String) -> Bool   // `*` = 임의 문자열(빈 문자열 포함), `?` = 정확히 한 글자
}
// SSLProxyingPolicy.shouldDecrypt: isEnabled && HostPatternSet(patterns).matches(host)

// Kit
public enum HostListError: Error, Equatable { case tooLarge, notText, invalidJSON }
public enum HostList {
    public static let maxFileSize = 1_048_576
    public struct Parsed: Equatable, Sendable { public var patterns: [String]; public var rejected: Int }
    public static func parse(_ data: Data) throws(HostListError) -> Parsed
    public static func normalize(_ line: String) -> String?     // 한 줄 → 패턴, 쓸 수 없으면 nil
    public static func serialize(_ patterns: [String]) -> Data   // 머리 주석 한 줄 + 패턴마다 한 줄, LF, 끝 줄바꿈
    public static func merge(_ new: [String], into existing: [String]) -> (merged: [String], added: [String])
}
```

- **`parse` 규칙(스펙 §4.5)**
  - 크기가 `maxFileSize`보다 크면 `tooLarge`. UTF-8이 아니면 `notText`. BOM은 뗀다.
  - 앞뒤 공백을 지운 첫 글자가 `{`이면 `ProxymanImporter.sslHosts(_:)`로 읽는다. nil이면 `invalidJSON`이다. 읽은 값도 `normalize`를 거친다.
  - 그 밖에는 줄 단위로 읽는다(`\r\n`, `\n`). 빈 줄과 `#`로 시작하는 줄은 건너뛴다. 나머지 줄은 `normalize`가 nil이면 `rejected += 1`이다.
  - 중복은 대소문자를 무시하고 처음 것만 남긴다.
- **`normalize`**
  - 공백을 지운다. `://`가 있으면 `URL(string:)?.host`를 쓰고, 없으면 그 줄을 쓴다.
  - 끝의 `:숫자`를 뗀다. 소문자로 바꾼다.
  - 비었거나 `[a-z0-9.\-_*?]` 밖의 글자가 있으면 nil이다.
- **`serialize` 머리 줄:** `# Prog host list — 한 줄에 호스트 패턴 하나. *는 임의 문자열, ?는 한 글자.`

- [ ] **Step 1: 실패하는 테스트를 쓴다.**

```swift
// SSLProxyingPolicyTests.swift (Core)
@Test func questionMarkMatchesOneCharacter() {
    let p = SSLProxyingPolicy(patterns: ["v?.example.net"])
    #expect(p.shouldDecrypt(host: "v1.example.net")); #expect(!p.shouldDecrypt(host: "v10.example.net")); #expect(!p.shouldDecrypt(host: "v.example.net"))
}
@Test func hostPatternSetExactAndWildcard() {
    let s = HostPatternSet(["API.example.com", "*.example.org"])
    #expect(s.matches("api.example.com")); #expect(!s.matches("x.api.example.com"))
    #expect(s.matches("a.example.org")); #expect(!s.matches("example.org"))
}
@Test func emptyPatternSetMatchesNothing() { #expect(HostPatternSet([]).isEmpty); #expect(!HostPatternSet([]).matches("a")) }

// HostListTests.swift (Kit)
@Test func parsesLinesCommentsAndBlank()        // "# c\r\napi.example.com\n\n  *.Example.org  \n" → ["api.example.com", "*.example.org"], rejected 0
@Test func parseTakesHostFromURLAndDropsPort()  // "https://api.example.com:8443/v1/x?y=1\ncdn.example.org:443" → ["api.example.com", "cdn.example.org"]
@Test func parseRejectsInvalidAndDedupes()      // "a b.example.com\napi.example.com\nAPI.example.com\nv?.example.net\nbad/host" → ["api.example.com", "v?.example.net"], rejected 2
@Test func parseAcceptsBOM()                    // "\u{FEFF}api.example.com" → ["api.example.com"]
@Test func parseReadsProxymanSSLJSON()          // {"nodes":[{"kind":{"domain":[{"url":"api.example.com"},{"url":"*.example.org"}]}}]} → 두 패턴
@Test func parseRejectsLargeFileAndBadJSON()    // Data(count: 1_048_577) → tooLarge; "{not json" → invalidJSON; Data([0xff, 0xfe, 0x00]) → notText
@Test func serializeRoundTrips()                // serialize(["api.example.com", "*.example.org"]): "# Prog host list"로 시작, "\n"으로 끝; parse 결과 같음
@Test func mergeIsCaseInsensitiveAndKeepsOrder() // merge(["B.example.com", "c.example.com"], into: ["a.example.com", "b.example.com"]) → merged ["a.example.com", "b.example.com", "c.example.com"], added ["c.example.com"]
```

  `merge`는 새 항목을 `normalize` 없이 그대로 비교한다. 대소문자만 무시한다. 넣을 때는 받은 문자열을 그대로 붙인다.

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path Packages/EyeProxyCore --filter SSLProxyingPolicy` 그리고 `swift test --package-path Packages/EyeProxyKit --filter HostListTests`

Expected: `HostPatternSet`, `HostList`가 없어 컴파일 실패.

- [ ] **Step 3: 구현.** Interfaces대로 구현한다. `SSLProxyingPolicy`의 `private static func matches`는 지우고 `HostPatternSet`을 쓴다. 기존 SSL 테스트는 모두 그대로 통과해야 한다.

- [ ] **Step 4: 통과 확인**

Run: Core, Kit 테스트 전체, 그리고 앱 빌드(Global Constraints).

Expected: 모두 PASS, `** BUILD SUCCEEDED **`.

- [ ] **Step 5: 커밋**

`feat(ssl): 호스트 패턴 ? 와일드카드와 호스트 목록 파일 형식`

---

### Task 2: 호스트 그룹 모델과 필터·사이드바 연결 (Kit)

**Files:**
- Create:
  - `Packages/EyeProxyKit/Sources/EyeProxyKit/HostGroup.swift`
  - `Packages/EyeProxyKit/Tests/EyeProxyKitTests/HostGroupTests.swift`
- Modify:
  - `FlowFilter.swift`
  - `SidebarTree.swift`
  - `AppSettings.swift`
  - 테스트 `FlowFilterTests.swift`, `SidebarTreeTests.swift`, `AppSettingsTests.swift`
  - 앱 빌드 유지: `EyeProxy/SessionTab.swift`(`title`의 `switch`)

**Interfaces:**

```swift
public struct HostGroup: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var hostPatterns: [String]
    public var apps: [String]                  // ProcessIdentity.groupKey
    public init(id: UUID = UUID(), name: String, hostPatterns: [String], apps: [String])
    public var isEmpty: Bool { get }           // 패턴·앱 모두 없음
    public var displayName: String { get }     // name(공백 제거)이 있으면 그것, 없으면 첫 항목(패턴 먼저, 그다음 앱) + 나머지가 n>0이면 " 외 n"
}
public struct HostGroupMatcher: Sendable {
    public init(_ group: HostGroup)            // HostPatternSet을 여기서 한 번 만든다
    public func matches(host: String, process: String?) -> Bool   // 패턴에 맞거나 process가 apps에 있음
}
// FlowScope: Codable 추가
// FlowFilter: public var group: HostGroup? = nil   — CodingKeys에 넣지 않는다(저장 안 함)
// PreparedFilter: init에서 groupMatcher를 만들고, matches에서 host 검사 다음에
//   if let groupMatcher, !groupMatcher.matches(host: flow.request.host, process: process) { return false }
// SidebarItem: Codable 추가, case group(HostGroup); apply → f.group = g
public struct GroupNode: Identifiable, Sendable { public let group: HostGroup; public let count: Int; public var id: UUID { group.id } }
// SidebarTree: public let groups: [GroupNode]
//   build(flows:attribution:devices:pinned:runtimes:groups: [HostGroup] = [])
//   - 개수: 그룹마다 매처를 한 번 만들고, 흐름마다 attribution[id]?.groupKey로 판정
//   filtered: 그룹 displayName이나 패턴 중 하나가 query를 포함하면 남긴다
// AppSettings: public var hostGroups: [HostGroup]   (키 "eyeproxy.hostGroups", JSON)
//   public func saveGroup(_ g: HostGroup)   — 같은 id가 있으면 그 자리에서 바꾸고, 없으면 뒤에 붙인다
//   public func deleteGroup(id: UUID)
```

- [ ] **Step 1: 실패하는 테스트를 쓴다.**

```swift
// HostGroupTests.swift
@Test func groupMatchesDomainPatternOrApp() {
    let m = HostGroupMatcher(HostGroup(name: "g", hostPatterns: ["*.example.com"], apps: ["com.example.app"]))
    #expect(m.matches(host: "api.example.com", process: nil))
    #expect(m.matches(host: "other.net", process: "com.example.app"))
    #expect(!m.matches(host: "other.net", process: nil))
    #expect(!m.matches(host: "example.com", process: nil))
}
@Test func groupDisplayNameFallsBack() {
    #expect(HostGroup(name: " ", hostPatterns: ["api.example.com", "*.example.org"], apps: []).displayName == "api.example.com 외 1")
    #expect(HostGroup(name: "우리 서버", hostPatterns: ["api.example.com"], apps: []).displayName == "우리 서버")
}
@Test func sidebarItemCodableRoundTrip() // [.allFlows, .host("api.example.com"), .scope(FlowScope(device: "192.0.2.10", host: "api.example.com")),
                                         //  .path(host: "api.example.com", prefix: "/v1"), .group(g)] → JSONEncoder → JSONDecoder → 같음
// FlowFilterTests.swift
@Test func sidebarGroupFiltersFlows()    // 호스트 api.example.com, cdn.example.org, other.net 흐름 3개;
                                         // .group(HostGroup(name: "", hostPatterns: ["*.example.com", "cdn.example.org"], apps: [])).apply(to: &f) → 맞는 흐름 2개
@Test func groupIsNotPersistedInFilter() // f.group = g → encode → decode → group == nil, rules 유지
// SidebarTreeTests.swift
@Test func treeCountsGroups()            // 위 흐름 3개 + groups [g] → tree.groups.first?.count == 2;
                                         // filtered("example.org").groups.count == 1; filtered("zzz").groups.isEmpty
// AppSettingsTests.swift
@Test @MainActor func hostGroupsPersistAndReplaceByID() // saveGroup(a); saveGroup(b); a.name = "새 이름"; saveGroup(a)
                                                         // → 새 AppSettings에서 [a(새 이름), b] 순서; deleteGroup(id: b.id) → [a]
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path Packages/EyeProxyKit --filter 'HostGroupTests|FlowFilterTests|SidebarTreeTests|AppSettingsTests'`

Expected: 컴파일 실패.

- [ ] **Step 3: 구현한다.**
  - **Kit:** Interfaces대로 구현한다. 기존 `SidebarTree(...)` 생성자 호출(`filtered` 포함)에 `groups`를 넘긴다.
  - **앱 빌드 유지:** `SessionTab.title`의 `switch`에 `case .group(let g)?: return g.displayName`를 넣는다. 앱의 다른 동작은 바꾸지 않는다.

- [ ] **Step 4: 통과 확인**

Run: Kit 테스트 전체, 앱 빌드.

Expected: PASS, BUILD SUCCEEDED.

- [ ] **Step 5: 커밋**

`feat(tabs): 호스트 그룹 모델과 필터·사이드바 연결`

---

### Task 3: 탭 저장본과 복원 순서 (Kit)

**Files:**
- Create:
  - `Packages/EyeProxyKit/Sources/EyeProxyKit/TabSnapshot.swift`
  - `Packages/EyeProxyKit/Tests/EyeProxyKitTests/TabSnapshotTests.swift`
- Modify:
  - `AppSettings.swift`
  - `AppSettingsTests.swift`

**Interfaces:**

```swift
public struct TabSnapshot: Codable, Equatable, Sendable {
    public var filePath: String?          // nil = 라이브
    public var selection: SidebarItem?
    public var filter: FlowFilter         // 규칙·AND/OR만 저장된다(FlowFilter의 Codable)
    public init(filePath: String?, selection: SidebarItem?, filter: FlowFilter)
}
public struct OpenTabs: Codable, Equatable, Sendable {
    public var tabs: [TabSnapshot]
    public var activeIndex: Int?
    public init(tabs: [TabSnapshot], activeIndex: Int?)
    public func restorePlan() -> RestorePlan
}
public struct RestorePlan: Equatable, Sendable {
    public enum Active: Equatable, Sendable { case main, rest(Int), none }
    public var main: TabSnapshot?         // 첫 라이브 탭(실행 탭에 넣는다). 없으면 nil
    public var rest: [TabSnapshot]        // 나머지, 저장 순서
    public var active: Active
}
// AppSettings
public var restoreTabsAtLaunch: Bool      // 키 "eyeproxy.restoreTabsAtLaunch", 기본 true
public var openTabs: OpenTabs?            // 키 "eyeproxy.openTabs", JSON. nil이면 키를 지운다. 읽기 실패면 nil
```

- [ ] **Step 1: 실패하는 테스트를 쓴다.**

```swift
@Test func restorePlanPutsFirstLiveTabFirst()
// tabs = [file "/tmp/a.eyeproxy", live L1(selection .host("api.example.com")), live L2, file "/tmp/b.har"], activeIndex 3
// → main == L1, rest == [a, L2, b], active == .rest(2)
@Test func restorePlanActiveCases()
// 같은 tabs: activeIndex 1 → .main; activeIndex nil → .none; activeIndex 9 → .none
// 파일 탭만 [a, b], activeIndex 0 → main nil, rest [a, b], active .rest(0); 빈 tabs → main nil, rest [], .none
@Test func snapshotRoundTripsGroupSelectionAndRules()
// selection .group(g), filter.rules = [FilterRule(key: .url, match: .contains, text: "v1")] → encode/decode 같음
// AppSettingsTests.swift
@Test @MainActor func openTabsPersistAndRestoreDefaultIsOn()
// 기본: restoreTabsAtLaunch == true, openTabs == nil; openTabs = OpenTabs(tabs: [L1], activeIndex: 0) → 새 AppSettings에서 같음; openTabs = nil → 새 AppSettings에서 nil
```

  테스트의 파일 경로는 `/tmp/...`만 쓴다.

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path Packages/EyeProxyKit --filter 'TabSnapshotTests|AppSettingsTests'`

Expected: 컴파일 실패.

- [ ] **Step 3: 구현.** Interfaces대로 구현한다.

- [ ] **Step 4: 통과 확인**

Run: Kit 테스트 전체, 앱 빌드.

Expected: PASS, BUILD SUCCEEDED.

- [ ] **Step 5: 커밋**

`feat(tabs): 탭 저장본과 복원 순서 모델`

---

### Task 4: Android 기기 종류와 `devices.json` 호환 (Kit)

**Files:**
- Modify:
  - `Devices/DeviceRegistry.swift`(`DeviceKind`, `Device` Codable)
  - `Devices/DeviceDiscovery.swift`(Cast)
  - 테스트 `DeviceDiscoveryTests.swift`, `DeviceRegistryTests.swift`
  - 앱: `EyeProxy/Views/Devices/ConnectedDevicesSection.swift`(`label`), `EyeProxy/Views/Sidebar/SidebarView.swift`(`icon`)

**Interfaces:**

```swift
public enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case thisMac, appleTV, iPhone, iPad, androidTV, googleTV, androidPhone, unknown   // 고르기 순서 = 이 순서
    public init(from decoder: any Decoder) throws    // 모르는 raw 값 → .unknown (throw하지 않음)
    public var legacy: DeviceKind { get }            // android 셋 → .unknown, 나머지 자기 자신
}
// Device: init(from:)/encode(to:) 직접 구현.
//   키: address, name, autoName, kind, extendedKind, lastSeen, flowCount, decryptedCount, tlsFailureCount (Task 5에서 mac 추가)
//   encode: kind = kind.legacy; kind != kind.legacy일 때만 extendedKind = kind
//   decode: extendedKind가 있고 읽히면 그것, 아니면 kind(모르는 값은 .unknown)
// DeviceDiscovery.parse: "_googlecast._tcp" → name = txt["fn"], kind = castKind(model: txt["md"])
public nonisolated static func castKind(model: String?) -> DeviceKind?
//   nil·빈 값 → nil; "Google Home"·"Google Nest"·"Nest" 접두 → nil;
//   "Google TV" 포함 또는 "Chromecast" 접두 → .googleTV; 그 밖 → .androidTV  (대소문자 무시)
```

- [ ] **Step 1: 실패하는 테스트를 쓴다(기존 테스트 하나는 고친다).**

```swift
// DeviceDiscoveryTests.swift
// 고침: parsesGoogleCastFriendlyName — md "Chromecast" → kind == .googleTV (이름은 "안방 TV" 그대로)
@Test func castModelMapsToAndroidKinds() {
    #expect(DeviceDiscovery.castKind(model: "Google TV Streamer") == .googleTV)
    #expect(DeviceDiscovery.castKind(model: "Chromecast") == .googleTV)
    #expect(DeviceDiscovery.castKind(model: "SHIELD Android TV") == .androidTV)
    #expect(DeviceDiscovery.castKind(model: "BRAVIA 4K VH2") == .androidTV)
    #expect(DeviceDiscovery.castKind(model: "Google Nest Mini") == nil)
    #expect(DeviceDiscovery.castKind(model: "Google Home") == nil)
    #expect(DeviceDiscovery.castKind(model: "Nest Hub") == nil)
    #expect(DeviceDiscovery.castKind(model: nil) == nil)
}
// DeviceRegistryTests.swift
@Test @MainActor func androidKindIsWrittenCompatibly()
// 192.0.2.30 요청 → rename(…, kind: .googleTV) → save → JSONSerialization으로 읽은 첫 객체: kind == "unknown", extendedKind == "googleTV"
// → 새 DeviceRegistry로 읽으면 kind == .googleTV
@Test @MainActor func legacyKindsHaveNoExtendedKey()   // .appleTV 기기 저장 → 객체에 "extendedKind" 키 없음, kind == "appleTV"
@Test @MainActor func unknownKindValueDoesNotCorruptFile()
// 임시 폴더에 [{"address":"192.0.2.31","kind":"smartFridge","lastSeen":"2026-11-13T00:00:00Z","flowCount":1,"decryptedCount":0,"tlsFailureCount":0}]
// → DeviceRegistry 읽기: devices.count == 1, kind == .unknown; 폴더에 "corrupt" 파일 없음
```

  `rename`은 이 태스크에서는 아직 주소를 받는 옛 시그니처다.

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path Packages/EyeProxyKit --filter 'DeviceDiscoveryTests|DeviceRegistryTests'`

Expected: 컴파일 실패, 또는 새 테스트 FAIL.

- [ ] **Step 3: 구현한다.** 앱 빌드를 유지하려고 다음도 같이 고친다.
  - **`ConnectedDevicesSection.label`:**
    - `.androidTV` → "Android TV"
    - `.googleTV` → "Google TV"
    - `.androidPhone` → `String(localized: "Android 폰")`
  - **`SidebarView.icon`:**
    - `.androidTV`, `.googleTV` → `"tv"`
    - `.androidPhone` → `"smartphone"`

- [ ] **Step 4: 통과 확인**

Run: Kit 테스트 전체, 앱 빌드.

Expected: PASS, BUILD SUCCEEDED.

- [ ] **Step 5: 커밋**

`feat(devices): Android TV·Google TV·Android 폰 종류와 Cast 모델로 종류 채우기`

---

### Task 5: ARP 표로 MAC 알아보기와 이 Mac 이름 (Kit)

**Files:**
- Create:
  - `Packages/EyeProxyKit/Sources/EyeProxyKit/Devices/ARPTable.swift`
  - `Packages/EyeProxyKit/Tests/EyeProxyKitTests/ARPTableTests.swift`
- Modify:
  - `Devices/DeviceRegistry.swift`
  - `DeviceRegistryTests.swift`
  - 앱 빌드 유지: `ConnectedDevicesSection.swift`(`ForEach`는 id, `rename(id:)`)

**Interfaces:**

```swift
public enum ARPTable {
    /// sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO)로 표를 읽어 그 IPv4의 MAC. 실패·없음이면 nil.
    public static func macAddress(for ipv4: String) -> String?
    /// 라우팅 메시지 버퍼 → [IPv4: MAC]. arp.c와 같은 방식: rt_msghdr 뒤에 sockaddr_in, 그다음(4바이트 올림) sockaddr_dl.
    static func parse(_ buffer: [UInt8]) -> [String: String]
    /// 6바이트가 아니거나 모두 0, 모두 0xff면 nil. 소문자 두 자리, ":" 구분.
    static func format(_ bytes: [UInt8]) -> String?
}
// Device
public var address: String                 // let → var (MAC으로 옮길 때 바뀜)
public var mac: String?                     // 새 키 "mac"(선택)
public var id: String { mac ?? address }
// DeviceRegistry
public init(storageURL: URL?, macLookup: @escaping @MainActor (String) -> String? = { _ in nil })
public static let macCheckInterval: TimeInterval = 60
public func device(at address: String) -> Device?          // 그 주소의 lastSeen이 가장 늦은 기록
public func isCurrent(_ device: Device) -> Bool            // device(at: device.address)?.id == device.id
public func rename(id: String, name: String?, kind: DeviceKind)   // 옛 rename(_ address:…)를 바꾼다
@discardableResult public func markThisMac(_ address: String, name: String?) -> Bool
//   그 주소의 현재 기록: kind가 .unknown이면 .thisMac, name이 비지 않았으면 autoName = name. 바뀌면 true. 루프백·기록 없음이면 false
```

- **MAC 맞추기(`update` 안, 루프백·빈 주소·`"unknown"` 제외)**
  - **읽는 조건:** 그 주소를 마지막으로 읽은 시각(이벤트 날짜 기준, 메모리에만 둔다)이 없거나 `macCheckInterval` 이상 지났을 때만 `macLookup(address)`를 부른다.
  - **결과가 MAC M이면** 스펙 §4.3.1 표대로 한다.
    1. 그 주소의 현재 기록이 MAC M이면 그대로 둔다.
    2. 다른 주소에 MAC M인 기록이 있으면, 그 기록의 `address`를 이 주소로 바꾸고 `lastSeen`을 이벤트 날짜로 한다.
    3. 그 주소의 현재 기록에 MAC이 없으면, 그 기록에 M을 적는다.
    4. 그 주소에 기록이 없거나, 현재 기록이 다른 MAC이면, 새 기록을 만든다(MAC M, 기억한 광고가 있으면 지금처럼 적용).
  - **그 뒤** 그 주소의 현재 기록(`lastSeen`이 가장 늦은 것)에 개수 변경을 적용하고, 지금처럼 정렬한다.
  - 어떤 경로에서도 기록을 지우지 않는다. `name`·`kind`·`autoName`을 다른 기록으로 복사하지 않는다(기록 자체가 옮겨 간다).
- **주소로 찾는 곳은 모두 "가장 최근 기록"을 쓴다.** `applyDiscovered`, `hasRemoteDevice`, `update`가 해당한다. `devices`는 `lastSeen` 내림차순이라 `firstIndex(where:)`면 된다. 정렬을 깨는 코드가 생기지 않게 주의한다.

- [ ] **Step 1: 실패하는 테스트를 쓴다.** MAC 예시는 `00:00:5e:00:53:xx`만 쓴다.

```swift
// ARPTableTests.swift
@Test func formatsMAC()            // [0x00,0x00,0x5e,0x00,0x53,0x01] → "00:00:5e:00:53:01"; 0 여섯 개 → nil; 0xff 여섯 개 → nil; 5바이트 → nil
@Test func parsesRouteMessage()    // 테스트 안에서 버퍼를 만든다: 메시지 1 = rt_msghdr(rtm_msglen = 전체 길이) + sockaddr_in(sin_len 16, AF_INET, 192.0.2.20)
                                   //   + sockaddr_dl(sdl_len 20, AF_LINK, sdl_nlen 0, sdl_alen 6, 00:00:5e:00:53:14);
                                   //   메시지 2 = 같은 모양, 192.0.2.21, sdl_alen 0(미완성)
                                   // → ["192.0.2.20": "00:00:5e:00:53:14"]
@Test func liveTableLookupIsSafe() // ARPTable.macAddress(for: "192.0.2.1")가 nil이거나 형식("xx:xx:xx:xx:xx:xx")에 맞다(크래시 없음)
// DeviceRegistryTests.swift — lookup은 테스트의 var 사전을 읽는 클로저. 날짜 t0 = Date(timeIntervalSince1970: 1_800_000_000)
@Test @MainActor func macFollowsDeviceToNewAddress()
// lookup[".20"] = M1; .20 요청(t0) → rename(id: M1, name: "거실 TV", kind: .googleTV)
// lookup = [".21": M1]; .21 요청(t0+120) → device(at: "192.0.2.21")?.displayName == "거실 TV", kind == .googleTV, flowCount == 2
// devices.count == 1, device(at: "192.0.2.20") == nil
@Test @MainActor func reassignedAddressKeepsOldNameAsPrevious()
// .20=M1 이름 "거실 TV"(t0) → lookup[".20"] = M2, .20 요청(t0+120) → device(at: .20)?.mac == M2, displayName == "192.0.2.20"
// devices.count == 2; M1 기록은 isCurrent == false, name == "거실 TV"
// → lookup[".22"] = M1, .22 요청(t0+240) → device(at: .22)?.displayName == "거실 TV", isCurrent == true
@Test @MainActor func oldRecordLearnsMAC()
// MAC 없는 JSON(.20, name "내 기기")으로 시작 → lookup[".20"] = M1, .20 요청 → mac == M1, name 유지
// → .21에서 M1 → 이름이 따라감
@Test @MainActor func macLookupIsRateLimited()
// 호출 횟수를 센다: .20 요청 t0, t0+10, t0+30 → 1회; t0+61 → 2회. 127.0.0.1 요청 → 늘지 않음
@Test @MainActor func markThisMacSetsKindAndAutoName()
// .5 요청 → markThisMac(".5", name: "테스트 Mac") == true → kind .thisMac, displayName "테스트 Mac"; 다시 부르면 false
// 이름 "내 Mac"을 직접 붙인 기기는 displayName "내 Mac" 유지; .iPad로 고른 기기는 .iPad 유지; markThisMac("127.0.0.1", …) == false
@Test @MainActor func macPersists()   // save → 다시 읽기: mac 유지; mac 키 없는 옛 JSON도 읽힘
```

  기존 테스트의 `rename(address, …)` 호출은 `rename(id:)`로 바꾼다(MAC이 없으면 id = 주소).

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path Packages/EyeProxyKit --filter 'ARPTableTests|DeviceRegistryTests'`

Expected: 컴파일 실패.

- [ ] **Step 3: 구현**
  - **ARP 표:** `import Darwin`. `rt_msghdr`, `sockaddr_dl`, `NET_RT_FLAGS`, `RTF_LLINFO`를 쓴다.
    - Swift에서 보이지 않는 이름이 있으면 오프셋을 상수로 둔다. 그때는 `MemoryLayout`과 macOS SDK 헤더 값으로 테스트에서 맞춘다.
    - 올림 규칙: `len > 0 ? 1 + ((len - 1) | 3) : 4`.
    - 크기를 먼저 묻고(`sysctl` 두 번) 버퍼를 할당한다. 실패하면 nil이다.
  - **앱 빌드 유지:** `ConnectedDevicesSection`을 고친다.
    - `ForEach(model.devices.devices)`는 `Identifiable` id로 그대로 둔다.
    - `update`는 `model.devices.rename(id: device.id, …)`를 부른다.

- [ ] **Step 4: 통과 확인**

Run: Kit 테스트 전체, 앱 빌드.

Expected: PASS, BUILD SUCCEEDED.

- [ ] **Step 5: 커밋**

`feat(devices): ARP 표의 MAC으로 기기 알아보기와 이 Mac 이름`

---

### Task 6: Android CA 번들 스니펫과 TV 명령 (Kit)

**Files:**
- Modify:
  - `Packages/EyeProxyKit/Sources/EyeProxyKit/Onboarding/AndroidSetup.swift`
  - `AndroidSetupTests.swift`
  - 앱 빌드 유지: `EyeProxy/Views/Certificate/AndroidSection.swift`(TV 명령 호출, 설치 인텐트 버튼 제거)

**Interfaces:**

```swift
public static let bundledCAPath = "app/src/debug/res/raw/proxy_ca.crt"
/// app/src/debug/res/xml/network_security_config.xml — base-config trust-anchors: system, user, @raw/proxy_ca.
/// 첫 줄 주석에 파일 위치, 둘째 줄 주석에 "앱에 이미 config가 있으면 debug-overrides의 trust-anchors에 @raw/proxy_ca만 더한다".
public static let bundledNetworkSecurityConfigXML: String
/// app/src/debug/AndroidManifest.xml — <manifest xmlns:android=… xmlns:tools=…><application android:networkSecurityConfig="@xml/network_security_config"
///   tools:replace="android:networkSecurityConfig" /></manifest>, 주석: main에 같은 속성이 없으면 tools:replace는 지워도 된다.
public static let debugManifestXML: String
public static func copyCACommand(caPEMPath: String) -> String
//   "mkdir -p app/src/debug/res/raw && cp \"<caPEMPath>\" app/src/debug/res/raw/proxy_ca.crt"
public static let fingerprintCommand = "openssl x509 -in app/src/debug/res/raw/proxy_ca.crt -noout -fingerprint -sha256"
public static let trustAnchorLogcatCommand = "adb logcat | grep -i \"trust anchor\""
public static func clearProxyCommand(adb: String) -> String   // "<adb> shell settings put global http_proxy :0"
// connectArguments: 입력에 ":"가 있으면 그대로, 없으면 ":5555"를 붙인다
// tvCommandLines(adb:tvIP:host:port:) — 두 줄: connect, 프록시 설정 (crt 인자 삭제)
// installIntentArguments 삭제
```

  기존 `networkSecurityConfigXML`(user CA 허용)은 에뮬레이터·실기기 설명에서 계속 쓰므로 그대로 둔다.

- [ ] **Step 1: 테스트를 쓴다(기존 두 개는 고친다).** 지금 테스트에 있는 사설 주소(192.168 대역) 값을 모두 `192.0.2.x`로 바꾼다.

```swift
// 고침: proxyAndPushArgumentsAreExact — installIntentArguments 줄을 지운다
// 바꿈: tvCommandLinesContainConnectAndIntent → tvCommandLinesAreConnectAndProxyOnly
@Test func tvCommandLinesAreConnectAndProxyOnly() {
    let lines = AndroidSetup.tvCommandLines(adb: "adb", tvIP: "192.0.2.20", host: "192.0.2.5", port: 9090).split(separator: "\n").map(String.init)
    #expect(lines == ["adb connect 192.0.2.20:5555", "adb shell settings put global http_proxy 192.0.2.5:9090"])
}
@Test func connectKeepsExplicitPort() { #expect(AndroidSetup.connectArguments("192.0.2.20:37199") == ["connect", "192.0.2.20:37199"]) }
@Test func clearProxyCommandIsExact() { #expect(AndroidSetup.clearProxyCommand(adb: "adb") == "adb shell settings put global http_proxy :0") }
@Test func bundledConfigTrustsRawCA()   // XML에 `<certificates src="@raw/proxy_ca"`, `src="system"`, `src="user"`, "app/src/debug/res/xml/network_security_config.xml"가 있다
@Test func debugManifestPointsToConfig() // `android:networkSecurityConfig="@xml/network_security_config"`, `tools:replace="android:networkSecurityConfig"`가 있다
@Test func copyCACommandQuotesPath() {
    #expect(AndroidSetup.copyCACommand(caPEMPath: "/tmp/Prog CA/ca.pem")
            == "mkdir -p app/src/debug/res/raw && cp \"/tmp/Prog CA/ca.pem\" app/src/debug/res/raw/proxy_ca.crt")
}
@Test func fingerprintCommandReadsBundledFile() { #expect(AndroidSetup.fingerprintCommand.contains(AndroidSetup.bundledCAPath)) }
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path Packages/EyeProxyKit --filter AndroidSetupTests`

Expected: 컴파일 실패.

- [ ] **Step 3: 구현한다.** 앱 빌드를 유지하려고 `AndroidSection`도 최소로 고친다.
  - TV 탭의 `adbSetProxyAndPushCA(host: macIP)` 버튼은 그대로 둔다(Task 11에서 바꾼다).
  - "인증서 설치 화면 열기" 버튼을 지운다.
  - `tvCommandLines` 호출에서 `crt:`를 뺀다.

- [ ] **Step 4: 통과 확인**

Run: Kit 테스트 전체, 앱 빌드.

Expected: PASS, BUILD SUCCEEDED.

- [ ] **Step 5: 커밋**

`feat(android): 디버그 빌드 CA 번들 스니펫과 TV adb 명령 정리`

---

### Task 7: SSL Proxying 호스트 목록 가져오기·내보내기와 한 번에 켜기 (앱)

**Files:**
- Create: `EyeProxy/AppModel+HostList.swift`
- Modify:
  - `EyeProxy/AppModel.swift`
  - `EyeProxy/Views/Settings/SettingsView.swift`(SSLSettings)
  - `EyeProxy/Views/Sidebar/SidebarView.swift`

**Interfaces:**
- **`AppModel.enableSSLProxying(forHosts hosts: [String]) async`**
  - `HostList.merge`로 `settings.sslPatterns`에 더하고, `sslEnabled = true`, `applySettingsToServer()`를 한다.
  - 지금의 `enableSSLProxying(for:)`와 `enableSSLProxying(forHostsOfApp:in:)`도 이것을 부르게 바꾼다. 동작은 같아야 한다.
- **`AppModel.importSSLList() async`**
  - `NSOpenPanel`(`.plainText`, `.json`, 확장자 `config`)로 파일을 고르고 `HostList.parse`로 읽는다.
  - 빈 결과거나 오류면 `systemError`를 쓴다.
    - "목록에 쓸 호스트가 없습니다"
    - "파일이 너무 큽니다(1 MB 초과)"
    - "텍스트 파일이 아닙니다"
    - "Proxyman 목록을 읽지 못했습니다"
  - 그다음 `NSAlert`를 띄운다.
    - 메시지: "호스트 패턴 \(n)개(새로 \(m)개)를 SSL Proxying List에 더할까요?"
    - 설명: 버린 줄 수(있으면). `*`가 있으면 "`*`가 있어 모든 HTTPS를 복호화합니다."
    - 액세서리 체크박스: "호스트 그룹으로도 저장"(기본 켬)
    - 버튼: "추가", "취소"
  - 확인하면 다음을 한다.
    - `enableSSLProxying(forHosts:)`
    - 체크되어 있으면 `settings.saveGroup(HostGroup(name: 파일 이름(확장자 제외), hostPatterns: patterns, apps: []))`
    - `infoMessage = "SSL Proxying List에 \(m)개를 더했습니다."`
- **`AppModel.exportHostList(_ patterns: [String], suggestedName: String)`**
  - `NSSavePanel`로 `<suggestedName>.txt`를 받고 `HostList.serialize`를 쓴다. 실패하면 `systemError`다.
  - `settings.autoOpenExportDirectory`가 켜져 있으면 Finder에서 보인다(지금 Export와 같다).

- [ ] **Step 1: 모델을 구현한다.** Interfaces대로.

- [ ] **Step 2: SSL 설정 화면을 고친다.** 목록 아래에 버튼 두 개를 둔다.
  - "가져오기…" → `Task { await model.importSSLList() }`, help: "호스트 목록 파일(.txt) 또는 Proxyman SSL 목록에서 가져오기"
  - "내보내기…" → `model.exportHostList(settings.sslPatterns, suggestedName: "ssl-proxying-list")`, 목록이 비면 비활성, help: "지금 목록을 호스트 목록 파일로 저장"
  - Section footer: "한 줄에 패턴 하나. 팀 공용 목록은 파일로 주고받아 가져오세요."

- [ ] **Step 3: 사이드바 우클릭을 고친다.** Remote devices 기기 줄과 Apps의 앱 줄 우클릭에서 `Open as New Tab` 아래에 넣는다.
  - `Enable SSL Proxying for All Domains` → `model.enableSSLProxying(forHosts: node.hosts.map(\.host))`
  - help: "이 기기(앱)가 이 탭에서 쓴 모든 도메인을 SSL Proxying List에 넣기"

- [ ] **Step 4: 빌드하고 소스를 확인한다.**

Run: 앱 빌드, `grep -rn "enableSSLProxying" EyeProxy`

Expected:
- BUILD SUCCEEDED.
- `sslPatterns.append`나 `sslPatterns =`를 직접 쓰는 곳은 `enableSSLProxying(forHosts:)` 안과 설정 화면의 `StringListEditor`뿐이다. `ProxymanImporter`는 Kit이라 제외한다.

- [ ] **Step 5: 커밋**

`feat(ssl): 호스트 목록 가져오기·내보내기와 기기·앱 도메인 한 번에 켜기`

---

### Task 8: 호스트 그룹 탭 — New Domain or App ⇧⌘K, Favorites ▸ Groups (앱)

**Files:**
- Create: `EyeProxy/Views/Sidebar/HostGroupSheet.swift`
- Modify:
  - `EyeProxy/SessionTab.swift`
  - `EyeProxy/EyeProxyApp.swift`
  - `EyeProxy/Views/MainWindow.swift`
  - `EyeProxy/Views/Sidebar/SidebarView.swift`
  - `EyeProxy/AppModel.swift`

**Interfaces:**
- **`SessionTab.groupSheet: GroupSheetRequest?`** 메인 창이 `.sheet(item:)`으로 띄운다.
  - `struct GroupSheetRequest: Identifiable { let id = UUID(); var draft: HostGroup; let isEditing: Bool }`
- **`SessionTab.newGroupDraft() -> HostGroup`** 지금 사이드바 선택으로 미리 채운다.
  - `.host(h)`, `.path(h, _)`, `.scope(s)`이고 `s.host`가 있으면 → 패턴 `[h]`
  - `.scope(s)`이고 `s.process`가 있으면(호스트 없음) → 앱 `[s.process]`
  - `.group(g)` → 새 id로 g를 복사
  - 그 밖 → 빈 그룹
- **`SessionTab.computeSidebar`**는 `groups: model.settings.hostGroups`를 넘긴다(관찰이 걸려 그룹이 바뀌면 다시 만든다).
- **`AppModel.replaceGroupSelection(_ g: HostGroup)`** 모든 탭에서 `sidebarSelection`이 같은 id의 `.group`이면 새 값으로 바꾼다(편집 저장 뒤).

- [ ] **Step 1: `HostGroupSheet`를 만든다.**
  - **입력**
    - 이름 칸: 안내 글자는 `draft.displayName`.
    - 도메인 패턴 `TextEditor`: 줄이나 쉼표로 나누고 `HostList.normalize`를 거친다. 버린 항목이 있으면 개수를 빨간 글자로 보인다.
    - "가져오기…": `HostList.parse` 결과를 기존 패턴에 `merge`한다.
  - **고르기 목록**
    - 검색칸 하나와 두 목록을 둔다. 이 탭 `sidebarTree.domains`의 호스트, 이 탭 `sidebarTree.apps`(displayName, 아이콘)다.
    - 체크하면 패턴이나 앱에 넣고, 풀면 뺀다.
  - **저장 옵션:** "Favorites에 저장" Toggle은 새로 만들 때만 보이고 기본 켬이다. 편집할 때는 늘 저장한다.
  - **버튼**
    - Cancel(Esc)
    - 새로 만들 때 Open(⏎). 저장 옵션이 켜져 있으면 `settings.saveGroup`을 하고, `openWindow(id: "main", value: model.newTabID(sharing: tab, selecting: .group(g)))`를 연다.
    - 편집할 때 Save(⏎): `settings.saveGroup(g)`, `model.replaceGroupSelection(g)`.
    - `g.isEmpty`면 Open과 Save는 비활성이다.

- [ ] **Step 2: 메뉴와 시트를 붙인다.**
  - **File 메뉴:** `CommandGroup(replacing: .newItem)`의 New Session 아래에 넣는다.
    - `Button("New Domain or App…") { tab.groupSheet = .init(draft: tab.newGroupDraft(), isEditing: false) }`
    - `.keyboardShortcut("k", modifiers: [.command, .shift])`
    - `.disabled(model.activeTab == nil)`
    - help: "도메인·앱 묶음을 고른 새 탭 (⇧⌘K)"
  - **`MainWindow`:** `.sheet(item: $tab.groupSheet) { HostGroupSheet(request: $0) }`

- [ ] **Step 3: 사이드바 Groups를 만든다.**
  - **위치:** Favorites 섹션 안, Pinned 아래에 `DisclosureGroup(isExpanded: expansion("groups"))`, 라벨 `Label("Groups", systemImage: "square.stack")`.
  - **줄:** `Label(node.group.displayName, systemImage: "folder")`, `.badge(node.count)`, `.tag(SidebarItem.group(node.group))`.
  - **빈 경우:** 그룹이 없고 거르기 글자가 비었으면 회색 "⇧⌘K로 그룹 만들기".
  - **우클릭 메뉴:**
    - `Open as New Tab`
    - `Divider`
    - `Edit…` → `tab.groupSheet = .init(draft: g, isEditing: true)`
    - `Enable SSL Proxying` → `model.enableSSLProxying(forHosts: g.hostPatterns)`(패턴이 없으면 비활성)
    - `Export…` → `model.exportHostList(g.hostPatterns, suggestedName: g.displayName)`(패턴이 없으면 비활성)
    - `Delete` → `settings.deleteGroup(id:)`
  - 각 항목에 `.help`를 단다.

- [ ] **Step 4: 빌드한다.**

Run: 앱 빌드.

Expected: BUILD SUCCEEDED. ⇧⌘K는 앱 전체에서 하나만 쓰여야 한다. `grep -rn 'keyboardShortcut("k", modifiers: \[.command, .shift\])' EyeProxy`가 한 줄이다.

- [ ] **Step 5: 커밋**

`feat(tabs): 호스트 그룹 탭(New Domain or App ⇧⌘K, Favorites ▸ Groups)`

---

### Task 9: 탭 복원 (앱)

**Files:**
- Modify:
  - `EyeProxy/SessionTab.swift`
  - `EyeProxy/AppModel.swift`
  - `EyeProxy/EyeProxyApp.swift`(AppDelegate)
  - `EyeProxy/Views/MainWindowHost.swift`
  - `EyeProxy/Views/Settings/SettingsView.swift`(General)

**Interfaces:**
- **`SessionTab.init(..., restoreSavedRules: Bool, initialFilter: FlowFilter? = nil)`**
  - `initialFilter`가 있으면 저장된 규칙이나 빈 필터 대신 그것으로 시작한다. 이 경로에서도 `didSet`을 거치지 않는다.
  - `persistsRules`는 지금처럼 `restoreSavedRules`다.
- **`AppModel`**
  - `@ObservationIgnored private let restorePlan: RestorePlan?`: init에서 `settings.restoreTabsAtLaunch ? settings.openTabs?.restorePlan() : nil`.
  - `mainTab`(lazy)은 `restorePlan?.main`이 있으면 `initialFilter = main.filter`로 만들고 `sidebarSelection = main.selection`을 넣는다.
  - `func restoreTabs() async`: 한 번만 돈다.
    - `restorePlan.rest`를 순서대로 처리한다.
      - 라이브: `makeTab(fileURL: nil, …, restoreSavedRules: false, initialFilter: s.filter)`, `sidebarSelection = s.selection`.
      - 파일: `await open(URL(fileURLWithPath: path), quiet: true)`. 성공하면 그 탭에 같은 필터와 선택을 넣는다.
    - 만든 id를 차례로 `pendingOpenTabIDs`에 붙인다. `MainWindow`가 지금처럼 창을 연다.
    - `active`가 `.rest(i)`이고 그 탭이 만들어졌으면 `pendingKeyTabID = id`다. `.main`이면 `mainTab.window?.makeKeyAndOrderFront(nil)`이다.
  - `func open(_ url: URL, quiet: Bool = false) async -> UUID?`: `quiet`면 실패해도 `systemError`, `refreshRecent`를 하지 않고, 성공해도 `noteRecent`를 하지 않는다.
  - `var pendingKeyTabID: UUID?`(`@ObservationIgnored`): `MainWindowHost`가 attach할 때 같은 탭이면 `window.makeKeyAndOrderFront(nil)`을 하고 비운다.
  - `func snapshotTabs() -> OpenTabs`
    - 순서: `activeTab?.window`(없으면 아무 탭의 창)의 `tabbedWindows ?? [window]` 순서로 탭을 찾는다. 나머지 탭은 `NSApp.orderedWindows` 순서로 뒤에 붙인다. 창이 없는 탭은 뺀다.
    - `activeIndex`는 `activeTab`의 자리다.
- **`AppDelegate`**
  - `applicationDidFinishLaunching`의 서버 시작 `Task` 뒤에 `Task { await model.restoreTabs() }`를 둔다.
  - `applicationShouldTerminate`: 종료 확인 알림을 통과하고 `quitTask == nil`인 첫 진입에서, `model.breakpoints.releaseAll()` 바로 앞에 `model.settings.openTabs = model.settings.restoreTabsAtLaunch ? model.snapshotTabs() : nil`을 한다.
- **설정:** General 첫 Section에 `Toggle("Restore Tabs at Launch", isOn: $settings.restoreTabsAtLaunch)`, help: "다시 실행할 때 종료 전에 열려 있던 탭 다시 열기".

- [ ] **Step 1: 구현한다.** Interfaces대로.

- [ ] **Step 2: 빌드한다.**

Run: 앱 빌드.

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: 코드를 다시 읽고 확인한다.** 결과를 ledger에 적는다.
  - `settings.filterRules`에 쓰는 곳은 `persistsRules`인 탭(`mainTab`)뿐이다.
  - 복원 경로에서 `systemError`, `noteRecent`, `refreshRecent`를 부르지 않는다.
  - `restoreTabs`는 두 번 불러도 한 번만 돈다.
  - 종료 확인에서 취소하면 `openTabs`가 바뀌지 않는다.

- [ ] **Step 4: 커밋**

`feat(tabs): 종료할 때 열린 탭을 다음 실행에 복원`

---

### Task 10: 기기 연결 — ARP 조회, 이 Mac 이름, 연결된 기기 표시 (앱)

**Files:**
- Modify:
  - `EyeProxy/AppModel.swift`
  - `EyeProxy/Views/Devices/ConnectedDevicesSection.swift`

**Interfaces:**
- **`AppModel.init`:** `DeviceRegistry(storageURL: …, macLookup: { ARPTable.macAddress(for: $0) })`
- **`AppModel.handle`:** `devices.observe(event)` 바로 뒤에 다음을 한다.
  - `.requestStarted(flow)`이고 주소가 루프백이 아니며, 이번 실행에서 처음 보는 주소(`@ObservationIgnored var checkedOwnAddresses: Set<String>`)이면 집합에 넣는다.
  - 그 주소가 `lanAddresses`에 있으면 `devices.markThisMac(addr, name: Self.computerName)`을 하고, true면 `try? devices.save()`를 한다.
  - `static var computerName: String? { SCDynamicStoreCopyComputerName(nil, nil) as String? }`(`import SystemConfiguration`)
  - `startDiscoveryIfRemoteDeviceSeen()`과 그 조건은 바꾸지 않는다.
- **`ConnectedDevicesSection` 행**
  - 주소 줄: `address` + (MAC이 있으면) ` · <mac>`
  - `!model.devices.isCurrent(device)`이면 주소 줄 뒤에 회색 "이전" 표시
  - help: "이 주소는 지금 다른 기기가 쓰고 있습니다 — 같은 MAC이 다시 보이면 이름이 따라갑니다"

- [ ] **Step 1: 구현한다.**

- [ ] **Step 2: 빌드하고 소스를 확인한다.**

Run: 앱 빌드, 그리고 `git diff main -- EyeProxy/AppModel.swift | grep -n "startDiscoveryIfRemoteDeviceSeen\|DeviceDiscovery"`

Expected: BUILD SUCCEEDED. 찾기 시작 조건에 바뀐 줄이 없다(Review Focus 6).

- [ ] **Step 3: 커밋**

`feat(devices): MAC 조회·이 Mac 이름 연결과 연결된 기기 MAC 표시`

---

### Task 11: Android 인증서 안내 개편 (앱)

**Files:**
- Modify:
  - `EyeProxy/Views/Certificate/AndroidSection.swift`
  - `EyeProxy/AppModel+Certificate.swift`

**Interfaces:**
- **`CertificateExportFormat.androidRaw`:** 기본 이름 `proxy_ca.crt`, PEM으로 쓴다. `AppModel.exportAndroidRawCA()`가 이것을 쓴다.
- **`AppModel.adbSetProxy(host: String) async -> String`:** 프록시만 설정한다. `adbSetProxyAndPushCA`는 에뮬레이터 탭에서만 쓴다.

- [ ] **Step 1: TV 탭을 고친다(스펙 §4.4).**
  - 탭 이름은 "Android TV·Google TV"다.
  - **단계 문구 다섯 개**
    1. connect: 네트워크 디버깅은 `:5555`, 무선 디버깅은 화면의 포트.
    2. "CA는 TV에 설치하지 않습니다 — Android 11+는 설정 화면에서만 설치되고 Google TV에는 그 화면도 파일 선택기도 없습니다. 아래 '디버그 빌드에 CA 넣기'를 따르세요."
    3. 프록시 설정.
    4. 디버그 빌드 실행 후 확인.
    5. 끝나면 해제.
  - **입력과 버튼**
    - TV IP 칸: prompt `192.0.2.10`, 입력은 `IP` 또는 `IP:포트`.
    - adb가 있으면 버튼 셋: `adb connect`, `adb로 프록시 설정`(`adbSetProxy(host: macIP)`), `adb로 프록시 해제`.
    - adb가 없으면 `tvCommandLines` 두 줄과 `clearProxyCommand` 한 줄을 복사칸으로 보인다.
  - **해제 경고:** 해제 버튼 바로 아래 주황 글자로 "프록시를 켜 둔 채 Prog를 끄면 TV의 네트워크가 끊기고, 켜 둔 동안 다른 앱의 HTTPS가 실패할 수 있습니다. 끝나면 꼭 해제하세요."

- [ ] **Step 2: 실기기·에뮬레이터 탭에 한 줄씩 더한다.**
  - 실기기 탭: Android 11+는 파일을 눌러서는 설치되지 않는다는 줄.
  - 에뮬레이터 탭: "아래 디버그 빌드 방법도 됩니다."

- [ ] **Step 3: `caveatSection`을 "디버그 빌드에 CA 넣기" Section으로 바꾼다.** 모든 탭에서 보인다.
  - **원리 문장 세 개(스펙 §4.4):** Android 7+ 사용자 CA, 스토어 빌드 불가, `INSTALL_FAILED_UPDATE_INCOMPATIBLE`와 로그인 데이터.
  - **지문:** `LabeledContent("Prog CA SHA-256")`에 `model.certificateAuthority.sha256Fingerprint`(복사 버튼).
  - **CA 복사**
    - "CA를 proxy_ca.crt로 저장…" 버튼.
    - `AndroidSetup.copyCACommand(caPEMPath: AppModel.caDirectory.appending(path: "ca.pem").path)` 명령칸(복사 버튼).
  - **XML 두 개:** `bundledNetworkSecurityConfigXML`, `debugManifestXML`(각각 복사 버튼).
  - **확인:** `fingerprintCommand` 명령칸과 "출력의 지문이 위 SHA-256과 같아야 합니다."
  - **주의 두 줄:** CA를 커밋하지 말 것(`.git/info/exclude`). Reset하면 다시 복사·빌드할 것.
  - **진단:** "logcat에 `Trust anchor for certification path not found`가 보이면 앱이 Prog CA를 믿지 않는 것입니다(스플래시에서 멈출 수 있음)." 그리고 `trustAnchorLogcatCommand` 명령칸.
  - **명령칸 모양:** 지금 `commandText`처럼 고정폭, 선택 가능, 복사 버튼을 단다. 같은 모양이 반복되므로 작은 `snippet(_ text:)` 뷰 하나로 묶는다.

- [ ] **Step 4: 빌드하고 문자열을 확인한다.**

Run: 앱 빌드, 그리고 `grep -niE '/Use[r]s/|192[.]168[.]|tving' EyeProxy/Views/Certificate/AndroidSection.swift Packages/EyeProxyKit/Sources/EyeProxyKit/Onboarding/AndroidSetup.swift`

Expected: BUILD SUCCEEDED, grep 결과 없음.

- [ ] **Step 5: 커밋**

`feat(android): TV·Google TV는 디버그 빌드에 CA 넣기로 안내`

---

### Task 12: 문서

**Files:**
- Modify: `README.md`
- Create: `docs/superpowers/plans/2026-11-13-prog-host-tabs-devices-ssl-handover.md`

- [ ] **Step 1: README를 고친다.**
  - **"세션 탭" 절에 더한다.**
    - New Domain or App ⇧⌘K와 그룹 문법(OR, 와일드카드)
    - Favorites ▸ Groups 우클릭 메뉴
    - 탭 복원(General ▸ Restore Tabs at Launch, 무엇을 저장하는지, 사라진 파일은 건너뜀)
  - **"호스트 목록 파일(SSL Proxying 묶음)" 절을 새로 쓴다.**
    - 형식 예시: `example.com` 계열만 쓴다.
    - 해석 규칙, 가져오기·내보내기 위치, Proxyman JSON 읽기, "호스트 그룹으로도 저장"
    - 팀 공용 목록은 레포 밖에서 주고받는다는 것
    - 기기·앱 우클릭 Enable SSL Proxying for All Domains
  - **"원격 기기 이름 자동 찾기" 절을 고친다.**
    - `_googlecast._tcp` 행의 종류를 "TXT `md` → Google TV·Android TV"로 바꾼다.
    - MAC으로 알아보기: 같은 네트워크만 되고, 프라이빗 주소가 주기적으로 바뀌면 새 기기로 보인다. "이전" 표시.
    - 이 Mac LAN IP의 컴퓨터 이름.
    - Android 폰은 직접 고른다.
  - **Certificate 메뉴의 Android 섹션 설명을 새 내용으로 바꾼다.**
    - TV·Google TV: CA 설치 대신 디버그 빌드 번들
    - XML, 복사, 지문, 프록시 해제 경고, Trust anchor 진단
  - **단축키 표에 ⇧⌘K를 더한다.**
  - **알려진 제한(세션 탭·기기 이름)을 고친다.**
    - 지운다: "탭은 다시 실행할 때 복원되지 않는다", "공유기가 IP를 바꾸면 다시 붙여야 한다".
    - 더한다:
      - 복원은 한 창으로 모인다.
      - 다른 서브넷·주기적 임의 MAC 기기는 IP로 알아본다.
      - 옛 버전 Prog가 `devices.json`을 다시 저장하면 MAC과 Android 종류가 빠진다.
      - 그룹에 원격 기기를 넣을 수 없다(필터 막대 Client 규칙을 쓴다).
      - SSL 목록은 더하기만 되고 파일 단위로 빼기는 없다.

- [ ] **Step 2: 핸드오버를 쓴다.** 이전 핸드오버(`2026-11-12-prog-session-tabs-handover.md`) 형식을 따른다.
  - 무엇이 들어갔나(태스크·커밋 표)
  - 알아 둘 결정: 이 계획 맨 위 "내가 정한 것"
  - 구현 중 달라진 점
  - **사용자 점검표**(에이전트는 Debug 앱을 실행하지 않았으므로 앱 동작은 모두 여기서 본다)
    - **그룹:**
      - ⇧⌘K → 도메인 두 개와 앱 하나로 그룹을 만든다. 새 탭 제목이 그룹 이름이고 맞는 요청만 보인다.
      - Favorites ▸ Groups 배지 수가 맞는다.
      - Edit하면 열린 탭에 반영된다. Delete해도 열린 탭은 유지된다.
    - **SSL 목록:**
      - 레포 밖의 팀 목록 파일을 가져온다. 확인 알림의 개수와 `*` 경고가 맞고, 그룹으로도 생긴다.
      - 내보낸 파일을 다시 가져오면 "새로 0개"다.
    - **기기·앱 한 번에 켜기:** 기기 우클릭 Enable SSL Proxying for All Domains 뒤 그 기기의 HTTPS가 복호화된다.
    - **탭 복원:**
      - 라이브 탭 3개(전체·기기·그룹)와 파일 탭 1개를 열고 ⌘Q → 다시 실행하면 같은 순서이고, 앞 탭과 필터 규칙이 복원된다.
      - 파일을 지운 뒤 실행하면 그 탭만 빠지고 알림이 없다.
      - Restore Tabs at Launch를 끄면 라이브 탭 하나로 시작한다.
      - 종료 확인 알림에서 취소한 뒤에는 저장본이 바뀌지 않는다.
    - **MAC:**
      - TV에 이름을 붙인 뒤 공유기에서 IP를 바꾸거나 DHCP 임대를 갱신한다. 새 IP에서도 이름이 보이고, 연결된 기기에 MAC이 보인다.
      - 다른 기기가 옛 IP를 받으면 옛 기록에 "이전"이 붙는다.
    - **이 Mac:** 다른 기기 설정에 Mac LAN IP를 프록시로 넣고 Mac 브라우저도 LAN IP 프록시로 보내 본다. Remote devices에 컴퓨터 이름과 노트북 아이콘이 보인다.
    - **Android 종류:** Google TV가 처음 트래픽을 보낼 때 종류가 Google TV로 채워진다(로컬 네트워크 허용 상태).
    - **호환:** Debug 앱에서 Google TV 종류를 저장한 뒤 릴리스 Prog를 실행한다. 기기 목록이 그대로이고(종류만 알 수 없음) `devices.corrupt-*.json`이 생기지 않는다.
    - **Android 안내:**
      - 디버그 빌드에 `proxy_ca.crt`를 넣고 `openssl` 지문이 창의 SHA-256과 같다.
      - TV 앱 요청이 Prog에 보인다.
      - 프록시 해제 버튼 뒤 `settings get global http_proxy`가 `:0`이다.
  - 다음 묶음 후보
    - SSL Exclude List와 항목별 켜기
    - 파일 단위 빼기
    - 그룹에 기기 넣기
    - New Folder
  - 머지 메모
    - 새 패키지 없음
    - 새 UserDefaults 키 셋
    - `devices.json` 새 키 `mac`, `extendedKind`
    - Info.plist 변경 없음

- [ ] **Step 3: 커밋 전에 문자열을 확인한다.**

Run: `git diff --cached | grep -nE '/Use[r]s/|192[.]168[.]|tving[.]com'`

Expected: 결과 없음.

- [ ] **Step 4: 커밋**

`docs: 호스트 그룹 탭·탭 복원·기기 이름·Android 안내·SSL 묶음 README와 핸드오버`
