import AppKit

// 用法: swiftc make_icon.swift -o make_icon && ./make_icon <原图.png> <输出.iconset>
// 作用: 中心裁成正方形 → 按 macOS 图标规范（内缩 ~10%、圆角 ~22.5%）生成全套尺寸

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: make_icon <input.png> <output.iconset>")
    exit(1)
}
let inputPath = args[1]
let outputDir = args[2]

guard let source = NSImage(contentsOfFile: inputPath) else {
    print("无法读取图片: \(inputPath)")
    exit(1)
}
var proposed = CGRect(origin: .zero, size: source.size)
guard let cg = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
    print("无法转换 CGImage")
    exit(1)
}

let side = min(cg.width, cg.height)
let cropRect = CGRect(
    x: (cg.width - side) / 2,
    y: (cg.height - side) / 2,
    width: side,
    height: side
)
guard let cropped = cg.cropping(to: cropRect) else {
    print("裁剪失败")
    exit(1)
}

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

let drawable = NSImage(cgImage: cropped, size: NSSize(width: side, height: side))

for (name, size) in entries {
    let canvas = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        print("创建位图失败 \(size)")
        exit(1)
    }
    rep.size = NSSize(width: canvas, height: canvas)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    // macOS 图标安全区：四周内缩约 9.8%，圆角半径约 22.45%
    let inset = canvas * 0.098
    let content = NSRect(
        x: inset, y: inset,
        width: canvas - inset * 2,
        height: canvas - inset * 2
    )
    let radius = content.width * 0.2245
    let clip = NSBezierPath(roundedRect: content, xRadius: radius, yRadius: radius)
    clip.addClip()

    drawable.draw(
        in: content,
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("导出 PNG 失败 \(size)")
        exit(1)
    }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(name)
    try png.write(to: url)
}

print("生成完成: \(outputDir)")
