// DMG 설치 창 배경(안내 문구 + 화살표)을 그린다. 문구를 바꿀 때만 다시 실행:
//   swift scripts/dmg/make-background.swift scripts/dmg && tiffutil -cathidpicheck scripts/dmg/background.png scripts/dmg/background@2x.png -out scripts/dmg/background.tiff && rm scripts/dmg/background*.png
// 결과: background.tiff (1x + 2x). 아이콘 좌표는 make-dmg.sh 와 맞춰야 한다 (앱 150,200 / Applications 450,200).
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size = NSSize(width: 600, height: 400)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()

    func text(_ s: String, y: CGFloat, size fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                                                    .foregroundColor: color, .paragraphStyle: style]
        NSAttributedString(string: s, attributes: attrs).draw(in: NSRect(x: 20, y: y, width: size.width - 40, height: fontSize * 1.5))
    }
    // AppKit 좌표는 아래가 0 — Finder 아이콘 y=200(위에서)은 여기서 y=200
    text("Prog를 Applications 폴더로 끌어다 놓으세요", y: 330, size: 17, weight: .semibold, color: NSColor(white: 0.12, alpha: 1))
    text("Drag Prog to the Applications folder", y: 306, size: 12, weight: .regular, color: NSColor(white: 0.38, alpha: 1))
    text("이미 설치돼 있으면 \"대치\"를 누르세요. 설정과 루트 인증서는 그대로 유지됩니다.", y: 92, size: 12, weight: .regular, color: NSColor(white: 0.38, alpha: 1))
    text("If asked, choose \"Replace\". Your settings and root certificate are kept.", y: 72, size: 11, weight: .regular, color: NSColor(white: 0.55, alpha: 1))

    // 화살표: 앱 아이콘(150) → Applications(450)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 230, y: 200)); arrow.line(to: NSPoint(x: 362, y: 200))
    arrow.lineWidth = 6; arrow.lineCapStyle = .round
    NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1).setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 372, y: 200)); head.line(to: NSPoint(x: 350, y: 214)); head.line(to: NSPoint(x: 350, y: 186)); head.close()
    NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1).setFill(); head.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(scale: 1).write(to: URL(fileURLWithPath: "\(out)/background.png"))
try! render(scale: 2).write(to: URL(fileURLWithPath: "\(out)/background@2x.png"))
