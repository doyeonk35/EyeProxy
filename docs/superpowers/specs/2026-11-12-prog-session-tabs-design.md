# Prog 세션 탭·Open Recent·기기 이름 설계

> 사용자 지시: "Proxyman 동작을 참고해 최대한 동일하게." 질문 단계는 생략했다. 아래에서 **(내 판단)** 표시는 Proxyman 자료로 확인하지 못해 내가 정한 부분이다.

## 1. 왜

Proxyman에서는 한 창에서 탭을 여러 개 열어 앱·도메인별로 나눠 보고, 저장해 둔 세션이나 HAR을 새 탭으로 열어 라이브 캡처와 나란히 본다. Prog는 지금 창이 하나뿐이다. 파일을 열면 라이브 세션이 통째로 교체되어, 라이브 캡처와 저장본을 나란히 볼 수 없다. 이번 묶음에서는 보기 상태를 `AppModel`에서 탭으로 옮긴다. 이 작업은 이전 스펙(2026-11-09 §12)에서 미뤄 둔 것이다.

같은 묶음에 **원격 기기 이름 자동 찾기**를 넣는다(사용자 요청). 지금은 설정에서 이름을 직접 붙이지 않으면 사이드바 Remote devices, Client 열, Export에 IP만 보여서, 여러 Apple TV·Google TV를 붙여 쓰면 어느 기기인지 알기 어렵다. 사용자가 따로 확인해 보니, 같은 네트워크의 Apple TV는 AirPlay 광고로, Chromecast with Google TV는 Cast 광고로 이름을 알 수 있었다. 이름을 알리지 않는 기기도 있었다.

## 2. 근거: Proxyman에서 확인한 것

**설치된 Proxyman 6.3.0의 메뉴.** 접근성 API로 읽기만 했고, 클릭은 하지 않았다.

- **File:**
  - New Session ⌘T
  - New Folder
  - New Domain or App ⇧⌘K
  - Open… ⌘O
  - Open Recent ▸ (Clear Menu)
  - Convert ▸ From .chls to .har
  - Save Session… (단축키 없음)
  - Close ⌘W
  - Close All ⌥⌘W
- **View:**
  - Show Tab Bar
  - Show All Tabs ⇧⌘\
  - Auto Select the Latest Request ⇧⌘L
  - Select Next Tab ⇧⌘]
  - Select Previous Tab ⇧⌘[
- **Window:** Move Tab to New Window, Merge All Windows. 이 메뉴를 보면 macOS 기본 창 탭을 쓰는 문서 기반 앱이다. 창 제목은 Listen IP다.

**공식 문서(proxyman.com/docs/basic-features/multiple-tabs).**

- 탭마다 출처(앱·도메인), 필터, 선택한 요청이 따로 있다.
- 라이브 탭들은 **같은 캡처를 공유한다**.
- 새 탭을 여는 방법은 세 가지다. ⌘T, 탭 막대의 `+`, 사이드바의 앱·도메인을 우클릭해서 **Open as New Tab**.
- 탭은 끌어서 순서를 바꾼다.
- 탭 우클릭 메뉴에는 Close Tab, Close Other Tabs, Close Tabs to the Right가 있다.
- 마지막 탭을 닫으면 창이 닫힌다.

**문서와 변경 이력.**

- Save Session은 세션 전체(모든 요청, 앱, 도메인, 기기)를 저장한다.
- Open은 ⌘O, 끌어다 놓기, Finder 더블클릭으로 할 수 있다.

**확인하지 못한 것.**

- 새 탭(⌘T)이 처음에 무엇을 보여 주는지
- 파일을 새 탭으로 여는지
- 저장하지 않은 상태 표시와 닫을 때 저장할지 묻는지
- 다시 실행할 때 탭을 복원하는지

## 3. 목표·비목표·반목표

**목표**

- 한 창에 macOS 기본 창 탭을 여러 개 연다. 탭마다 보기 상태를 따로 갖는다.
- 라이브 탭은 하나의 라이브 세션을 함께 본다. 파일 탭은 자기만의 세션을 갖는다.
- Open… / Open Recent / 끌어다 놓기 / Finder 더블클릭으로 연 파일은 새 탭에 열린다.
- 사이드바 우클릭 Open as New Tab.
- HAR을 가져올 때 클라이언트 이름을 되살려, 사이드바에서 클라이언트별로 묶는다.
- 원격 기기가 Bonjour로 알리는 이름을 찾아, 직접 붙인 이름이 없으면 IP 대신 보여 준다.

**비목표(이번에 하지 않음)**

- 호스트 그룹 탭: 다음 묶음.
- New Folder, New Domain or App, Convert .chls, Command Palette.
- ⇧⌘1–9로 N번째 탭 선택. 6.3 메뉴에 없고, macOS 기본 탭에도 없다.
- 저장하지 않은 상태 표시와 닫을 때 저장 확인. 다시 실행할 때 탭 복원.
- 탭 이름 바꾸기, 탭 사이로 요청 끌어 옮기기.
- 기기 이름: adb·ARP·역방향 DNS로 찾기, MAC 주소로 기기 알아보기(IP가 바뀌면 직접 붙인 이름은 옛 IP에 남는다), Android 기기 종류 추가.

**반목표(이렇게 되면 실패)**

- 탭을 여러 개 열었더니 라이브 캡처가 느려지거나, 보이지 않는 탭이 계속 다시 계산한다.
- 메뉴 명령(Delete, Highlight, cURL, Export, Clear)이 지금 보고 있는 탭이 아닌 다른 탭에 작용한다.
- 파일을 열면 라이브 세션이 사라진다. 지금 동작이 이렇고, 이걸 없애려는 것이다.
- 마지막 창을 닫으면 프록시 서버가 멈추거나, 다시 창을 열 방법이 없다.
- 한 탭의 필터나 선택을 바꿨더니 다른 탭도 바뀐다.
- 자동으로 찾은 이름이 사용자가 직접 붙인 이름이나 종류를 덮는다.
- 이 Mac 트래픽만 보는 사용자에게도 로컬 네트워크 권한 창이 뜬다.

## 4. 동작

### 4.1 탭과 세션

- **라이브 세션은 앱에 하나**다(`AppModel`이 가진다). 녹화, Clear, Delete, Highlight, 코멘트, 번호는 이 세션에 속한다. 그래서 라이브 탭 하나에서 Clear·Delete를 하면 모든 라이브 탭에 반영된다. "같은 캡처를 공유한다"는 문서에서 끌어낸 결론이다.
- **파일 탭**은 연 파일의 세션을 따로 갖는다. 라이브 요청은 들어오지 않는다. 여기서 한 Clear·Delete·Highlight는 그 탭에만 적용된다. 저장하지 않고 닫으면 사라지고, 묻지 않는다. **(내 판단)**
- **탭마다 따로 갖는 보기 상태**
  - 필터: 칩, 숨김 포함, 규칙 막대와 그 표시 여부
  - 선택, 정렬
  - 사이드바 선택, 사이드바 거르기 글자, 펼친 도메인
  - 본문 일치 작업
  - 파생 목록과 트리
  - 지우기 확인, 코멘트 시트
- **Auto Select는 지금처럼 전역 설정**이다. 켜져 있으면 각 라이브 탭이 자기 목록에서 최신 요청을 따라간다. 사용자가 행을 고르면 꺼진다. **(내 판단: 6.3에서는 View 메뉴의 토글 하나다.)**
- **단축키**
  - New Session ⌘T: 새 라이브 탭을 연다. 모든 요청 보기, 빈 필터로 시작한다. **(내 판단)**
  - Close ⌘W: 탭을 닫는다.
  - Close All ⌥⌘W: 모든 탭을 닫는다.
  - Select Next Tab ⇧⌘], Select Previous Tab ⇧⌘[.
  - Show Tab Bar, Show All Tabs, Move Tab to New Window, Merge All Windows, 탭 우클릭 메뉴는 macOS가 제공하는 것을 그대로 쓴다.
- **앱을 실행하면** 라이브 탭 하나를 연다. 마지막에 쓰던 필터 규칙을 복원하는 것은 지금과 같다. 그 뒤에 여는 새 탭은 빈 필터로 시작한다.
- **창이 모두 닫혀도** 앱과 프록시는 계속 돈다. Dock 아이콘 클릭, 상태 막대 메뉴, ⌘T로 라이브 탭을 다시 연다.
- **탭 제목**
  - 라이브 탭: 사이드바에서 고른 항목 이름. 고른 게 없으면 `All Requests`. **(내 판단: 6.3은 Listen IP를 제목으로 쓰지만, 그건 이미 툴바 캡슐에 보인다.)**
  - 파일 탭: 파일 이름.
- **보이지 않는 탭**(뒤에 있는 탭)은 목록과 트리를 다시 계산하지 않는다. 앞으로 나올 때 한 번 계산한다.

### 4.2 메뉴

- **File 메뉴**
  - New Session ⌘T
  - Open… ⌘O
  - Open Recent ▸ 최근 파일들, Clear Menu
  - Save Session… ⌘S
  - Clear Session ⌘K: 지금의 "세션 지우기"
  - Close ⌘W
  - Close All ⌥⌘W
- **View 메뉴:** Select Next Tab ⇧⌘], Select Previous Tab ⇧⌘[ (Auto Select 아래).
- **메뉴 이름은 Proxyman과 같은 영어로** 맞춘다. 지금의 "세션 열기… / 세션 저장… / 세션 지우기"를 바꾸는 것이다. **(내 판단: 메인 화면 묶음도 Proxyman의 영어 이름을 썼다.)**
- ⌘S는 Proxyman에는 없지만, Prog에서 이미 쓰고 있어서 유지한다. **(내 판단)**
- **메뉴 명령과 툴바·하단 바·상태 막대 메뉴는 앞에 있는 탭에 작용한다.**

### 4.3 열기·최근 파일·저장

- 열 수 있는 것: Prog 세션(`.eyeproxy`)과 HAR.
- 여는 방법: Open… ⌘O, Open Recent, 창에 끌어다 놓기, Finder 더블클릭(`open -a` 포함).
- 어떤 방법이든 **새 파일 탭**으로 열린다. 이미 열려 있는 파일이면 그 탭으로 이동한다. **(내 판단)**
- **Open Recent:** macOS 최근 문서 목록(`NSDocumentController`)을 쓴다.
  - 파일을 열거나 저장할 때 목록에 올린다.
  - 개수는 시스템 설정을 따른다.
  - 없는 파일을 고르면 오류 알림을 띄우고 목록에서 뺀다.
- **Save Session…:** 앞에 있는 탭의 세션 전체를 저장한다. 라이브 탭이면 라이브 세션 전체다. 저장한 뒤에도 탭은 그대로 남는다.
- **Export와 Save Requests:** 지금 기능 그대로 쓰되, 앞에 있는 탭을 대상으로 한다.

### 4.4 사이드바 Open as New Tab

앱, 기기, 도메인, 경로 항목을 우클릭하면 Open as New Tab이 나온다. 이걸 고르면 같은 세션을 보는 새 탭이 열리고, 사이드바는 그 항목이 선택된 상태다. 파일 탭에서 고르면 새 탭도 같은 파일 세션을 본다.

### 4.5 HAR 클라이언트 이름

- HAR을 가져올 때 `_prog.client`를 그 요청의 `Flow.clientAddress`에 넣는다. 값이 없으면 지금처럼 빈 문자열이다. **(내 판단)** 별도 사전을 두지 않는 이유는, 지금 코드가 이미 사이드바 묶기, Client 열, Export, 세션 파일 저장을 모두 `clientAddress` 기준으로 하기 때문이다. 이렇게 하면 새 저장 필드 없이 다음이 그대로 된다.
  - 사이드바: Remote devices 아래에 클라이언트 이름별로 묶인다. 이름이 없는 요청은 지금처럼 "가져온 요청"으로 묶인다.
  - Client 열과 Export에 그 이름이 나온다. 그래서 HAR을 내보냈다가 다시 가져와도 이름이 유지된다.
- 대가: 가져온 요청의 IP Address 필터는 IP 대신 이름에 걸린다.

### 4.6 원격 기기 이름 자동 찾기

Proxyman이 원격 기기 이름을 어떻게 정하는지는 확인하지 못했다. 이 절은 모두 **(내 판단)**이다.

- **지금 있는 것:** 설정의 "연결된 기기"에서 이름과 종류를 직접 붙일 수 있다. 이름은 `Device.displayName`을 거쳐 사이드바 Remote devices, Client 열, Export, 상세 Summary에 쓰인다. 붙이지 않으면 IP다.
- **새로 하는 것:** 같은 네트워크의 Bonjour 광고에서 이름을 찾아 기기에 붙인다.

  | 광고 | 주로 알리는 기기 | 이름 | 종류(TXT 모델 값) |
  |---|---|---|---|
  | `_airplay._tcp` | Apple TV, Mac | 서비스 이름 | `model` |
  | `_companion-link._tcp` | iPhone, iPad, Apple TV | 서비스 이름 | `rpMd` |
  | `_googlecast._tcp` | Chromecast, Google TV | TXT `fn` | 없음 |

  - 모델 값이 `AppleTV`, `iPhone`, `iPad`로 시작하면 그 종류다. 그 밖에는 종류를 모른다.
- **우선순위:** 직접 붙인 이름 > 자동 이름 > IP.
  - 자동 이름은 직접 붙인 이름을 덮지 않는다. 직접 붙인 이름을 지우면 자동 이름이 보인다.
  - 자동 종류는 종류가 "알 수 없음"일 때만 채운다.
- **저장:** 자동 이름도 `devices.json`에 함께 저장한다. 기기가 꺼져 있어도 마지막 이름이 남는다. 같은 IP에서 다른 이름이 광고되면(공유기가 IP를 다시 나눠 준 경우) 새 이름으로 바꾼다. 옛 `devices.json`도 그대로 읽힌다.
- **트래픽보다 광고가 먼저 오면:** 기억해 두었다가, 그 IP가 처음 트래픽을 보낼 때 붙인다.
- **언제 찾나:** 루프백이 아닌 기기가 처음 트래픽을 보낼 때 시작한다. 실행할 때 `devices.json`에 원격 기기가 이미 있으면 바로 시작한다. 한 번 시작하면 앱이 도는 동안 계속 듣는다. 이 Mac 트래픽만 보는 사용자에게는 로컬 네트워크 권한 창이 뜨지 않는다.
- **찾지 못하면:** 권한을 거부했거나 이름을 알리지 않는 기기라면 지금처럼 IP를 보여 준다. 오류 알림은 띄우지 않는다.
- **설정 화면:** 이름 칸이 비어 있으면 회색 안내 글자로 자동 이름이 보인다. 지금도 안내 글자로 `displayName`을 쓰므로 따로 고칠 것은 없다.

## 5. 제약

- 프로젝트 규칙
  - 외부 패키지 허용 목록에 없는 것은 추가 금지
  - 모듈 방향 앱 → Kit → Core
  - App Sandbox 끔
  - 커밋은 `<type>(<scope>): <한국어 요약>`
- 공개 레포 규칙: 커밋할 파일에 사내 도메인이나 로컬 경로를 넣지 않는다.
- macOS 15 이상, Swift 6. 그래서 `WindowGroup`의 `.restorationBehavior(.disabled)`를 쓸 수 있다.
- 세션 파일 형식은 하위 호환: 옛 파일도 열려야 하고, 새 필드는 선택이다.

## 6. 만드는 사람에게 맡기는 것

- 탭이 앞에 왔는지 아는 방법: `NSWindow` 알림이나 SwiftUI `controlActiveState`, 가림 상태 중에서 고른다.
- 앞 탭을 추적하는 방법: `AppModel.activeTab`이나 `focusedSceneValue` 중에서 고른다.
- `NSWindow` 탭을 켜는 세부 방법: `tabbingMode`, `tabbingIdentifier`.
- `AppModel`에서 탭으로 옮기는 코드를 어떻게 나눌지.
