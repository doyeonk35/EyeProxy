# Prog 세션 탭 — 핸드오버 (2026-11-12)

플랜: `2026-11-12-prog-session-tabs.md` · 스펙: `../specs/2026-11-12-prog-session-tabs-design.md` · 브랜치: `feat/session-tabs`(base `9c5ae49`)
상태: Task 1~6 구현·리뷰 완료. 아래 3장의 점검표는 Finder·실기기·시스템 권한 창이 필요해 자동 확인에서 뺀 것이라 사람이 확인한다.
테스트: `swift test --package-path Packages/EyeProxyKit` 373개, `swift test --package-path Packages/EyeProxyCore` 60개. Debug 앱 빌드 성공.

## 1. 무엇이 들어갔나

Proxyman 6.3처럼 한 창 안의 세션 탭, 파일을 새 탭으로 열기, Open Recent, 원격 기기 이름 자동 찾기. 사용자 설명은 README의 "세션 탭"·"원격 기기 이름 자동 찾기"·"알려진 제한(세션 탭·기기 이름)" 절.

| Task | 내용 | 커밋 |
|---|---|---|
| 1 | HAR 가져올 때 `_prog.client`를 `Flow.clientAddress`로 되살림(Client 열·사이드바 묶음·다시 내보내기). | `04fc461` |
| 2 | 보기 상태(필터·선택·정렬·사이드바 등)를 `SessionTab`으로 분리. | `b33aaa8` |
| 3 | 탭: New Session ⌘T, Close ⌘W, Close All ⌥⌘W, Select Next/Previous Tab ⇧⌘]/⇧⌘[, 사이드바 Open as New Tab. 라이브 탭은 한 캡처를 공유, 파일 탭은 독립. 메뉴 이름을 영어(Open…·Save Session…·Clear Session)로. | `ec7592b` |
| 4 | 파일을 새 탭으로 열기(Open… ⌘O, Open Recent ▸ Clear Menu, 끌어다 놓기, Finder·`open -a`), Save Session… ⌘S. | `58c87d8` |
| 4 수정 | 문서 실행일 때만 Breakpoints 창 닫기. | `9ad35e7` |
| 5 | Bonjour(`_airplay._tcp`·`_companion-link._tcp`·`_googlecast._tcp`)로 기기 이름·종류 자동 찾기, `devices.json` 저장. | `09e75e1` |
| 5 수정 | 기기 주소를 IPv4로 맞춤. | `28cf1c5` |
| 6 | README와 이 문서. | 이 커밋 |

## 2. 알아 둘 결정·달라진 점

스펙에서 Proxyman 자료로 확인하지 못해 내가 정한 것(스펙의 **(내 판단)**):
- 파일 탭의 Clear·Delete·Highlight는 그 탭에만 적용되고, 저장하지 않고 닫아도 묻지 않는다.
- New Session ⌘T는 모든 요청 보기·빈 필터로 시작한다.
- 라이브 탭 제목은 사이드바에서 고른 항목 이름(없으면 `All Requests`). 6.3은 Listen IP를 쓰지만 그건 툴바 캡슐에 이미 있다.
- Auto Select는 전역 설정 하나(6.3도 View 메뉴 토글 하나).
- 메뉴 이름을 Proxyman의 영어로(Open…·Save Session…·Clear Session). ⌘S는 Proxyman에 없지만 이미 쓰고 있어 유지.
- 어떤 방법으로 열어도 새 파일 탭이고, 이미 열린 파일이면 그 탭으로 이동.
- HAR `_prog.client`를 `Flow.clientAddress`에 넣는다(별도 사전 없음, 세션 파일 형식 그대로). 대가로 가져온 요청의 IP Address 필터가 이름에 걸린다.
- 기기 이름 자동 찾기 전체(Proxyman 방식 미확인): 광고 종류 세 가지, 우선순위 직접 이름 > 자동 이름 > IP, `devices.json` 저장, 처음 트래픽이 올 때 시작(권한 창은 그때만), 거부하면 IP·알림 없음.

구현 중 달라진 점:
- Close(⌘W)·Close All(⌥⌘W)은 별도 명령이 아니라 시스템 기본 메뉴(Close의 ⌥ 대체 항목)다. 그래서 Close All은 Compose·Breakpoints·기기·설정 창까지 모두 닫는다.
- Debug 빌드가 문서 종류를 선언해 Finder가 Debug 빌드를 기본 앱으로 고를 수 있다.
- 파일을 받으며 시작하면 SwiftUI가 여는 Breakpoints 창(창 id `breakpoints`)을 닫는데 잠깐 보일 수 있다. 새 탭도 앞 창의 탭 묶음에 붙기 전 잠깐 별도 창으로 깜빡일 수 있다.
- 기기 주소는 IPv4만 맞춘다.
- 세션 파일 형식 변경 없음(`index.json` version 1).

## 3. 수동 점검표(사용자)

**탭·파일**
- [ ] Finder에서 `.eyeproxy`·`.har` 더블클릭 → 새 파일 탭(기본 앱이 다른 Prog 복사본이 아닌지 확인).
- [ ] 파일을 창에 끌어다 놓기 → 새 파일 탭.
- [ ] 상태 막대 메뉴 Show Prog가 메인 창을 다시 연다(메뉴 막대에 Prog 아이콘이 둘이면 어느 쪽인지 확인).
- [ ] 실제 iPhone 트래픽을 보내며 탭 3개(전체·기기·도메인): 필터·선택이 탭마다 따로이고, 한 탭에서 Clear하면 나머지에도 반영되는지.
- [ ] 트래픽이 많을 때 탭 여러 개의 메모리(하단 바)와 반응.
- [ ] Stay On Top(설정 ▸ Advanced)을 켠 채 탭 추가·이동.
- [ ] 전체 화면에서 ⌘T·탭 이동·Close.
- [ ] Close All ⌥⌘W가 Compose·Breakpoints·기기·설정 창까지 닫는다 — 보내지 않은 Compose 편집이 사라지는 것을 받아들일 수 있는가(아니면 메인 탭만 닫게 바꾼다).

**기기 이름**
- [ ] Apple TV나 Google TV가 처음 트래픽을 보낼 때 macOS 로컬 네트워크 권한 창이 한 번 뜬다(이 Mac 트래픽만이면 안 뜬다).
- [ ] 허용하면 사이드바 Remote devices, Client 열, 설정 ▸ 연결된 기기에 광고 이름이 보인다.
- [ ] 직접 이름을 붙이면 그 이름이 이기고, 지우면 광고 이름으로 돌아간다.
- [ ] 권한을 거부하면 IP로 보이고 알림이 없다.

## 4. 다음 묶음

- 호스트 그룹 탭(도메인·앱 묶음별 탭).
- 탭 복원(재실행 시), 이름을 알리지 않는 기기의 이름 직접 입력 편의(IP가 바뀌면 다시 붙여야 하는 문제).

## 5. 머지 메모

- 새 패키지 없음. 세션 파일 형식·설정 키 변경 없음. Info.plist에 `NSLocalNetworkUsageDescription`·`NSBonjourServices` 3종(`_airplay._tcp`·`_companion-link._tcp`·`_googlecast._tcp`)과 문서 종류가 있다.
- 메인 체크아웃에 스펙·플랜의 추적 안 된 복사본이 남아 있으면 main에 머지하기 전에 지운다.
- 머지 전 위 점검표 중 Finder 더블클릭과 로컬 네트워크 권한 창은 손으로 한 번 보는 것을 권한다.
