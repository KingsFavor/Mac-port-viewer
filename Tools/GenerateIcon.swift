import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 앱 아이콘 생성기.
// assets/logo.png (검정 배경 + 흰색 로고, 1024 정사각형) 를 각 iconset 크기로 리샘플링한다.
// 사용법: swift Tools/GenerateIcon.swift <출력 .iconset 디렉토리> [소스 PNG 경로]

func loadSourceImage(_ path: String) -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        FileHandle.standardError.write("소스 이미지 로드 실패: \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    return img
}

func renderPNG(_ image: CGImage, size: Int, to url: URL) {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("컨텍스트 생성 실패") }

    ctx.interpolationQuality = .high
    // 검정 배경으로 채운 뒤 로고를 그린다 (소스에 배경이 포함돼 있어도 안전).
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

    guard let out = ctx.makeImage() else { fatalError("이미지 생성 실패") }
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fatalError("PNG 대상 생성 실패") }
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
}

// ---- 메인 ----
let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("사용법: swift GenerateIcon.swift <출력.iconset 디렉토리> [소스 PNG]\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
let sourcePath = args.count >= 3 ? args[2] : "assets/logo.png"
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let source = loadSourceImage(sourcePath)

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
    renderPNG(source, size: size, to: outDir.appendingPathComponent(name))
    print("  ✓ \(name) (\(size)px)")
}
print("✅ iconset 생성 완료: \(outDir.path)")
