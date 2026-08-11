import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 귀여운 물고기 앱 아이콘 생성기.
// 1024 기준 좌표계로 그린 뒤 각 iconset 크기로 렌더링한다.
// 사용법: swift Tools/GenerateIcon.swift <출력 .iconset 디렉토리>

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: a)
}

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 1024x1024 기준으로 아이콘을 그린다. ctx 는 이미 size x size 로 스케일되어 있다고 가정.
func drawIcon(into ctx: CGContext, size: CGFloat) {
    let scale = size / 1024.0
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)

    // 배경: 둥근 사각형 + 세로 그라디언트 (바다색)
    let bg = roundedRectPath(CGRect(x: 0, y: 0, width: 1024, height: 1024), radius: 224)
    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(
        colorsSpace: space,
        colors: [rgb(90, 200, 245), rgb(2, 119, 189)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [])

    // 물결 하이라이트 (은은한 상단 광)
    ctx.setFillColor(rgb(255, 255, 255, 0.10))
    ctx.fillEllipse(in: CGRect(x: -200, y: 620, width: 1424, height: 700))
    ctx.restoreGState()

    // 좌표계: CG 는 y 아래가 0. 아래 그림은 화면 기준 좌표를 쓰기 위해 y 를 뒤집는다.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // ---- 물고기 (오른쪽을 바라봄) ----

    // 꼬리
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 300, y: 512))
    tail.addCurve(to: CGPoint(x: 150, y: 360),
                  control1: CGPoint(x: 230, y: 470), control2: CGPoint(x: 180, y: 400))
    tail.addCurve(to: CGPoint(x: 250, y: 512),
                  control1: CGPoint(x: 210, y: 440), control2: CGPoint(x: 250, y: 480))
    tail.addCurve(to: CGPoint(x: 150, y: 664),
                  control1: CGPoint(x: 250, y: 544), control2: CGPoint(x: 210, y: 584))
    tail.addCurve(to: CGPoint(x: 300, y: 512),
                  control1: CGPoint(x: 180, y: 624), control2: CGPoint(x: 230, y: 554))
    tail.closeSubpath()
    ctx.addPath(tail)
    ctx.setFillColor(rgb(255, 138, 101))
    ctx.fillPath()

    // 위 지느러미
    let topFin = CGMutablePath()
    topFin.move(to: CGPoint(x: 470, y: 640))
    topFin.addQuadCurve(to: CGPoint(x: 560, y: 760), control: CGPoint(x: 470, y: 760))
    topFin.addQuadCurve(to: CGPoint(x: 620, y: 660), control: CGPoint(x: 620, y: 720))
    topFin.closeSubpath()
    ctx.addPath(topFin)
    ctx.setFillColor(rgb(255, 138, 101))
    ctx.fillPath()

    // 몸통 (통통한 타원) + 배 하이라이트
    let bodyRect = CGRect(x: 280, y: 340, width: 520, height: 344)
    ctx.saveGState()
    ctx.addEllipse(in: bodyRect)
    ctx.clip()
    let bodyGrad = CGGradient(
        colorsSpace: space,
        colors: [rgb(255, 167, 130), rgb(255, 112, 67)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(bodyGrad, start: CGPoint(x: 0, y: 684), end: CGPoint(x: 0, y: 340), options: [])
    ctx.restoreGState()

    // 아래 지느러미
    let botFin = CGMutablePath()
    botFin.move(to: CGPoint(x: 520, y: 380))
    botFin.addQuadCurve(to: CGPoint(x: 600, y: 300), control: CGPoint(x: 560, y: 300))
    botFin.addQuadCurve(to: CGPoint(x: 640, y: 400), control: CGPoint(x: 660, y: 340))
    botFin.closeSubpath()
    ctx.addPath(botFin)
    ctx.setFillColor(rgb(255, 112, 67))
    ctx.fillPath()

    // 눈 (흰자 + 눈동자 + 반짝임)
    ctx.setFillColor(rgb(255, 255, 255))
    ctx.fillEllipse(in: CGRect(x: 618, y: 470, width: 118, height: 118))
    ctx.setFillColor(rgb(40, 40, 55))
    ctx.fillEllipse(in: CGRect(x: 650, y: 486, width: 60, height: 60))
    ctx.setFillColor(rgb(255, 255, 255))
    ctx.fillEllipse(in: CGRect(x: 686, y: 522, width: 22, height: 22))

    // 볼터치 (은은한 분홍)
    ctx.setFillColor(rgb(255, 82, 82, 0.30))
    ctx.fillEllipse(in: CGRect(x: 640, y: 420, width: 70, height: 44))

    // 미소
    ctx.setStrokeColor(rgb(120, 40, 20))
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    let smile = CGMutablePath()
    smile.move(to: CGPoint(x: 690, y: 430))
    smile.addQuadCurve(to: CGPoint(x: 760, y: 430), control: CGPoint(x: 725, y: 400))
    ctx.addPath(smile)
    ctx.strokePath()

    // 물방울
    ctx.setFillColor(rgb(255, 255, 255, 0.55))
    ctx.fillEllipse(in: CGRect(x: 800, y: 640, width: 46, height: 46))
    ctx.fillEllipse(in: CGRect(x: 860, y: 710, width: 28, height: 28))

    ctx.restoreGState()
}

func renderPNG(size: Int, to url: URL) {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("컨텍스트 생성 실패") }

    ctx.interpolationQuality = .high
    drawIcon(into: ctx, size: CGFloat(size))

    guard let image = ctx.makeImage() else { fatalError("이미지 생성 실패") }
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fatalError("PNG 대상 생성 실패") }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// ---- 메인 ----
let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("사용법: swift GenerateIcon.swift <출력.iconset 디렉토리>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// iconset 규격 (이름, 픽셀 크기)
let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in specs {
    renderPNG(size: size, to: outDir.appendingPathComponent(name))
    print("  ✓ \(name) (\(size)px)")
}
print("✅ iconset 생성 완료: \(outDir.path)")
