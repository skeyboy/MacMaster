// 列出窗口 id，供 `screencapture -o -x -l<id>` 使用。
//
// 本项目验证原生 UI 只用"抓窗口"这一条路：合成点击/滚轮/键盘会逃逸到用户当时的
// 前台应用，属于不可接受副作用。用法：
//   swift Scripts/window-ids.swift            # 全部窗口
//   swift Scripts/window-ids.swift MacMaster  # 按进程名过滤
import CoreGraphics
import Foundation

let filter = CommandLine.arguments.dropFirst().first
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("no window info"); exit(1)
}
for info in infoList {
    guard let pid = info[kCGWindowOwnerPID as String] as? Int,
          let name = info[kCGWindowOwnerName as String] as? String,
          let number = info[kCGWindowNumber as String] as? Int
    else { continue }
    if let filter, name != filter { continue }
    let layer = info[kCGWindowLayer as String] as? Int ?? -1
    let title = info[kCGWindowName as String] as? String ?? ""
    let bounds = (info[kCGWindowBounds as String] as? [String: Any]) ?? [:]
    print("windowid=\(number) pid=\(pid) layer=\(layer) title=\(title) bounds=\(bounds)")
}
