import AppKit
import SwiftUI

/// 선택 가능한 모노 텍스트(줄번호·줄바꿈 토글). `text`는 인스턴스가 바뀔 때만 다시 넣는다.
/// `isEditable`이면 일반 텍스트로 편집되고 글자마다 `onChange`가 불린다. 이때 같은 문자열의 새 `text`는
/// 색(속성)만 입혀 커서·되돌리기를 건드리지 않는다.
///
/// 줄번호는 NSRulerView를 쓰지 않고 텍스트 뷰 왼쪽 여백에 직접 그린다. macOS 26에서 세로 ruler에
/// 스크롤 가장자리 덮개(NSBannerView)가 붙어 본문과 그 위 툴바까지 가려 보이지 않았다.
struct CodeTextView: NSViewRepresentable {
    let text: NSAttributedString
    let wrap: Bool
    var isEditable = false
    /// 상세 본문은 Appearance ▸ Font Size를 넘긴다. nil이면 `font`(편집기 등) 그대로.
    var fontSize: CGFloat?
    /// Appearance ▸ Show Invisibles: 공백 `·`, 탭 `→`, 줄바꿈 `¬`.
    var showInvisibles = false
    var onChange: ((String) -> Void)?

    static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    /// 기본 글꼴·색만 입힌 문자열 (글꼴 속성이 없으면 Helvetica로 그려진다).
    static func base(_ s: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor.textColor])
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: NSAttributedString?
        var wrap: Bool?
        var fontSize: CGFloat?
        var onChange: ((String) -> Void)?

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? GutterTextView else { return }
            tv.reloadLineStarts()
            onChange?(tv.string)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = GutterTextView()
        tv.isEditable = isEditable
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = isEditable
        tv.usesFontPanel = false
        // ⌘F·⌘G: 내장 찾기 막대(일치 모두 강조·개수·대소문자 옵션). 막대는 감싼 NSScrollView 위에 붙는다.
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        // JSON·헤더를 고치므로 따옴표·대시 자동 치환과 맞춤법 교정을 끈다.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.typingAttributes = [.font: Self.font, .foregroundColor: NSColor.textColor]
        tv.delegate = context.coordinator
        tv.font = Self.font
        tv.textColor = .textColor
        tv.backgroundColor = .textBackgroundColor
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.minSize = .zero
        tv.layoutManager?.allowsNonContiguousLayout = true

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? GutterTextView, let tc = tv.textContainer else { return }
        let c = context.coordinator
        c.onChange = onChange
        tv.isEditable = isEditable
        tv.allowsUndo = isEditable
        tv.showsInvisibles = showInvisibles
        if c.wrap != wrap {
            c.wrap = wrap
            let big = CGFloat.greatestFiniteMagnitude
            tc.widthTracksTextView = wrap
            tv.isHorizontallyResizable = !wrap
            tv.maxSize = NSSize(width: big, height: big)
            scroll.hasHorizontalScroller = !wrap
            if wrap {
                tv.setFrameSize(NSSize(width: scroll.contentSize.width, height: tv.frame.height))
            } else {
                tc.containerSize = NSSize(width: big, height: big)
            }
        }
        let textChanged = c.text !== text
        if textChanged, let storage = tv.textStorage {
            c.text = text
            if isEditable, storage.string == text.string {
                recolor(storage, from: text)
            } else {
                storage.setAttributedString(text)
                tv.reloadLineStarts()
            }
        }
        // 본문 문자열은 `base`의 고정 크기로 만들어지므로 넣은 뒤 글꼴 크기만 바꾼다(전체가 같은 모노 글꼴).
        if let fontSize, textChanged || c.fontSize != fontSize {
            c.fontSize = fontSize
            tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)   // 글자 전체에 적용된다
        }
    }

    /// 글자는 그대로 두고 글자색만 `text`의 것으로 바꾼다.
    private func recolor(_ storage: NSTextStorage, from text: NSAttributedString) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: full)
        text.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if let value { storage.addAttribute(.foregroundColor, value: value, range: range) }
        }
        storage.endEditing()
    }
}

/// 왼쪽 여백(gutter)에 줄번호를 그리는 텍스트 뷰. 줄을 시작하는 조각에만 번호를 그려 줄바꿈된 이어짐 조각은 비운다.
final class GutterTextView: NSTextView {
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let pad: CGFloat = 8
    private static let invisibleMarks: [UInt16: NSString] = [32: "·", 9: "→", 10: "¬"]
    private var lineStarts = [0]  // 각 줄 첫 글자의 UTF-16 인덱스
    private var gutter: CGFloat = 28
    var showsInvisibles = false { didSet { if showsInvisibles != oldValue { needsDisplay = true } } }

    /// 텍스트가 바뀐 뒤 호출: 줄 시작 위치와 여백 폭을 다시 계산한다.
    func reloadLineStarts() {
        var starts = [0]
        var i = 0
        for u in string.utf16 {
            i += 1
            if u == 10 { starts.append(i) }
        }
        lineStarts = starts
        gutter = CGFloat(max(2, String(starts.count).count) * 8 + 12)
        // 좌우 여백 합 = gutter + 2·pad. 왼쪽은 textContainerOrigin에서 gutter + pad로 민다.
        textContainerInset = NSSize(width: (gutter + 2 * Self.pad) / 2, height: 6)
        needsDisplay = true
    }

    override var textContainerOrigin: NSPoint {
        NSPoint(x: gutter + Self.pad, y: textContainerInset.height)
    }

    /// 보이는 글리프 범위의 공백·탭·줄바꿈 자리에 흐린 기호를 그린다(글자는 그 위에 그려지고 이 자리는 비어 있다).
    private func drawInvisibles(_ lm: NSLayoutManager, _ glyphs: NSRange, _ origin: NSPoint) {
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let text = string as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? CodeTextView.font, .foregroundColor: NSColor.tertiaryLabelColor]
        for i in chars.location..<NSMaxRange(chars) {
            guard let mark = Self.invisibleMarks[text.character(at: i)] else { continue }
            let glyph = lm.glyphIndexForCharacter(at: i)
            let line = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let x = lm.location(forGlyphAt: glyph).x
            mark.draw(at: NSPoint(x: origin.x + line.minX + x, y: origin.y + line.minY), withAttributes: attrs)
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer else { return }
        let origin = textContainerOrigin
        let visible = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = lm.glyphRange(forBoundingRect: NSRect(x: 0, y: visible.minY, width: tc.size.width, height: visible.height), in: tc)
        // 가로로도 보이는 부분만(줄바꿈 끈 한 줄짜리 큰 본문에서 줄 전체를 돌지 않게).
        if showsInvisibles { drawInvisibles(lm, lm.glyphRange(forBoundingRect: visible, in: tc), origin) }

        let gutterRect = NSRect(x: 0, y: rect.minY, width: gutter, height: rect.height)
        guard gutterRect.intersects(rect) else { return }
        NSColor.windowBackgroundColor.setFill()
        gutterRect.fill()

        let attrs: [NSAttributedString.Key: Any] = [.font: Self.numberFont, .foregroundColor: NSColor.secondaryLabelColor]
        lm.enumerateLineFragments(forGlyphRange: glyphs) { frag, _, _, range, _ in
            let ch = lm.characterIndexForGlyph(at: range.location)
            // ch 이하인 줄 시작의 개수 = 줄 번호
            var lo = 0, hi = self.lineStarts.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if self.lineStarts[mid] <= ch { lo = mid + 1 } else { hi = mid }
            }
            guard lo > 0, self.lineStarts[lo - 1] == ch else { return }
            let label = String(lo) as NSString
            let size = label.size(withAttributes: attrs)
            let y = frag.minY + origin.y + (frag.height - size.height) / 2
            label.draw(at: NSPoint(x: self.gutter - 6 - size.width, y: y), withAttributes: attrs)
        }
    }
}
