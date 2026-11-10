# Prog 요청·응답 찾기·거르기 핸드오버 (2026-11-10)

플랜: `2026-11-10-prog-find-filter.md`(설계 절이 스펙) · 브랜치: `find-filter`(base `3b93fac`)
상태: Task 1~4 구현·리뷰 완료. 아래 2장의 **미확인** 항목은 사람이 확인한다(실제 키보드, 한글 입력, 시트·도구 창, 라이트 외관, 큰 JSON, VoiceOver).
테스트: `swift test --package-path Packages/EyeProxyKit`(Kit 330개 — 최종 리뷰에서 `arrayIndexKeysAreNotMatched` 추가).

## 1. 무엇이 들어갔나

상세 창 요청·응답 패널에서 ⌘F로 찾기·거르기를 하고, JSON 트리를 버튼 하나로 모두 펼치고 접는다. 이전에는 Edit 메뉴에 Find 항목이 없어 ⌘F가 아무 일도 하지 않았다. 이번에 Edit ▸ Find ▸ Find…(⌘F)·Find Next(⌘G)·Find Previous(⇧⌘G)를 새로 넣었다. 사용자 설명은 README의 상세 탭 › 찾기·거르기(⌘F)와 알려진 제한(찾기·거르기) 절.

| Task | 내용 | 커밋 |
|---|---|---|
| 0 | 플랜(설계: Proxyman 문서 조사, 범위 밖 목록). | `9601210` |
| 1 | Kit: `JSONTreeSearch` — `matches`·`ancestors`·`filter`·`containerIDs`. 전위 순회, 재귀 없음, 대소문자 무시. 객체·배열은 키로만 일치. 테스트 7개. | `322d02c` |
| 2 | 앱: JSON 트리를 평탄화한 행 `List`로 다시 쓰고(깊이 512도 보기 깊이 일정), Tree 모드 막대에 모두 펼치기·모두 접기·찾기 버튼, 찾기 막대(Search·Filter, i / N, Enter/⇧Enter, Esc). 수정: 빠른 입력 시 한 글자 늦은 결과, 행 화살표 클릭. | `c0a6309` |
| 3 | 앱: Edit ▸ Find 메뉴와 ⌘F 라우팅(텍스트 뷰 → 표·트리 → 목록·사이드바면 툴바 검색칸 → 표준 체인), 본문·Raw `NSTextView` 내장 찾기 막대, 헤더·쿼리·쿠키·요약 표 거르기("N / 전체 M"), 트리 막대 ⌘F 재포커스·⌘G/⇧⌘G·막대 밖 Esc·"일치 없음"·들여쓰기 상한 32·접근성 라벨. | `c25b089` |
| 3 수정 | 찾기 막대 입력 중 ⌘F가 툴바 검색칸으로 튀던 것(목록·사이드바·포커스 없음일 때만 검색칸으로), `DetailFind` Equatable(메뉴 재구성 방지), 표 탭 제스처 제거(값 더블클릭 선택·⌘C 회복), 요약 표 흐름 바뀌면 초기화, 표 검색칸 포커스 지연. | `b1a1fcc` |
| 4 | README와 이 문서. | `acc9357` |
| 최종 리뷰 | 배열 원소 인덱스 키는 검색 제외(Kit), M3U8 표 ⌘F가 툴바로 가지 않게, Esc·✕ 뒤 표·트리로 포커스 복귀(다음 ⌘F가 같은 막대), 트리 보이는 행·일치 집합 캐시, Filter에서 일치 중복 계산 제거, 표 행·강조를 원래 인덱스로. | `2242f27` |
| 최종 리뷰 문서 | README 찾기 막대 범위(일반 텍스트·HTML 소스·편집 보기의 Replace), 이 점검표. | 이 커밋 |

## 2. 수동 점검표

근거의 파일 이름은 구현 세션 scratchpad의 `ff-task2/`·`ff-task3/` 폴더 스크린샷이다(커밋하지 않음). "리포트"는 Task 리포트에 확인 기록만 있고 스크린샷은 없다는 뜻, "코드 확인"은 코드를 읽어 확인했고 실제 화면은 보지 않았다는 뜻이다. 자동 확인은 자기 Debug 빌드(포트 19090, 다크 외관은 실행 인자로만)에서 모달을 열지 않고 했다.

| 항목 | 방법 | 상태 | 근거 |
|---|---|---|---|
| 변경 전 기준 | 목록 포커스에서 ⌘F → 아무 일 없음(Find 메뉴 없음) | 확인됨 | `ff-task3/00-baseline-list-cmdF.png` |
| 목록 ⌘F → 툴바 검색칸 | 목록 클릭 → ⌘F | 확인됨 | `ff-task3/1-list-cmdF-toolbar-search.png` |
| 사이드바 ⌘F → 툴바 검색칸 | 사이드바 클릭 → ⌘F | 확인됨 | 리포트(AX 포커스 확인) |
| 툴바 검색칸에서 ⌘G·⇧⌘G | 검색칸에 "nest" 입력 → ⌘G·⇧⌘G → 글자 그대로 | 확인됨 | `ff-task3/1b-toolbar-search-cmdG-ok.png` |
| 본문 Pretty 찾기 | 본문 클릭 → ⌘F → "user" → ⌘G 두 번 | 확인됨 | `ff-task3/3-body-pretty-find.png` |
| Raw 탭 찾기 | Raw 탭 클릭 → ⌘F → "content" | 확인됨 | `ff-task3/4-raw-tab-find.png` |
| 찾기 막대 입력 중 ⌘F | 본문 찾기 막대에 "beta" → ⌘F 다시 → 막대에 머묾, 툴바 검색칸 포커스 안 됨 | 확인됨 | `ff-task3/9-pretty-bar-cmdF-again.png`, `ff-task3/9-toolbar-crop.png` |
| 찾기 막대 안 ⌘G | 막대 검색칸에서 ⌘G → 다음 일치 | 확인됨 | 리포트 |
| 헤더 표 거르기 | 이름 열 클릭 → ⌘F → "content" → `2 / 전체 5` | 확인됨 | `ff-task3/2-header-filter.png` |
| 표 거르기 Esc | 거르는 중 Esc → 칸 닫힘, 전체 행 | 확인됨 | `ff-task3/2b-header-esc.png` |
| 이름 열 클릭 후 ⌘F | 목록 포커스에서 이름 열 클릭 → ⌘F → 표 거르기(3회 중 3회) | 확인됨 | 리포트 |
| 값 글자 클릭 후 ⌘F | 값 글자 클릭 → ⌘F → 아무 일 없음(툴바로 튀지 않음) | 확인됨 | 리포트(AX: StaticText) — 알려진 제한 |
| 값 더블클릭 선택·⌘C | 값 단어 더블클릭 → ⌘C → `application` 복사 | 확인됨 | `ff-task3/10-table-dblclick-select.png` |
| 거른 행 우클릭 복사 | 거르는 중 행 우클릭 ▸ 값 복사 / 이름: 값 복사 | 확인됨 | `ff-task3/7-filter-context-menu.png`, `ff-task3/11-filter-context-menu-fix.png` |
| 흐름 바꾸면 표 거르기 닫힘 | 흐름 1에서 거르기 → 흐름 2 선택 | 확인됨 | `ff-task3/6a-filter-flow1.png`, `ff-task3/6b-after-flow-change.png` |
| 요약 표 거르기·초기화 | 요약 펼치기 → ⌘F → "bytes" → 흐름 바꿈 | 확인됨 | `ff-task3/12a-summary-filter.png`, `ff-task3/12b-summary-after-flow-change.png` |
| 쿼리·쿠키 표 거르기 | 쿼리·쿠키가 있는 흐름에서 ⌘F | 미확인 | 코드 확인(헤더와 같은 `KeyValueTable`, `.id(flowID)`) |
| 트리 처음 접힘 | Tree 모드로 바꿈 | 확인됨 | `ff-task2/1-collapsed.png` |
| 모두 펼치기 | 모두 펼치기 버튼 | 확인됨 | `ff-task2/2-expanded.png` |
| 모두 접기 | 펼친 뒤 모두 접기 버튼 | 미확인 | 코드 확인(`treeExpanded = []`) |
| 행 화살표 | 행 화살표 클릭으로 하나씩 펼침·접힘 | 확인됨 | `ff-task2/6-chevron.png` |
| 트리 Search | 접힌 상태에서 "0" → 일치 강조, 조상 펼침, `3 / 54`. 최종 리뷰 뒤 배열 인덱스 키를 빼서 같은 "0"이 `1 / 28` | 확인됨 | `ff-task2/3-search.png`, `ff-final/2-tree-search-0-no-index-keys.png` |
| 트리 Search 스크롤 | "true" → `2 / 6`, 현재 일치로 스크롤 | 확인됨 | `ff-task2/3b-search-others.png` |
| Enter / ⇧Enter | 검색칸에서 Enter 다음, ⇧Enter 이전 | 확인됨 | 리포트 |
| 빠른 입력 결과 | "email"을 빠르게 입력 → `1 / 12`(수정 전 한 글자 늦음) | 확인됨 | 리포트, 수정 전 `ff-task2/0-bug-stale-query-before-fix.png` |
| 트리 Filter | "admin" → `3개 일치`, 일치와 조상만, 모두 펼침 | 확인됨 | `ff-task2/4-filter.png` |
| 트리 Filter 0개 | "zzz" → `0개 일치` + 가운데 "일치 없음" | 확인됨 | `ff-task3/8-tree-filter-no-match.png` |
| 트리 ⌘F·⌘G | 트리 행 클릭 → ⌘F(검색칸 포커스) → ⌘G → `2 / 3` | 확인됨 | `ff-task3/5-tree-cmdF-cmdG.png` |
| 막대 열린 채 ⌘F | 트리 행 클릭 → ⌘F → 검색칸으로 포커스 | 확인됨 | 리포트 |
| 트리 Esc 복원 | 검색칸·트리 행 포커스에서 Esc → 막대 닫힘, 열기 전 펼침 상태 | 확인됨 | `ff-task2/5-closed-restored.png`, `ff-task3/5b-tree-esc-from-list.png` |
| 실제 키보드 ⇧⌘G | 하드웨어 키보드로 ⇧⌘G(자동 확인의 HID 키 입력은 앱에 닿지 않았고, 앱 PID로 직접 보낸 이벤트는 `3/3 → 2/3`로 동작 — 전역 단축키 의심) | 미확인 | 리포트, 메뉴 항목 AX 확인 |
| 한글 검색어(IME) | 트리·표·본문 찾기에 한글을 실제 입력기로 입력(예: 키·값의 한글) | 미확인 | Kit 테스트(`searchIsCaseInsensitiveAndMatchesKoreanKeysAndValues`) |
| Compose·Breakpoint 편집기 ⌘F | 편집기 본문 클릭 → ⌘F → 내장 찾기 막대 | Compose 확인됨, Breakpoint·Map Local 미확인 | `ff-final/8-compose-raw-find.png`, 나머지는 코드 확인(같은 `NSTextView` 경로) |
| 코멘트 시트 ⌘F | Add Comment… 시트에서 ⌘F → 뒤의 툴바 검색칸으로 가지 않음 | 미확인 | 코드 확인(`sheetParent == nil`) |
| 라이트 외관 | 시스템 라이트에서 트리 강조색·옅은 노랑, 표·트리 막대 | 미확인 | 스크린샷은 모두 다크 |
| 2 MB JSON 모두 펼치기 | 2.05 MB·15만 노드 응답 → Tree → 모두 펼치기 → Filter에 "ad" 두 글자(Debug 빌드). 펼치기는 바로, 첫 글자 ≈0.3초 멈칫, 둘째 글자 ≈0.05초(AX 왕복 0.39초를 뺀 값) | 확인됨 | `ff-final/6b-big-tree-expanded.png`, `ff-final/7-big-filter-ad.png` |
| Esc 후 ⌘F | 표: 거르기 열기 → Esc(또는 ✕) → ⌘F → 같은 칸이 다시 열림. 트리: 막대 → Esc → 트리에 포커스 → ⌘F → 막대 다시 열림 | 확인됨 | `ff-final/1-table-esc-then-cmdF.png`, `ff-final/3-tree-esc-then-cmdF.png` |
| M3U8 표 ⌘F | M3U8 탭 표 행 클릭 → ⌘F → 포커스가 표에 머묾(툴바 검색칸으로 가지 않음) | 확인됨 | `ff-final/5-m3u8-table-cmdF.png`(AX 포커스 확인) |
| 일반 텍스트 본문 찾기 | M3U8 응답 본문 탭(일반 텍스트) → ⌘F → "index" 2개 | 확인됨 | `ff-final/4-plain-text-body-find.png` |
| 편집 보기에서 바꾸기 | Compose Raw 편집기 → ⌘F → 막대에 Replace 체크 | 확인됨 | `ff-final/8-compose-raw-find.png` (바꾸기 실행은 미확인) |
| VoiceOver 라벨 | 모두 펼치기·모두 접기·찾기, 이전 일치·다음 일치·닫기, 행 화살표 펼치기/접기 | 미확인 | 코드 확인(`Label`·`accessibilityLabel`) |
| 트리 행 글자 선택 | 트리 행 글자 드래그 선택·복사 | 미확인 | 코드 확인(`.textSelection(.enabled)`) |
| macOS 15 | 개발 Mac(최신 macOS) 밖에서 찾기 막대·라우팅 | 미확인 | - |

집계: 확인됨 33 / 부분 확인 1 / 미확인 9.

## 3. 보류·결정 요약

**구현 중 결정(ruling)**
- 목록·사이드바 ⌘F → 툴바 검색칸은 "지금처럼"이 아니라 새 동작이다(이전엔 ⌘F가 아무 일도 안 함). ⌘F·⌘G 단축키는 Edit ▸ Find 하나뿐.
- 툴바 검색칸으로 가는 조건은 응답자가 없음·`NSTableView`(목록·사이드바)·창 자체일 때만(긍정 조건). 찾기 막대 입력 중이나 값 글자 선택 상태에서 포커스를 빼앗지 않는다.
- 트리는 재귀 `DisclosureGroup`/`OutlineGroup` 대신 평탄화한 행 `List`(깊이 512, 수천 노드 대응, `scrollTo` 바로 사용).
- 객체·배열은 키로만 일치(미리보기 `{3 keys}`가 "keys"·숫자에 다 걸리지 않게).
- 표 클릭 포커스는 `focusable`만. 탭 제스처는 값 더블클릭 선택·⌘C를 깨서 뺐다. 그래서 값 글자를 클릭하면 ⌘F가 무반응(문서화).
- 요약 표도 같은 컴포넌트라 거르기가 붙었다(그대로 둠, 흐름 바뀌면 초기화).
- 수용: 표·트리 클릭 뒤 ⌫가 목록 삭제를 안 함(Delete는 목록 포커스에 묶임), 열린 막대에서 Esc는 항상 소비, 키보드만으로 표에 가려면 전체 키보드 접근.

**다음으로 미룸**
- 본문 찾기 정규식(내장 막대가 지원 안 함), 트리 JSON Path·jq 모드, 목록 2차 필터(키·매칭 방식 메뉴), 필터 여러 개(⌘N), M3U8 찾기.
- 큰 트리에서 키 입력마다 동기 전체 계산(디바운스·백그라운드 계산). `JSONTreeView.apply`에 `ponytail:` 표시(측정값·올릴 방법)를 남겼다.
- Filter에서 걸러진 객체·배열의 개수 표시(지금은 원래 개수).
- Search 중 손으로 바꾼 펼침이 다음 입력에 덮임(의도, 단순함).
- 일치가 1개일 때 다시 스크롤하기(Task 2 리뷰 minor).
- Kit 깊이 테스트(510단계)는 재귀 회귀를 증명하진 못한다(비재귀는 코드 확인).

## 4. 머지 메모

- 문서·앱·Kit만 바뀌었고 새 패키지·설정 키·세션 파일 형식 변경 없음. `Package.resolved` 변경 없음.
- 머지 전 위 미확인 중 실제 키보드 ⇧⌘G·한글 입력·라이트 외관은 손으로 한 번 보는 것을 권한다.
