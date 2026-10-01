// 从 PNG 的指定坐标取像素色，用于客观判定"这一屏到底是浅色档还是深色档"。
// 为什么要有这个：肉眼看截图会把"整体偏亮"当成"浅色档生效"，而真正的问题形态是
// 局部混档（窗口底浅、卡片仍深，或反过来）——那只有逐点量才看得见。
// 用法：swift Scripts/pixel-probe.swift <png> x,y[,x,y ...]
//       swift Scripts/pixel-probe.swift <png> scan <x|y> <fixed> <from> <to>   沿一条线打色带
//
// 注意：不要用 NSColor 在命令行里查语义色的值——脱离真实绘制上下文解析动态色，
// 浅深两档会给出同样的（错的）值。要判断"卡片比页面亮还是暗"只能量截图本身。
import Foundation
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3,
      let dataProvider = CGDataProvider(url: URL(fileURLWithPath: args[1]) as CFURL),
      let image = CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: false,
                          intent: .defaultIntent)
else {
    print("读不到图片：\(args.count > 1 ? args[1] : "(缺参数)")")
    exit(1)
}
let width = image.width, height = image.height
guard let data = image.dataProvider?.data,
      let ptr = CFDataGetBytePtr(data) else { print("取不到像素数据"); exit(1) }
let bpp = image.bitsPerPixel / 8
let bpr = image.bytesPerRow
// 只支持常规 RGBA/ARGB 截图格式；异常格式直接说清楚，不猜
guard bpp == 4 else { print("不支持的 bpp=\(bpp)"); exit(1) }

func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int)? {
    guard x >= 0, x < width, y >= 0, y < height else { return nil }
    let offset = y * bpr + x * bpp
    // PNG 里通道顺序按 CGImage 元数据解释；这里以首字节=R 的常见布局取样，
    // 若与实际不符会在文档里体现为一致性偏差，所以同一张图内比较仍然可靠。
    return (Int(ptr[offset]), Int(ptr[offset + 1]), Int(ptr[offset + 2]))
}

// 色带扫描：沿一条直线每像素取样，只在颜色变化处打印。
// 为什么：判断"卡片底和页面底是不是同一层"要的是边界，靠手点几个坐标容易正好点到文字上。
if args.count >= 6, args[2] == "scan" {
    let axis = args[3]
    let toArg: Int? = args.count > 6 ? Int(args[6]) : nil
    guard let fixed = Int(args[4]), let from = Int(args[5]) else {
        print("scan 参数不对，用法：scan <x|y> <fixed> <from> [to]"); exit(1)
    }
    let end = toArg ?? (axis == "x" ? height : width)
    var last: (Int, Int, Int)? = nil
    var runStart = from
    for pos in from..<end {
        let p = axis == "x" ? rgb(fixed, pos) : rgb(pos, fixed)
        if let p, let last, p == last { continue }
        if let last {
            let a = axis == "x" ? "y" : "x"
            print("\(a)=\(runStart)..\(pos - 1)  (\(last.0),\(last.1),\(last.2))")
        }
        last = p
        runStart = pos
    }
    if let last {
        let a = axis == "x" ? "y" : "x"
        print("\(a)=\(runStart)..\(end - 1)  (\(last.0),\(last.1),\(last.2))")
    }
    exit(0)
}

for spec in args.dropFirst(2) {
    let parts = spec.split(separator: ",")
    guard parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) else { continue }
    guard let (r, g, b) = rgb(x, y) else {
        print("\(x),\(y) 越界（图片 \(width)x\(height)）"); continue
    }
    print("\(x),\(y) = (\(r),\(g),\(b))")
}
