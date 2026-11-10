# Prog 목록·상세 편의·Export 핸드오버 (2026-11-09)

플랜: `2026-11-09-prog-list-detail-export.md` · 스펙: `../specs/2026-11-09-prog-list-detail-export-design.md` · 브랜치: `list-detail`(base `8bf5bb7`)
상태: Task 1~13 구현·리뷰 완료. 아래 2장의 **미확인** 항목은 사람이 확인한다(저장·열기 패널, 확인 알림, 시스템 외관 전환, 다른 OS 버전 등 자동 확인에서 열지 않은 경로).
테스트: `swift test --package-path Packages/EyeProxyCore`, `swift test --package-path Packages/EyeProxyKit`(Kit 321개, Task 9 시점).

## 1. 무엇이 들어갔나

Proxyman에서 매일 쓰던 손버릇(Highlight, Delete/Delete All, Auto Select, Raw·요약 보기)을 채우고, 나중에 CLI·MCP가 올라갈 Export·HAR 가져오기 API를 Kit에 고정했다. 상태 막대는 눈 아이콘 + 빨간 점으로, 툴바와 툴팁을 다듬었다. 사용자 설명은 README의 목록 편의·상세 탭·Export·HAR 열기·툴바·툴팁·상태 막대 메뉴 절.

| Task | 내용 | 커밋 |
|---|---|---|
| 1 | Kit: ID 번호를 안정 번호로(저장 번호 사전, 지워도 다시 매기지 않음, unrecorded 최신 번호 되돌림, 세션 파일 `numbers`). | `fbe7246` |
| 2 | Kit: `SessionStore.remove(ids:)`, `FlowHighlight` 모델, 세션 파일 `highlights`. | `2d34a93` |
| 3 | 앱: Highlight 색(⌘1…⌘6)·취소선(⇧⌘X)·Reset(⌘0), Delete(⌫)·Delete All(보이는 행만, 숨은 행 있으면 확인). 수정: 막대 행 높이 전체·선택색 우선·숨은 선택 행 삭제 방지·Delete All 게이트. | `0b9e855`, `bd5be27` |
| 4 | Kit+앱: Auto Select(`AutoSelect.latest`, 사용자 선택이면 끔). 수정: Delete·Repeat·Highlight·코멘트 대상을 실행 시점 선택으로. | `2f847ea`, `54387c9`, `201c61d` |
| 5 | Kit: M3U8 파서(master·media, 상대 URI, BYTERANGE, KEY). 수정: BOM·잘못된 줄 내성. | `a9f8088`, `efd9915` |
| 6 | Kit+앱: `RawMessage`, Raw 탭·접는 요약·M3U8 탭. 수정: Raw 내용 키 갱신, 세그먼트 # = MEDIA-SEQUENCE + 순번, 키 절대 URL, SSL 3가지 표기, 취소된 Raw 작업 경쟁. | `8dce694`, `8b9cb31`, `8a3d7bf` |
| 7 | Kit: `FlowExport.har`·`csv`. 수정: 본문을 풀어 `content.text`, 바뀐 원본은 `_prog.raw*Body`, 쿼리 분해 보강. | `2af3ac5`, `b7b2886` |
| 8 | Kit(+Core): `FlowImport.har`. 수정: 항목별 관대한 해석, ws/wss 기본 포트, 날짜 대체. | `9cdbb79`, `f538ddd` |
| 9 | 앱: Flow ▸ Export·Save Requests·우클릭 Export, ⌘O로 HAR 열기, `.har` UTI. 수정: 선택이 모두 숨으면 보이는 행 전체, 클라이언트 이름 공용 함수, 앱 CSV만 UTF-8 BOM. | `5563c0b`, `9577042` |
| 10 | 상태 막대 눈 아이콘(뜸·감음·사선) + 빨간 점, `sips` 렌더. 추가(사용자 요청): 앱 아이콘 투명 모서리, macOS 기본 여백(824 본체). | `4920cd5`, `aeec28d`, `284053d` |
| 11 | 툴바: 상태 캡슐 여백, "숨김 포함" 체크박스 → 눈 토글(SSL 자물쇠와 같은 묶음). | `3d9e6b4` |
| 12 | 툴바·필터 칩·메뉴 막대·상태 메뉴·우클릭·Certificate 창 한국어 한 줄 툴팁. 추가: Mac IP 피커 툴팁. | `590d56a`, `8614eb1` |
| 13 | README와 이 문서. | 이 커밋 |

## 2. 수동 점검표

근거의 파일 이름은 구현 세션 scratchpad의 `taskN/` 폴더 스크린샷이다(커밋하지 않음). "코드 확인"은 코드를 읽어 확인했고 실제 화면은 보지 않았다는 뜻이다. 자동 확인은 자기 Debug 빌드(포트 19090)에서 모달을 열지 않고 했다.

| 항목 | 방법 | 상태 | 근거 |
|---|---|---|---|
| Highlight 표시(라이트) | 행마다 색(메뉴·⌘1…⌘6)·⇧⌘X·⌘0 Reset, 한 행 선택 | 확인됨 | `task3/10-light-b-highlights.png`, `task3/30-fix-light-b-highlights.png` |
| Highlight 표시(다크) | 같은 시나리오를 시스템 다크에서 | 확인됨 | `task3/40-dark-highlights.png`, `task3/40c-dark-crop.png` |
| 실제 키보드로 ⇧⌘X | 하드웨어 키보드로 ⇧⌘X(자동 확인은 앱에 직접 보낸 이벤트만 닿았고, HID 경로는 다른 앱의 전역 단축키에 막힌 것으로 보임) | 미확인 | - |
| ⌫ 삭제·안정 번호·선택 이동 | 가운데 행 ⌫ → 번호 그대로, 선택 아래로 / 마지막 행 ⌫ → 위로 | 확인됨 | `task3/20-after-delete.png`, `task3/22-after-delete-last.png` |
| 숨은 선택 행 보호 | 두 행 선택 뒤 사이드바로 하나 숨기고 ⌫ | 확인됨 | `task3/31a-filtered-after-delete.png`, `task3/31b-hidden-selection-kept.png` |
| 우클릭 ▸ Delete | 선택 안 된 행을 우클릭 ▸ Delete(Auto Select 켬·끔) | 확인됨 | `task3/24-after-context-delete.png`, `task4/b-after-context-delete.png` |
| 우클릭 메뉴 구성 | 행 우클릭 | 확인됨 | `task3/26-context-menu.png` |
| 검색창 ⌫ | 검색창에서 글자 입력 뒤 ⌫(빈 칸에서 한 번 더) | 확인됨 | `task4/c-search-cleared.png` |
| 코멘트 시트 ⌫ | Add Comment… 시트에서 ⌫ | 미확인 | - |
| Delete All(필터 없음) | 걸러진 행 없이 Flow ▸ Delete All | 확인됨 | `task3/25-after-delete-all.png` |
| Delete All 확인 알림 | 검색어·사이드바·필터 칩으로 일부를 숨기고(Auto Select 켬 상태 포함) Delete All → "보이는 N개를 지웁니다. 숨겨진 M개는 남습니다." / 지우기 → 보이는 것만 지움, 숨긴 것 남음 / 취소 → 그대로 | 미확인 | - |
| 다른 창이 앞일 때 비활성 | Compose·Breakpoint 창을 앞에 두고 Flow 메뉴 | 미확인 | 코드 확인(focused value 게이트) |
| 프로세스 귀속 정리 | Client가 붙은 Mac 앱 흐름을 지운 뒤 세션 저장·열기 | 미확인 | 코드 확인(`processes.remove`) |
| Auto Select 따라가기·스크롤 | View ▸ Auto Select 켜고 요청 여러 개 | 확인됨 | `task4/01-autoselect-3-curls.png`, `task4/07-scrolled-to-latest.png` |
| Auto Select 유지 | 자동 선택된 최신 행을 ⌫ / 검색으로 선택 행 숨김 | 확인됨 | `task4/02-after-delete-still-on.png`, `task4/a-after-delete.png`, `task4/c-search-hides-selected.png` |
| Auto Select 끄기 | ↑ 키 / 마우스로 다른 행 클릭 → 메뉴 체크 꺼짐, 다음 요청 안 따라감 | 확인됨 | `task4/05-arrow-up-turns-off.png`, `task4/e-click-other-row.png`, `task4/06-off-new-flow-not-followed.png` |
| Raw 탭 | JSON 요청·응답 Raw(한글 본문) | 확인됨 | `task6/02-json-raw.png` |
| 큰 Raw | 5.5 MB 텍스트 응답 Raw | 확인됨 | `task6/13-big-raw.png` |
| Breakpoint 편집 → Raw 갱신 | 요청 Breakpoint에서 헤더·URL을 고쳐 Apply & Execute → Raw 탭이 새 요청을 보임 | 미확인 | 코드 확인(`.task(id: source.key)`) |
| 요약 | 요약 펼치기, Highlight·SSL 값 | 확인됨 | `task6/03-json-summary.png`, `task6/22c.png` |
| M3U8 master·media | 로컬 평문 재생목록 두 개 | 확인됨 | `task6/20-fix-master-m3u8.png`, `task6/21-fix-media-m3u8.png` |
| M3U8 URI 복사·탭 복귀 | URI 우클릭 ▸ URL 복사 / 재생목록 아닌 흐름으로 가면 헤더 탭 | 확인됨 | `task6/10-uri-context-menu.png`, `task6/12c.png` |
| 실제 CDN HLS(HTTPS) | SSL Proxying을 켠 호스트의 실제 재생목록 | 미확인 | - |
| Flow·Export 메뉴 구성 | Flow ▸ … Save Requests… / Export ▸ 세 항목, 빈 세션에서 비활성 | 확인됨 | AX 메뉴 덤프(스크린샷 없음, task-9-report) |
| Export HAR(선택 없음) | 필터를 건 채 Flow ▸ Export ▸ as HAR… → 기본 이름 `Prog-<yyyyMMdd-HHmmss>.har`, 보이는 행만, ID 오름차순, `log.creator.version` = 앱 버전 | 미확인 | - |
| Export(선택 있음)·우클릭 Export | 2행 이상 선택 뒤 Export / 행 우클릭 ▸ Export ▸ 세 형식 → 그 행만 | 미확인 | - |
| 숨은 선택과 Export 범위 | 2행 선택 → 둘 다 숨김 → Export = 보이는 행 전체 / 하나만 숨김 → 보이는 선택 행만 | 미확인 | 코드 확인 |
| Save Requests 활성·범위 | 선택 없음·보이는 선택 없음 → 비활성 / 선택 있음 → 그 행만 저장(다시 열어 확인) | 미확인 | 빈 세션 비활성만 AX 확인 |
| CSV와 Excel 한글 | as CSV… → Excel for Mac·Numbers로 열기: 헤더 행, 한글 코멘트·클라이언트 이름, Client 열 = 목록 Client 열 | 미확인 | 코드 확인(앱이 BOM을 붙임) |
| Prog 세션 내보내기 왕복 | as Prog Session… → ⌘O로 다시 열기: 번호(빈 번호 포함)·코멘트·Highlight·Client | 미확인 | - |
| Proxyman이 설치된 Mac의 `.har` | as HAR… 저장 패널 기본 이름이 정확히 `Prog-<stamp>.har`(`.har.har`·확장자 묻기 없음) / ⌘O 패널에서 `.har` 선택 가능 | 미확인 | - |
| ⌘O로 Prog HAR 열기 | Prog가 내보낸 HAR 열기 → 세션 교체, 번호·코멘트·Highlight·취소선 복원, Client 열 빈칸, 사이드바 All. 사이드바에서 가져온 흐름(클라이언트 주소 없음)이 어떻게 보이는지 | 미확인 | - |
| 다른 도구 HAR 열기 | Chrome DevTools·Proxyman HAR → 파일 순서대로 1…n | 미확인 | Kit 테스트 |
| 잘못된 HAR | `{}`·평문을 `.har`로 바꿔 열기 → "HAR 파일을 열지 못했습니다: <이유>" | 미확인 | Kit 테스트(`invalidHAR`) |
| 패널 취소 | 저장·열기 패널에서 취소 → 변화·알림 없음 | 미확인 | - |
| 상태 막대 눈(기록 중) | 실제 메뉴 막대(다크) | 확인됨 | `task10/live-ok-zoom.png` |
| 상태 막대 빨간 점(서버 실패) | 포트를 미리 점유하고 실행 → 사선 눈 + 빨간 점 | 확인됨 | `task10/live-fail-zoom.png` |
| 세 상태·빨간 점 조건 | 실제 막대에서 기록 끔(눈 감음), 멈춘 Breakpoint 대기·규칙 파일 경고일 때 점, 모두 해소되면 점 사라짐 | 미확인 | `task10/contact-sheet.png`(오프라인 렌더만) |
| 빨간 점 + 라이트↔다크 | 점이 떠 있는 동안 시스템 외관을 바꿔 눈 색이 막대를 따르는지 | 미확인 | 오프라인 렌더만 |
| 앱 아이콘 여백·모서리 | Dock·Finder에서 다른 앱과 크기 비교, 모서리 흰 사각 없음 | 미확인 | `task10/appicon-margin.png`, `task10/appicon-before-after.png`(렌더 비교만) |
| 툴바(다크) | 자물쇠+눈 묶음, 눈 끔·켬(회색 선택 채움) | 확인됨 | `task11/after-toolbar-off.png`, `task11/after-toolbar-on.png` |
| 툴바(라이트) | 시스템 라이트에서 같은 확인 | 미확인 | - |
| 눈 토글 동작 | 마우스로 눈 클릭 → Block List로 숨긴 요청이 나타나고 사라짐 | 미확인 | AXPress로 토글 값만 확인 |
| 메뉴·툴바 툴팁 | Tools ▸ Map Local… 호버, 툴바 눈 호버 | 확인됨 | `task12/menu-tools-maplocal.png`, `task12/toolbar-eye.png` |
| macOS 15 툴팁 | macOS 15 Mac에서 메뉴 항목 호버 | 미확인 | - |
| 상태 막대·우클릭·인라인 피커 툴팁 | 상태 막대 메뉴 항목, 목록 우클릭 항목, View ▸ 레이아웃 A/B 호버 | 미확인 | - |
| xcstrings 동기화 | Xcode GUI에서 한 번 빌드(CLI 빌드는 갱신 안 함) → `Localizable.xcstrings` 커밋 | 미확인 | 이 브랜치에서 변경 없음 |

집계: 확인됨 21 / 미확인 26.

참고: 디버그 빌드는 v1.0.0보다 버전이 낮아 Sparkle 업데이트 창이 뜰 수 있다. 수동 확인 때는 실행 인자 `-SUEnableAutomaticChecks NO`(인자 도메인, 저장 안 됨)를 붙인다.

## 3. 보류·결정 요약

**사용자 결정**
- 안정 번호 a안: 한 번 붙은 번호는 그대로, 지워도 빈 번호.
- Strikethrough ⇧⌘X(스펙의 ⌥⌘S는 사이드바 접기와 충돌).
- 숨김 토글 켬 상태는 회색 선택 채움 유지(강조색 안 칠함).
- 앱 아이콘 흰 모서리 수정과 macOS 기본 여백을 이번 묶음에 넣음.

**구현 중 결정(ruling)**
- 요약은 패널 탭이 아니라 헤더 바 아래 접는 영역(대기·실패 흐름에서도 보이게).
- Auto Select는 보이는 목록의 최신 행이 바뀔 때만 선택을 쓴다. 끄는 것은 Table 선택 바인딩(클릭·키보드)뿐이고 Delete·세션 열기·자동 선택은 끄지 않는다.
- Flow 메뉴 동작은 메뉴 렌더 시점이 아니라 실행 시점의 선택을 대상으로 한다(Auto Select의 비동기 선택과 어긋남 방지). 그 결과 Add/Edit Comment는 한 행 선택일 때만 켜진다.
- HAR 본문은 풀어서 `content.text`, 풀어서 바뀌었으면 원본을 `_prog.rawRequestBody`/`rawResponseBody`에. 가져오기는 `_prog.raw*`를 우선한다.
- HAR 가져오기는 항목별로 관대하게, 읽을 항목이 0개일 때만 실패. 번호가 겹치거나 0 이하면 전부 다시 매김.
- Export 범위는 "보이는 선택 행, 없으면 보이는 행 전체". 세션 내보내기의 연결 로그는 전체일 때만.
- CSV BOM은 앱이 파일로 쓸 때만, Kit `FlowExport.csv`는 BOM 없음(CLI·MCP 출력 그대로).
- 상태 막대·앱 아이콘 렌더를 qlmanage(불투명 흰 배경)에서 `sips`로. 옛 개구리 상태 막대 PNG가 불투명했던 것이 잘 안 보였던 원인일 가능성.
- 툴바 묶음 안쪽 여백·간격은 SwiftUI API가 없어 시스템 기본(약 4pt) 수용.

**미룬 것(README 알려진 제한에도 있음)**
- 같은 길이 본문만 바뀐 편집은 Raw·본문 탭이 갱신 안 됨(근본 해법은 편집 세대 카운터). M3U8 탭은 응답 편집 뒤 갱신 안 됨.
- Finder 더블클릭·`open -a`로 `.har` 열기(`application(_:open:)` + `CFBundleDocumentTypes`, "현재 세션 교체?" 결정 필요).
- HAR 가져오기에서 클라이언트 이름 복원, 가져온 흐름의 사이드바 묶기(`clientAddress`가 빈 문자열).
- 외부 HAR: `wss` 복호화 여부, URL 세부(userinfo·대문자 scheme·명시 기본 포트). Core `UpstreamClient` 기본 포트 판정은 http/https만(Host 헤더 우선이라 실사용 영향 없음).
- CSV 수식 주입 방어, `FlowExport.har`의 `try!`.
- 세션 파일의 손상된 `numbers`(중복·0 이하)를 `replace`가 그대로 받음.
- Delete 되돌리기(⌘Z), 색으로 거르기.
- 도구 창(`Views/Tools/*`)·Compose의 영어 툴팁 통일.
- M3U8 URI 열 폭, 요약 펼침 상태 유지, 테스트 공백(쉼표 든 EXTINF 제목, 주석 낀 STREAM-INF, `userSelect` 단위 테스트 — 앱 타깃).

## 4. 머지 메모

이 브랜치가 갈라진 뒤 `main`에 v1.0.0 릴리스 커밋 `1458c57`이 들어갔다(`EyeProxy/Info.plist`의 `CFBundleVersion` 5·`CFBundleShortVersionString` 1.0.0, `project.yml`, `docs/appcast.xml`). 이 브랜치도 `EyeProxy/Info.plist`를 고쳤다(`.har` UTI `UTImportedTypeDeclarations` 추가, 파일 끝). 두 쪽 모두 남기면 되고 작은 충돌이 날 수 있다 — 버전은 main 값, UTI 선언은 이 브랜치 값. 머지 뒤 `xcodegen generate` + Debug 빌드, 빌드된 Info.plist에 `com.tv.eyeproxy.har`가 있는지 확인. HAR `log.creator.version`은 머지 뒤 1.0.0으로 나간다.

## 5. 다음 묶음 메모

1. **Open Recent + 한 창 안의 세션 탭 여러 개.**
2. 그다음 **호스트 그룹 탭**: 사내 도메인을 묶어 SSL Proxying을 한 번에 켜고 그 요청만 보는 탭, 원하는 도메인만 모은 탭.
- 스펙 §12대로 보기 상태(선택·정렬·필터·Auto Select)는 아직 `AppModel`에 있다. 세션 탭을 만들 때 탭별로 옮긴다(이번에 옮기면 선택·정렬 구조를 두 번 뜯게 되어 미뤘다). 세션에 속하는 데이터(Highlight·코멘트·번호)는 이미 `SessionStore`에 있고, Export API가 `[ExportItem]`을 받아 탭별 내보내기도 그대로 된다.
- HAR 클라이언트 이름 복원과 가져온 흐름의 사이드바 묶기도 이때.
- 기기(Apple TV·iPhone) 요청의 앱별 묶기는 별도 조사 문서가 있다(이 묶음 범위 밖).
- CLI·MCP는 `FlowExport.har`/`csv`, `FlowImport.har`를 그대로 부른다.
