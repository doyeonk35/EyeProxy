import AppKit
import SwiftUI

/// 상세 창의 SwiftUI 보기(헤더·쿼리·쿠키 표, JSON 트리)가 포커스를 가질 때 ⌘F·⌘G를 받는 동작.
/// 비교는 보기 인스턴스 `id`와 `step` 유무만 — 클로저는 매 갱신 새로 만들어지므로, 같은 보기면 같은 값으로 보아
/// 마우스 움직임·키 입력마다 포커스 값이 다시 퍼져 Find 메뉴가 새로 그려지지 않게 한다.
/// 클로저는 보기의 @State 저장소를 가리키므로 처음 값의 것을 계속 써도 최신 상태에 작용한다.
struct DetailFind: Equatable {
    let id: UUID
    let open: @MainActor () -> Void
    /// 다음(+1)·이전(-1) 일치. 없으면 ⌘G는 그냥 지나간다.
    var step: (@MainActor (Int) -> Void)?

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && (a.step == nil) == (b.step == nil) }
}

extension FocusedValues {
    @Entry var detailFind: DetailFind?
    /// 메인 창 필터 막대를 보이고 현재 규칙 검색칸에 포커스를 주는 동작(`open`).
    @Entry var flowSearch: DetailFind?
    /// 사이드바(목록·필터 칸)에 포커스가 있을 때 사이드바 필터 칸에 포커스를 주는 동작. ⇧⌘F는 그때만 켜진다.
    @Entry var sidebarFilter: DetailFind?
}

/// Edit ▸ Find. SwiftUI `Window` 장면은 Find 항목을 넣지 않아 직접 둔다(⌘F 단축키는 여기 하나뿐).
/// 라우팅: ① 본문·Raw 텍스트 뷰가 응답자면 내장 찾기 막대(NSTextFinder) ② 표·트리가 포커스면 그 막대
/// ③ 메인 창(시트 아님)의 목록·사이드바면 필터 막대 ④ 그 밖은 표준 응답자 체인.
/// 필터 막대 단축키(⌘N·⇧⌘N·⌘↑·⌘↓·⌘B)는 막대 안에, ⇧⌘F는 사이드바에 포커스가 있을 때만 켜진다 — 다른 곳의 같은 키를 빼앗지 않는다.
struct FindCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .pasteboard) { FindMenu() }
    }
}

private struct FindMenu: View {
    @FocusedValue(\.detailFind) private var detail
    @FocusedValue(\.flowSearch) private var flowSearch
    @FocusedValue(\.filterBar) private var filterBar
    @FocusedValue(\.sidebarFilter) private var sidebarFilter

    var body: some View {
        Divider()
        Menu("Find") {
            Button("Find…") { find() }
                .keyboardShortcut("f")
                .help("포커스된 보기에서 찾기·거르기, 목록이면 필터 막대 (⌘F)")
            Button("Find Next") { step(1) }
                .keyboardShortcut("g")
                .help("다음 일치 (⌘G)")
            Button("Find Previous") { step(-1) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help("이전 일치 (⇧⌘G)")
            Button("Filter Sidebar") { sidebarFilter?.open() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(sidebarFilter == nil)
                .help("사이드바 필터 칸으로 (⇧⌘F, 사이드바에 포커스가 있을 때)")
            Divider()
            filterItem("New Filter", .add, "n", help: "필터 막대에 규칙 추가 (⌘N)")
            filterItem("Remove Filter", .remove, "n", [.command, .shift], help: "필터 막대의 이 규칙 지우기 (⇧⌘N)")
            filterItem("Previous Filter", .up, .upArrow, help: "필터 막대 위 규칙으로 (⌘↑)")
            filterItem("Next Filter", .down, .downArrow, help: "필터 막대 아래 규칙으로 (⌘↓)")
            filterItem("Toggle Filter", .toggle, "b", help: "필터 막대의 이 규칙 켜기·끄기 (⌘B)")
        }
    }

    private func filterItem(_ title: LocalizedStringKey, _ command: FilterBarCommand, _ key: KeyEquivalent,
                            _ modifiers: EventModifiers = .command, help: LocalizedStringKey) -> some View {
        Button(title) { filterBar?.perform(command) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(filterBar == nil)
            .help(help)
    }

    private func find() {
        if textFinder(.showFindInterface) { return }
        if let detail { detail.open(); return }
        // 필터 막대는 목록·사이드바(표 보기)나 아무것도 포커스가 없을 때만. 찾기 막대에 입력 중(필드 편집기)이거나
        // 상세의 값 글자를 골라 둔 상태면 표준 체인에 맡겨 포커스를 빼앗지 않는다.
        let responder = NSApp.keyWindow?.firstResponder
        let listArea = responder == nil || responder is NSTableView || responder is NSWindow
        if let flowSearch, listArea, NSApp.keyWindow?.sheetParent == nil { flowSearch.open(); return }
        sendTextFinder(.showFindInterface)
    }

    private func step(_ d: Int) {
        let action: NSTextFinder.Action = d > 0 ? .nextMatch : .previousMatch
        if textFinder(action) { return }
        if let s = detail?.step { s(d); return }
        // 찾기 막대 검색칸(필드 편집기)에 있을 때 등은 표준 응답자 체인이 처리한다. 받는 쪽이 없으면 아무 일도 없다.
        sendTextFinder(action)
    }

    /// 응답자가 찾기 막대를 쓰는 텍스트 뷰(필드 편집기 아님)면 그 뷰에 보낸다.
    private func textFinder(_ action: NSTextFinder.Action) -> Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView, !tv.isFieldEditor, tv.usesFindBar else { return false }
        tv.performTextFinderAction(Self.item(action))
        return true
    }

    private func sendTextFinder(_ action: NSTextFinder.Action) {
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: Self.item(action))
    }

    /// `performTextFinderAction(_:)`은 보낸 쪽의 `tag`로 동작을 고른다.
    private static func item(_ action: NSTextFinder.Action) -> NSMenuItem {
        let item = NSMenuItem()
        item.tag = action.rawValue
        return item
    }
}
