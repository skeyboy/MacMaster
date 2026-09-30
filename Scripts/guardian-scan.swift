// guardian-scan.swift — CoreGraphics 逐像素取色/找边界，供设计稿↔实机几何对照。
//
// 用法（截图为 Retina @2x，本工具一律以 pt 报数：px ÷ scale，scale 由 --scale 给，默认 2）：
//   swift Scripts/guardian-scan.swift <img.png> px <x> <y>                    单点颜色（pt 坐标）
//   swift Scripts/guardian-scan.swift <img.png> vedges <x> <y0> <y1> [--tol N] 沿竖线 x 找颜色突变（行边界）
//   swift Scripts/guardian-scan.swift <img.png> hedges <y> <x0> <x1> [--tol N] 沿横线 y 找颜色突变（列边界）
//   swift Scripts/guardian-scan.swift <img.png> vfill <x> <y0> <y1>           竖线上每段填充的起止与颜色
//
// 输出全部是 pt；"实机像素测量、不许估"就靠这四个子命令。工具留在仓库里，
// 别把一次性脚本散在 /tmp（并发施工时 /tmp 随时可能被别人清掉）。

import CoreGraphics
import ImageIO
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let img = loadBitmap(args[1]) else {
    FileHandle.standardError.write(Data("用法: guardian-scan.swift <img.png> <子命令> …；图片读不到\n".utf8))
    exit(2)
}

func loadBitmap(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

// 把 CGImage 铺进 RGBA8 位图，逐点取色。
let scale: Double = {
    if let i = args.firstIndex(of: "--scale"), i + 1 < args.count, let v = Double(args[i + 1]) { return v }
    return 2.0
}()
guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { exit(3) }
let W = img.width, H = img.height
var buf = [UInt8](repeating: 0, count: W * H * 4)
let drawn: Bool = buf.withUnsafeMutableBytes { raw -> Bool in
    guard let ctx = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: W * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
    return true
}
if !drawn { FileHandle.standardError.write(Data("绘制失败\n".utf8)); exit(3) }

// pt → px
func px(_ x: Double) -> Int { min(W - 1, max(0, Int((x * scale).rounded()))) }
func py(_ y: Double) -> Int { min(H - 1, max(0, Int((y * scale).rounded()))) }
func color(_ xi: Int, _ yi: Int) -> (Int, Int, Int, Int) {
    let i = (yi * W + xi) * 4
    return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]), Int(buf[i + 3]))
}
func dist(_ a: (Int, Int, Int, Int), _ b: (Int, Int, Int, Int)) -> Int {
    abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)
}
func fmt(_ c: (Int, Int, Int, Int)) -> String { "(\(c.0),\(c.1),\(c.2)) a\(c.3)" }

let cmd = args[2]
let tol = (args.firstIndex(of: "--tol").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil }) ?? 24

switch cmd {
case "px":
    guard args.count >= 5, let x = Double(args[3]), let y = Double(args[4]) else { exit(2) }
    print("pt(\(x),\(y)) → px(\(px(x)),\(py(y))) = \(fmt(color(px(x), py(y))))")
case "vedges":
    guard args.count >= 6, let x = Double(args[3]), let y0 = Double(args[4]), let y1 = Double(args[5]) else { exit(2) }
    var prev = color(px(x), py(y0))
    print("x=\(x) 竖线，从 y=\(y0) 到 \(y1)，tol=\(tol)：")
    for yi in py(y0)...py(y1) {
        let c = color(px(x), yi)
        if dist(c, prev) > tol {
            print(String(format: "  y=%.2f pt  %→  %@", Double(yi) / scale, fmt(prev), fmt(c)))
            prev = c
        }
    }
case "hedges":
    guard args.count >= 6, let y = Double(args[3]), let x0 = Double(args[4]), let x1 = Double(args[5]) else { exit(2) }
    var prev = color(px(x0), py(y))
    print("y=\(y) 横线，从 x=\(x0) 到 \(x1)，tol=\(tol)：")
    for xi in px(x0)...px(x1) {
        let c = color(xi, py(y))
        if dist(c, prev) > tol {
            print(String(format: "  x=%.2f pt  %→  %@", Double(xi) / scale, fmt(prev), fmt(c)))
            prev = c
        }
    }
case "vfill":
    guard args.count >= 6, let x = Double(args[3]), let y0 = Double(args[4]), let y1 = Double(args[5]) else { exit(2) }
    var runs: [(startPx: Int, endPx: Int, c: (Int, Int, Int, Int))] = []
    for yi in py(y0)...py(y1) {
        let c = color(px(x), yi)
        if let last = runs.last, dist(last.c, c) <= tol { runs[runs.count - 1].endPx = yi }
        else { runs.append((yi, yi, c)) }
    }
    print("x=\(x) 竖线填充段（忽略 <2px 的抗锯齿细段）：")
    for r in runs where r.endPx - r.startPx >= Int(2 * scale) {
        print(String(format: "  y %.2f→%.2f pt（%.2f pt 高）  %@",
                     Double(r.startPx) / scale, Double(r.endPx) / scale,
                     Double(r.endPx - r.startPx + 1) / scale, fmt(r.c)))
    }
default:
    FileHandle.standardError.write(Data("未知子命令 \(cmd)\n".utf8))
    exit(2)
}
