// 列出窗口 id，供 `screencapture -o -x -l<id>` 使用。
//
// 本项目验证原生 UI 只用"抓窗口"这一条路：合成点击/滚轮/键盘会逃逸到用户当时的
// 前台应用，属于不可接受副作用。用法：
//   swift Scripts/window-ids.swift            # 全部窗口
//   swift Scripts/window-ids.swift MacMaster  # 按进程名过滤
//   swift Scripts/window-ids.swift --pid 1234 # 只列这个 pid 的窗口
//
// 并发验证（多个实例同时在跑）必须用 `--pid`：按进程名过滤会把别人那个实例的窗口
// 一起列出来，抓错窗口的截图比没截图更糟——它会让一份错误的证据看起来是真的。
import CoreGraphics
import Foundation

var nameFilter: String?
var pidFilter: Int?
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--pid":
        guard let raw = args.next(), let pid = Int(raw) else {
            FileHandle.standardError.write("--pid 后面要跟数字\n".data(using: .utf8)!)
            exit(2)
        }
        pidFilter = pid
    default:
        if nameFilter == nil { nameFilter = arg }
    }
}

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("no window info"); exit(1)
}
for info in infoList {
    guard let pid = info[kCGWindowOwnerPID as String] as? Int,
          let name = info[kCGWindowOwnerName as String] as? String,
          let number = info[kCGWindowNumber as String] as? Int
    else { continue }
    if let pidFilter, pid != pidFilter { continue }
    if let nameFilter, name != nameFilter { continue }
    let layer = info[kCGWindowLayer as String] as? Int ?? -1
    let title = info[kCGWindowName as String] as? String ?? ""
    let bounds = (info[kCGWindowBounds as String] as? [String: Any]) ?? [:]
    print("windowid=\(number) pid=\(pid) layer=\(layer) title=\(title) bounds=\(bounds)")
}
