import AppKit
import SwiftUI

/// 읽기 전용·선택 가능한 모노 텍스트(줄번호·줄바꿈 토글). `text`는 인스턴스가 바뀔 때만 다시 넣는다.
///
/// 줄번호는 NSRulerView를 쓰지 않고 텍스트 뷰 왼쪽 여백에 직접 그린다. macOS 26에서 세로 ruler에
/// 스크롤 가장자리 덮개(NSBannerView)가 붙어 본문과 그 위 툴바까지 가려 보이지 않았다.
struct CodeTextView: NSViewRepresentable {
    let text: NSAttributedString
    let wrap: Bool

    static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    /// 기본 글꼴·색만 입힌 문자열 (글꼴 속성이 없으면 Helvetica로 그려진다).
    static func base(_ s: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor.textColor])
    }

    final class Coordinator {
        var text: NSAttributedString?
        var wrap: Bool?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = GutterTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.usesFontPanel = false
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
        if c.text !== text {
            c.text = text
            tv.textStorage?.setAttributedString(text)
            tv.reloadLineStarts()
        }
    }
}

/// 왼쪽 여백(gutter)에 줄번호를 그리는 텍스트 뷰. 줄을 시작하는 조각에만 번호를 그려 줄바꿈된 이어짐 조각은 비운다.
final class GutterTextView: NSTextView {
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let pad: CGFloat = 8
    private var lineStarts = [0]  // 각 줄 첫 글자의 UTF-16 인덱스
    private var gutter: CGFloat = 28

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

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let gutterRect = NSRect(x: 0, y: rect.minY, width: gutter, height: rect.height)
        guard gutterRect.intersects(rect), let lm = layoutManager, let tc = textContainer else { return }
        NSColor.windowBackgroundColor.setFill()
        gutterRect.fill()

        let attrs: [NSAttributedString.Key: Any] = [.font: Self.numberFont, .foregroundColor: NSColor.secondaryLabelColor]
        let origin = textContainerOrigin
        let visible = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = lm.glyphRange(forBoundingRect: NSRect(x: 0, y: visible.minY, width: tc.size.width, height: visible.height), in: tc)
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
