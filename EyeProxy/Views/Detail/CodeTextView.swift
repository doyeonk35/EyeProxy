import AppKit
import SwiftUI

/// 읽기 전용·선택 가능한 모노 텍스트(줄번호·줄바꿈 토글). `text`는 인스턴스가 바뀔 때만 다시 넣는다.
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
        var observers: [NSObjectProtocol] = []
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.usesFontPanel = false
        tv.font = Self.font
        tv.textColor = .textColor
        tv.backgroundColor = .textBackgroundColor
        tv.textContainerInset = NSSize(width: 8, height: 6)
        // 줄번호 ruler가 NSLayoutManager를 쓰므로 텍스트를 넣기 전에 TextKit 1로 고정한다.
        tv.layoutManager?.allowsNonContiguousLayout = true

        let ruler = LineNumberRuler(textView: tv)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.contentView.postsBoundsChangedNotifications = true
        let redraw: @Sendable (Notification) -> Void = { [weak ruler] _ in
            MainActor.assumeIsolated { ruler?.needsDisplay = true }
        }
        let nc = NotificationCenter.default
        context.coordinator.observers = [
            nc.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main, using: redraw),
            nc.addObserver(forName: NSView.frameDidChangeNotification, object: tv, queue: .main, using: redraw),
        ]
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, let tc = tv.textContainer else { return }
        let c = context.coordinator
        if c.wrap != wrap {
            c.wrap = wrap
            tc.widthTracksTextView = wrap
            tv.isHorizontallyResizable = !wrap
            scroll.hasHorizontalScroller = !wrap
            let big = CGFloat.greatestFiniteMagnitude
            if wrap {
                tc.containerSize = NSSize(width: scroll.contentSize.width, height: big)
                tv.setFrameSize(NSSize(width: scroll.contentSize.width, height: tv.frame.height))
            } else {
                tc.containerSize = NSSize(width: big, height: big)
                tv.maxSize = NSSize(width: big, height: big)
            }
        }
        if c.text !== text {
            c.text = text
            tv.textStorage?.setAttributedString(text)
            (scroll.verticalRulerView as? LineNumberRuler)?.reload()
        }
    }
}

/// `CodeTextView` 전용 줄번호. 줄을 시작하는 조각에만 번호를 그려 줄바꿈된 이어짐 조각은 비운다.
final class LineNumberRuler: NSRulerView {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private var lineStarts = [0]  // 각 줄 첫 글자의 UTF-16 인덱스

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        reload()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 텍스트가 바뀐 뒤 호출: 줄 시작 위치와 두께를 다시 계산한다.
    func reload() {
        var starts = [0]
        if let s = (clientView as? NSTextView)?.string {
            var i = 0
            for u in s.utf16 {
                i += 1
                if u == 10 { starts.append(i) }
            }
        }
        lineStarts = starts
        ruleThickness = CGFloat(max(2, String(starts.count).count) * 8 + 12)
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        rect.fill()
        guard let tv = clientView as? NSTextView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor]
        let origin = tv.textContainerOrigin
        let visible = tv.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
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
            let y = self.convert(NSPoint(x: 0, y: frag.minY + origin.y), from: tv).y
            label.draw(at: NSPoint(x: self.ruleThickness - 6 - size.width, y: y + (frag.height - size.height) / 2), withAttributes: attrs)
        }
    }
}
