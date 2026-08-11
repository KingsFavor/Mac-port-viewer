import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// DMG 설치 창 배경 이미지 생성기. (물고기 테마 + Applications 로 드래그 안내)
// 창 크기 640x400 pt 기준으로 그린다. 앱/Applications 아이콘은 Finder 가 그리므로
// 여기서는 배경 · 화살표 · 안내 문구만 그린다.
// 사용법: swift Tools/GenerateDMGBackground.swift <출력.png> <배율(1|2)>

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: a)
}

func drawBackground(into ctx: CGContext, scale: CGFloat) {
    let H: CGFloat = 400
    ctx.scaleBy(x: scale, y: scale)

    // 배경 그라디언트 (은은한 바다색)
    let space = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: space,
        colors: [c(226, 245, 254), c(179, 229, 252)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    // 좌표를 화면 기준(y 아래로)으로 뒤집기
    ctx.translateBy(x: 0, y: H)
    ctx.scaleBy(x: 1, y: -1)

    // 물방울 장식
    ctx.setFillColor(c(255, 255, 255, 0.35))
    for (x, y, r) in [(70, 330, 10), (110, 300, 6), (560, 60, 12), (590, 95, 7), (300, 40, 8)] {
        ctx.fillEllipse(in: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(r*2), height: CGFloat(r*2)))
    }

    // 화살표 (앱 아이콘 → Applications) 아이콘은 y≈170(중앙), 좌 150 / 우 490
    ctx.setStrokeColor(c(2, 119, 189, 0.85))
    ctx.setLineWidth(9)
    ctx.setLineCap(.round)
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 250, y: 195))
    arrow.addLine(to: CGPoint(x: 388, y: 195))
    ctx.addPath(arrow)
    ctx.strokePath()
    // 화살촉
    let head = CGMutablePath()
    head.move(to: CGPoint(x: 410, y: 195))
    head.addLine(to: CGPoint(x: 384, y: 179))
    head.addLine(to: CGPoint(x: 384, y: 211))
    head.closeSubpath()
    ctx.addPath(head)
    ctx.setFillColor(c(2, 119, 189, 0.85))
    ctx.fillPath()

    // 텍스트 (Core Text via NSAttributedString)
    func drawText(_ s: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, center: CGPoint) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: color) ?? .black,
        ]
        let str = NSAttributedString(string: s, attributes: attrs)
        let line = str.size()
        // 현재 좌표계는 y 아래로 뒤집힌 상태이므로 그리기 위해 잠시 원복
        ctx.saveGState()
        ctx.translateBy(x: center.x - line.width/2, y: center.y + line.height/2)
        ctx.scaleBy(x: 1, y: -1)
        let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsctx
        str.draw(at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    drawText("Port Killer 설치", size: 26, weight: .bold, color: c(1, 87, 155), center: CGPoint(x: 320, y: 70))
    drawText("아래 앱을 Applications 폴더로 드래그하세요 🐟", size: 14, weight: .medium,
             color: c(2, 119, 189), center: CGPoint(x: 320, y: 105))
    drawText("Drag to install", size: 12, weight: .regular, color: c(2, 119, 189, 0.7),
             center: CGPoint(x: 320, y: 320))
}

let args = CommandLine.arguments
guard args.count >= 3, let scale = Int(args[2]) else {
    FileHandle.standardError.write("사용법: swift GenerateDMGBackground.swift <출력.png> <배율(1|2)>\n".data(using: .utf8)!)
    exit(1)
}
let out = URL(fileURLWithPath: args[1])
let pxW = 640 * scale, pxH = 400 * scale
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8,
    bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("컨텍스트 생성 실패")
}
ctx.interpolationQuality = .high
drawBackground(into: ctx, scale: CGFloat(scale))
guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("이미지 저장 실패")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("  ✓ \(out.lastPathComponent) (\(pxW)x\(pxH))")
