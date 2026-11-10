import AppKit
import SwiftUI

/// 상세 창의 SwiftUI 보기(헤더·쿼리·쿠키 표, JSON 트리)가 포커스를 가질 때 ⌘F·⌘G를 받는 동작.
struct DetailFind {
    let open: @MainActor () -> Void
    /// 다음(+1)·이전(-1) 일치. 없으면 ⌘G는 그냥 지나간다.
    var step: (@MainActor (Int) -> Void)?
}

extension FocusedValues {
    @Entry var detailFind: DetailFind?
    /// 메인 창 툴바 검색칸(목록 거르기)에 포커스를 주는 동작(`open`).
    @Entry var flowSearch: DetailFind?
}

/// Edit ▸ Find. SwiftUI `Window` 장면은 Find 항목을 넣지 않아 직접 둔다(⌘F 단축키는 여기 하나뿐).
/// 라우팅: ① 본문·Raw 텍스트 뷰가 응답자면 내장 찾기 막대(NSTextFinder) ② 표·트리가 포커스면 그 막대
/// ③ 메인 창(시트 아님)이면 툴바 검색칸 ④ 그 밖은 표준 응답자 체인.
struct FindCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .pasteboard) { FindMenu() }
    }
}

private struct FindMenu: View {
    @FocusedValue(\.detailFind) private var detail
    @FocusedValue(\.flowSearch) private var flowSearch

    var body: some View {
        Divider()
        Menu("Find") {
            Button("Find…") { find() }
                .keyboardShortcut("f")
                .help("포커스된 보기에서 찾기·거르기, 목록이면 검색칸 (⌘F)")
            Button("Find Next") { step(1) }
                .keyboardShortcut("g")
                .help("다음 일치 (⌘G)")
            Button("Find Previous") { step(-1) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help("이전 일치 (⇧⌘G)")
        }
    }

    private func find() {
        if textFinder(.showFindInterface) { return }
        if let detail { detail.open(); return }
        if let flowSearch, NSApp.keyWindow?.sheetParent == nil { flowSearch.open(); return }
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
