// P5.3 探针：kqueue 能不能看见目录里的 `.app` 增删。
// 用法：`caffeinate -i swift Scripts/apps-watch-probe.swift`（只在 /tmp 下建目录，不碰用户文件）。
// 结论写进 docs/analysis/apps-watch.md §3 —— 改实现前先跑一遍，别拿假设写代码。
//
// 为什么要打印相对时间：这个探针的结论就是"时序"。没有延迟数字的运行只能证明
// "事件最终会来"，证明不了"什么时候来"，也就分不清"一次删除产生两条事件"和
// "四个动作在唤醒瞬间一次性倾倒"这两种完全不同的解释。
import Foundation
import Darwin
import Dispatch

let dir = "/tmp/mm-watch-probe/watched"
try? FileManager.default.removeItem(atPath: dir)
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

let start = Date()
var lines: [String] = []
var closed = false
let lock = NSLock()

/// 事件回调排在 main queue，改动跑在另一条队列上：日志必须加锁串行追加，
/// 否则打印出来的顺序是竞态产物，不是真相。
func record(_ line: String) {
    lock.lock()
    defer { lock.unlock() }
    let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
    // cancel 之后到达的事件要标明：它不算"这次观察到了"，只是回调排在队里。
    lines.append("[\(elapsed)] \(line)" + (closed && line.hasPrefix("event") ? "  ← cancel 之后送达" : ""))
}

// 空目录刚建好就能 watch 吗？（夹具要从零开始造场景）
let fd = Darwin.open(dir, O_RDONLY)
precondition(fd >= 0, "open failed errno=\(errno)")
record("open ok fd=\(fd)")

let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
    eventMask: [.write, .delete, .rename, .revoke], queue: .main)
src.setEventHandler { record("event data=\(src.data.rawValue)") }
src.setCancelHandler { Darwin.close(fd) }
src.resume()

let work = DispatchQueue(label: "mutate")
work.asyncAfter(deadline: .now() + 0.4) {
    try! FileManager.default.createDirectory(atPath: dir + "/Foo.app", withIntermediateDirectories: true)
    record("created Foo.app")
}
work.asyncAfter(deadline: .now() + 1.0) {
    try! FileManager.default.removeItem(atPath: dir + "/Foo.app")
    record("removed Foo.app")
}
work.asyncAfter(deadline: .now() + 1.6) {
    // 目录里写一个毫不相干的普通文件，也触发吗？（决定事件有多吵）
    FileManager.default.createFile(atPath: dir + "/loose.txt", contents: Data())
    record("wrote loose.txt")
}
work.asyncAfter(deadline: .now() + 3.0) {
    // 留出足够窗口让最后一个写事件送达再收，否则会把"没收到"当成"不触发"。
    closed = true
    src.cancel()
    record("cancelled")
}
RunLoop.main.run(until: Date().addingTimeInterval(5.0))
lines.forEach { print($0) }
