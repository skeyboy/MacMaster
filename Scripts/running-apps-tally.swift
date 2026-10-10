// 现读一次本机进程快照，按 `RunningAppProbe.snapshot()` 的同一口径给两行统计。
//
// 为什么要入库：`fidelity-uninstaller.md` §13.3 与 `RunningAppProbe.swift` 的注释里都写着
// "参与判定 N 条 / 包名报不出 N 条 / 位置报不出 N 条 / **两样都报不出 0 条**"，
// 而"两样都报不出是 0 条"正是 `undetermined` 那一档**本机拍不出照片**的唯一依据。
// 一个支撑"为什么没有证据"的数字，必须能被别人一键重算，否则它和一句印象没有区别。
//
// 口径与生产代码逐条对齐（改生产口径时要同时改这里，不然两边会安静地分家）：
// `processIdentifier <= 0` 先剔（`com.apple.dt.Devices` 那类在 LaunchServices 账上却不是进程）；
// "报不出"= nil **或** 空串（与 `RunningAppInfo.isUnattributable` 的 `?.isEmpty != false` 同形）。
//
// 用法：swift Scripts/running-apps-tally.swift
import AppKit

var idEmpty = 0, pathEmpty = 0, bothEmpty = 0, participating = 0, nonPositive = 0
// 按**枚举 case 名**分桶，不按 `rawValue`：`ActivationPolicy` 是 regular=0 / accessory=1 / prohibited=2，
// 而"1 到底是 prohibited 还是 accessory"这种事不该靠记——第一版按数字打，差点把
// `.accessory` 12 条读成 `.prohibited` 12 条（`RunningAppProbe.swift` 里那条注释就是这么错的）。
// `String(describing:)` 也不行：这个从 Objective-C 桥过来的枚举打出来是
// `NSApplicationActivationPolicy(rawValue: 1)`，绕一圈又回到数字。所以逐 case 写死，
// 苹果哪天加一个 case 编译会提醒（`@unknown default` 那支）。
var nilIDByPolicy: [String: Int] = [:]

func policyName(_ p: NSApplication.ActivationPolicy) -> String {
    switch p {
    case .regular: return "regular"
    case .accessory: return "accessory"
    case .prohibited: return "prohibited"
    @unknown default: return "unknown(\(p.rawValue))"
    }
}

for app in NSWorkspace.shared.runningApplications {
    if app.processIdentifier <= 0 { nonPositive += 1; continue }
    let idMissing = app.bundleIdentifier?.isEmpty != false
    let pathMissing = app.bundleURL?.path.isEmpty != false
    if idMissing { nilIDByPolicy[policyName(app.activationPolicy), default: 0] += 1 }
    if idMissing { idEmpty += 1 }
    if pathMissing { pathEmpty += 1 }
    if idMissing && pathMissing { bothEmpty += 1; continue }
    participating += 1
}

print("total=\(NSWorkspace.shared.runningApplications.count) pidNonPositive=\(nonPositive) "
      + "participating=\(participating) idEmpty=\(idEmpty) pathEmpty=\(pathEmpty) bothEmpty=\(bothEmpty)")
print("idEmpty 按 activationPolicy:",
      nilIDByPolicy.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
