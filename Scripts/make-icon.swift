// 生成 MacMaster 的应用图标（一套 .iconset 的十张 PNG）。
//
//   swift Scripts/make-icon.swift /tmp/AppIcon.iconset
//
// 为什么是"画"出来的而不是丢一张位图进仓库：本仓库的红线是**每个数字都能自证**。
// 一张来路不明的 1024 png 没人能重画第二遍，改个圆角都得靠图像软件手 P；
// 这份脚本跑出来的图标，几何与配色全在下面的常量里，谁都能重跑并 diff。
//
// 形状取自设计系统自己的品牌符号 `sparkles`（`docs/design-system/icons.js` 里那条 path），
// 也就是侧边栏「✦ MacMaster」那颗。参数化写法：四角星 = 轴向 4 个外顶点 + 45° 4 个内顶点，
// 内/外半径比 0.362 是从 icons.js 那条 path 直接量出来的（外 3.9、内 √2），
// 所以画出来的星和稿子里的星是同一种星，不是"看着像"。
import AppKit
import Foundation

// MARK: - 配色（对齐 tokens.css）

/// `--c-accent`：暗档 #0A84FF、亮档 #007AFF。图标取暗档那支作顶端，
/// 底端压到 #0040DD——纯 #0A84FF 平铺在白色桌面上会糊成一片蓝，梯度是必要的。
let topColor = CGColor(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0, alpha: 1)
let bottomColor = CGColor(red: 0x00 / 255.0, green: 0x40 / 255.0, blue: 0xDD / 255.0, alpha: 1)

/// 星是白的；小星压一点透明度，避免三颗星一样亮看着像三个同级的东西。
let starColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

// MARK: - 几何

/// 圆角半径 / 边长。macOS 图标是连续曲率圆角（squircle），这里用普通圆角矩形近似；
/// 差多少肉眼在 32pt 以下看不出来，1024 档放大看边缘会发现没那么"鼓"。这一点如实写进文档。
let cornerRatio: CGFloat = 0.2237

/// 内/外半径比，见文件头从 icons.js 量出来的那段。
let starWaistRatio: CGFloat = 0.362

/// 四角星路径。CG 的 y 轴向上，所以"上顶点"是 center.y + r。
func starPath(center: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    for i in 0..<8 {
        let isOuter = i.isMultiple(of: 2)
        let r = isOuter ? radius : radius * starWaistRatio
        // i=0 从正上方起，顺时针每 45° 一个顶点。
        let angle = CGFloat.pi / 2 - CGFloat(i) * CGFloat.pi / 4
        let p = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    return path
}

/// 三颗星的摆位，全部用**边长比例**表达，所以同一份代码出 16 也出 1024。
/// 大星偏左上、两颗小星在右下，留出对角线方向的重心（和侧边栏那颗的读法一致）。
/// 注意 y 向上：0.60 是"从底往上六成"，也就是视觉上的偏上。
let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, alpha: CGFloat)] = [
    (x: 0.42, y: 0.58, r: 0.295, alpha: 1.0),
    (x: 0.70, y: 0.34, r: 0.125, alpha: 0.92),
    (x: 0.63, y: 0.72, r: 0.075, alpha: 0.80),
]

func drawIcon(size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil,
                        width: size, height: size,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let side = CGFloat(size)
    let tile = CGRect(x: 0, y: 0, width: side, height: side)
    let radius = side * cornerRatio

    // 底：圆角矩形裁切 + 竖直梯度。
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space,
                              colors: [topColor, bottomColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // 星。小尺寸下按比例算出的半径会小于一个像素的缝，16 档只画大星——
    // 三颗星挤在 16px 里是一团糊，糊掉不如少画。
    let visible = size >= 48 ? stars : Array(stars.prefix(1))
    for star in visible {
        ctx.addPath(starPath(center: CGPoint(x: side * star.x, y: side * star.y),
                             radius: side * star.r))
        ctx.setFillColor(starColor.copy(alpha: star.alpha)!)
        ctx.fillPath()
    }
    return ctx.makeImage()!
}

// MARK: - 落盘

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("用法：swift Scripts/make-icon.swift <iconset 目录>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = args[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// iconutil 认的就是这十个文件名；少一个就会少一档分辨率，Dock 缩到很小那张会糊。
let reps: [(name: String, size: Int)] = [
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

for rep in reps {
    let image = drawIcon(size: rep.size)
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("PNG 编码失败：\(rep.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(rep.name)
    try png.write(to: url)
    print("✓ \(rep.name)  \(rep.size)×\(rep.size)  \(png.count) 字节")
}
