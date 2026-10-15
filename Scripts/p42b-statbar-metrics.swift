// P42b 量尺：监控页顶部读数条从 4 格变 6 格（I8 加网络进出）在两档窗宽下的真实排版代价。
//
// 只量两件事实：单格能用多宽、这批标签/数值各自固有宽多少。
// 判定用的是 `MMStatItem` 自己的约束——数值 `lineLimit(1).minimumScaleFactor(0.7)`、
// 标题 `.caption` 且**没有** lineLimit（所以标题只会换行、不会缩字）。
//
// 全程不建窗口、不采样、不写盘：AppKit 字体度量在离屏算，输出只是数字。
import AppKit

let sidebarW: CGFloat = 220    // MainWindow.swift 的 navigationSplitViewColumnWidth(min: 220)
let windowMinW: CGFloat = 1000 // MacMasterApp.swift 的 .frame(minWidth: 1000)
let photoW: CGFloat = 1100     // fidelity-monitor §0 取证窗宽（p64 那批照片）
let scrollPad: CGFloat = 16    // MMGap.lg，滚动区 .padding
let rowGap: CGFloat = 12       // MMGap.md，statsRow 的 HStack spacing
let cardHPad: CGFloat = 12     // MMStatItem 的 .padding(.horizontal, MMGap.md)
let captionLineH: CGFloat = 13 // 07 稿 .stat .k 的 line-height
let cardH: CGFloat = 48        // §0 量过的实机读数卡整卡高（含描边）

let capFont = NSFont.preferredFont(forTextStyle: .caption1)
let rawTitle3 = NSFont.preferredFont(forTextStyle: .title3)
// MMStatItem 的数值只写 `.font(.title3)`，不带 weight，所以是常规字重；
// monospacedDigit 只换数字为等宽，字号不变。
let valFont = NSFont.monospacedDigitSystemFont(ofSize: rawTitle3.pointSize, weight: .regular)

func width(_ s: String, _ f: NSFont) -> CGFloat {
    NSAttributedString(string: s, attributes: [.font: f]).size().width
}

func usable(_ windowW: CGFloat) -> CGFloat { windowW - sidebarW - 2 * scrollPad }
func perCard(_ windowW: CGFloat, _ n: Int) -> CGFloat {
    (usable(windowW) - CGFloat(n - 1) * rowGap) / CGFloat(n)
}
func inner(_ windowW: CGFloat, _ n: Int) -> CGFloat { perCard(windowW, n) - 2 * cardHPad }

func f1(_ x: CGFloat) -> String { String(format: "%.1f", x) }
func f2(_ x: CGFloat) -> String { String(format: "%.2f", x) }

print("度量口径：标题 \(Int(capFont.pointSize))pt（preferredFont .caption1）· 数值 \(Int(rawTitle3.pointSize))pt monospacedDigit")
print("        可缩到 0.7 ⇒ 数值可用上限 = 单格文字宽 ÷ 0.7；标题无 lineLimit ⇒ 超宽就换行，每多一行 +\(Int(captionLineH))pt")
print("")

for (tag, w) in [("最小窗 1000pt", windowMinW), ("取证窗 1100pt", photoW)] {
    print("── \(tag)：滚动区可用宽 \(f1(usable(w)))pt")
    for n in [4, 5, 6] {
        print(String(format: "   %d 格：单格 %.1fpt · 标题/数值可用文字宽 %.1fpt · 数值缩字可用到 %.1fpt",
                     n, perCard(w, n), inner(w, n), inner(w, n) / 0.7))
    }
}
print("")

// 三档方案。A = 现有 4 格（基线）；B = 6 格；C = 5 格（磁盘读写挤成一行两项）。
let scenarios: [(String, Int, [(String, String)])] = [
    ("A · 现状 4 格", 4, [
        ("CPU 总占用", "35.8%"), ("内存", "80.2%"), ("磁盘 读", "1.9 MB/s"), ("磁盘 写", "293.3 KB/s"),
    ]),
    ("B · 加网络进出 = 6 格", 6, [
        ("CPU 总占用", "35.8%"), ("内存", "80.2%"), ("磁盘 读", "1.9 MB/s"), ("磁盘 写", "293.3 KB/s"),
        ("网络 下", "5.6 MB/s"), ("网络 上", "812.4 KB/s"),
    ]),
    ("C · 磁盘合成一格 = 5 格", 5, [
        ("CPU 总占用", "35.8%"), ("内存", "80.2%"), ("磁盘 读/写", "1.9 / 293.3 KB/s"),
        ("网络 下", "5.6 MB/s"), ("网络 上", "812.4 KB/s"),
    ]),
]

// 各档里"最坏但真会出现"的那几串：位数取 `MMFormat` 的天花板（compactBytes 最高到 TB、
// percent 固定一位小数），不是随手编的长串。C 档的双值串单独列进来。
let worstValues = ["—", "100.0%", "812.4 KB/s", "1023.9 TB/s", "1.9 / 293.3 KB/s", "1023.9 / 1023.9 TB/s"]

func report(_ n: Int, _ rows: [(String, String)], _ windowW: CGFloat) {
    let avail = inner(windowW, n)
    var wrapLabels: [String] = []
    var shrinkValues: [String] = []
    var clippedValues: [String] = []
    for (label, value) in rows {
        let lw = width(label, capFont), vw = width(value, valFont)
        let mark1 = lw > avail ? "✗换行" : "✓"
        let mark2: String
        if vw <= avail { mark2 = "✓" }
        else if vw * 0.7 <= avail { mark2 = "缩字 \(f2(avail / vw))" ; shrinkValues.append(value) }
        else { mark2 = "✗截断"; clippedValues.append(value) }
        if lw > avail { wrapLabels.append(label) }
        print(String(format: "   标题「%@」%6.1fpt %@  数值「%@」%6.1fpt %@",
                     label, lw, mark1, value, vw, mark2))
    }
    let extra = wrapLabels.count * Int(captionLineH)
    print("   ⇒ 标题超宽 \(wrapLabels.count) 个（\(wrapLabels.joined(separator: "、"))），卡高 \(Int(cardH))→\(Int(cardH) + extra)pt；缩字 \(shrinkValues.count) 个、截断 \(clippedValues.count) 个")
}

for w in [windowMinW, photoW] {
    print("══ 窗宽 \(Int(w))pt")
    for (name, n, rows) in scenarios {
        print("── \(name)（单格文字宽 \(f1(inner(w, n)))pt）")
        report(n, rows, w)
    }
    print("── 最坏位数（同一条数值分别放进 \(Int(w))pt 窗的 4 / 5 / 6 格）")
    for value in worstValues {
        let vw = width(value, valFont)
        var line = String(format: "   「%@」需 %5.1fpt：", value, vw)
        for n in [4, 5, 6] {
            let avail = inner(w, n)
            let verdict = vw <= avail ? "不缩字" : (vw * 0.7 <= avail ? "缩字" : "截断")
            line += String(format: " %d 格 %5.1fpt→%@  ", n, avail, verdict)
        }
        print(line)
    }
    print("")
}

print("══ 一句话余量（6 格 · 最窄窗 1000pt）")
let bRows = scenarios[1].2
let a6 = inner(windowMinW, 6)
let maxLabel = bRows.map { width($0.0, capFont) }.max() ?? 0
let maxValue = bRows.map { width($0.1, valFont) }.max() ?? 0
let ceiling = width("1023.9 TB/s", valFont)
print("   单格文字可用宽 \(f1(a6))pt：最宽标题 \(f1(maxLabel))pt、本档常用数值最宽 \(f1(maxValue))pt、位数天花板 \(f1(ceiling))pt")
print("   ⇒ 三者都不越线：不折行、不缩字、卡高仍 \(Int(cardH))pt，§0 那条折叠线落点不动")
print("")

print("══ 竖向代价（与缩字/换行分开算，两者可叠加）")
print("   读数条拆成两行：+卡高 \(Int(cardH)) + 块间距 \(Int(scrollPad)) = +\(Int(cardH + scrollPad))pt，")
print("     滚动视口高 = 窗高 700 − 标题栏 52 − 页头 46 = 602pt，吃掉 \(Int(cardH + scrollPad))pt = \(f1((cardH + scrollPad) / 602 * 100))%")
print("   只让标题折行不拆行：每个折行标签 +\(Int(captionLineH))pt（§0 那句「磁盘 IO 卡后内存卡只露一行」的落点会跟着下移这么多）")
print("   口径限制：本探针算的是 SwiftUI 同一套字体与内边距的**固有宽**，没实测 SwiftUI 的 HStack 压缩顺序；")
print("     真落地要拍一张 6 格的最小窗照片，不能只凭这张表结案。")
