import AppKit

/// 상태 막대 아이콘 상태. 눈 = 서버·기록 상태, 빨간 점 = 손볼 일 있음.
struct StatusIcon: Equatable {
    enum Eyes { case open, closed, stopped }
    var eyes: Eyes
    var needsAttention: Bool

    var accessibilityLabel: String {
        let state = switch eyes {
        case .open: "기록 중"
        case .closed: "일시정지"
        case .stopped: "서버 중지"
        }
        return "Prog — \(state)" + (needsAttention ? ", 확인 필요" : "")
    }
}

enum StatusIconImage {
    /// 점이 없으면 템플릿 에셋 그대로(시스템이 막대 외관에 맞춰 칠한다).
    /// 점이 있으면 템플릿이 될 수 없으므로 눈을 라벨 색으로 직접 칠하고 오른쪽 위에 빨간 점을 얹는다.
    /// 그리기 핸들러는 그릴 때마다(cacheMode = .never) 현재 그리기 외관을 보고 색을 골라서,
    /// 막대가 라이트·다크로 바뀌면 다시 그릴 때 눈 색이 따라간다.
    static func make(_ icon: StatusIcon) -> NSImage {
        let name = switch icon.eyes {
        case .open: "MenuBarEyesOpen"
        case .closed: "MenuBarEyesClosed"
        case .stopped: "MenuBarEyesStopped"
        }
        guard let eyes = NSImage(named: name) else { return NSImage() }
        guard icon.needsAttention else { return eyes }
        let image = NSImage(size: eyes.size, flipped: false) { rect in
            eyes.draw(in: rect)
            // labelColor(85% 불투명)는 막대의 템플릿 아이콘보다 흐려 보여서 불투명 흑·백을 고른다.
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            (dark ? NSColor.white : NSColor.black).set()
            rect.fill(using: .sourceAtop)
            // 지름 6pt 점, 둘레 1pt는 눈을 비워 점이 눈과 붙어 보이지 않게 한다.
            let dot = NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        image.cacheMode = .never
        return image
    }
}
