// 独立读一次 `NSWorkspace.shared.runningApplications`，把"位置或包名对上某个 .app"的条目列出来。
//
// 它是给取证脚本当**哨兵**用的，不是产品代码：照片上写着「正在运行 · 2 个进程（1094、1276）」，
// 日志里就得有一行能独立说出这两个号，否则照片上那句话没人核对。
//
// 为什么不用 `pgrep`：pgrep -f 按可执行路径的子串匹配，`/Applications/WeChat.app/Contents/`
// 一把就捞出 13 个进程（crashpad_handler、WeChatHelper、各种 WeChatAppEx Helper…），
// 而快照里只有 1094 与 1276 这两条报出的 `bundleURL` 正好是外层那个 .app——
// 其余的要么报的是自己那个嵌套的 .app，要么根本不注册为应用。
// 所以"照片上有几个号"与"pgrep 有几个号"是两个口径，混用会让哨兵比画面多报或少报。
//
// 比较规则与 `RunningAppProbe.resolve` 一致：包名与位置都按**小写后的字符串**比，
// 不做 realpath；位置对上的算 `sameBundle`，只有包名对上的算 `bundleIdentifierOnly`。
// 这样哨兵与界面在同一条快照上必然给出同一个答案。
//
//   swift Scripts/running-apps-probe.swift /Applications/WeChat.app
import AppKit
import Foundation

let argv = CommandLine.arguments
guard argv.count >= 2 else {
    FileHandle.standardError.write("用法：running-apps-probe.swift <.app 路径>\n".data(using: .utf8)!)
    exit(2)
}
let targetPath = argv[1].lowercased()
let targetID = Bundle(url: URL(fileURLWithPath: argv[1]))?.bundleIdentifier?.lowercased()

var rows: [(pid: Int32, evidence: String, id: String, path: String)] = []
for app in NSWorkspace.shared.runningApplications {
    guard app.processIdentifier > 0 else { continue }
    let reportedPath = app.bundleURL?.path
    let reportedID = app.bundleIdentifier
    // 既报不出包名也报不出位置（空串同样算报不出）的条目不参与判定——
    // 界面上它们是「无法判定」的依据，不是匹配项。
    guard reportedID?.isEmpty == false || reportedPath?.isEmpty == false else { continue }
    let sameFile = reportedPath?.lowercased() == targetPath
    let sameID = reportedID?.isEmpty == false && reportedID?.lowercased() == targetID && !sameFile
    guard sameFile || sameID else { continue }
    rows.append((app.processIdentifier, sameFile ? "sameBundle" : "bundleIdentifierOnly",
                 reportedID ?? "（无）", reportedPath ?? "（无）"))
}
for row in rows.sorted(by: { $0.pid < $1.pid }) {
    print("pid=\(row.pid) evidence=\(row.evidence) bundleID=\(row.id) bundlePath=\(row.path)")
}
print("count=\(rows.count) pids=\(rows.map { String($0.pid) }.joined(separator: "、"))")
