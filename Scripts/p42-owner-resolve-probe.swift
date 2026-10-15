// P42a 量尺探针：偏好文件页那一列「主人名」到底填不填得满。
//
// 判定层不在这里：反查用 NSWorkspace（LaunchServices），它只认本机注册过的 bundle id，
// 查不到就是 nil——这条不猜、不补、不用名称模糊匹配。
// 剥扩展名 / 削 UUID 尾段 / 「反向域名形态」三道闸的语义抄自
// Packages/MMUninstaller/Sources/MMUninstaller/OrphanScanner.swift（真源那三处原文随日志头一起打出来，
// 便于对账；落地时判定应由真源提供，两处不一致则本读数作废）。
//
// 全程只读：只列 ~/Library/Preferences 与其 ByHost 子目录的文件名，不读内容、不写任何目录。

import AppKit
import Foundation

struct Row {
    let fileName: String
    let base: String
    let stripped: String
    let ownerShaped: Bool
    let resolved: String?
}

func isUUIDLike(_ name: String) -> Bool {
    let layout = [8, 4, 4, 4, 12]
    let parts = name.lowercased().split(separator: "-", omittingEmptySubsequences: true).map(String.init)
    guard parts.count == layout.count else { return false }
    return zip(parts, layout).allSatisfy { part, length in
        part.count == length && part.allSatisfy(\.isHexDigit)
    }
}

func strippingUUIDTailSegment(_ base: String) -> String {
    let segments = base.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard let last = segments.last, segments.count > 1, isUUIDLike(last) else { return base }
    return segments.dropLast().joined(separator: ".")
}

func isOwnerShaped(_ base: String) -> Bool {
    let segments = base.split(separator: ".").map(String.init)
    guard segments.count >= 3 else { return false }
    return segments.allSatisfy { $0.count >= 2 }
}

func stripExtension(_ fileName: String) -> String {
    fileName.replacingOccurrences(of: #"\.(plist|savedState|shm|binarycookies)$"#, with: "", options: .regularExpression)
}

func appName(for bundleID: String) -> String? {
    guard let url = try? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    guard let info = Bundle(url: url)?.infoDictionary else { return url.deletingPathExtension().lastPathComponent }
    if let d = info["CFBundleDisplayName"] as? String, !d.isEmpty { return d }
    if let n = info["CFBundleName"] as? String, !n.isEmpty { return n }
    return url.deletingPathExtension().lastPathComponent
}

func scan(dir: URL) -> [Row] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
    let ws = NSWorkspace.shared
    return names.filter { $0.hasSuffix(".plist") }.sorted().compactMap { name in
        let base = stripExtension(name)
        let identity = strippingUUIDTailSegment(base)
        guard isOwnerShaped(identity) else {
            return Row(fileName: name, base: base, stripped: identity, ownerShaped: false, resolved: nil)
        }
        let hit = (try? ws.urlForApplication(withBundleIdentifier: identity)) != nil ? appName(for: identity) : nil
        return Row(fileName: name, base: base, stripped: identity, ownerShaped: true, resolved: hit)
    }
}

func appleShaped(_ base: String) -> Bool {
    base.lowercased().hasPrefix("com.apple")
}

func report(_ title: String, _ rows: [Row]) {
    let total = rows.count
    let shaped = rows.filter { $0.ownerShaped }
    let hit = shaped.filter { $0.resolved != nil }
    let hitApple = hit.filter { appleShaped($0.stripped) }
    print("## \(title)")
    print("  .plist 总数 \(total)｜形态闸通过 \(shaped.count)｜闸外 \(total - shaped.count)")
    print("  反查命中 \(hit.count)（占总数 \(pct(hit.count, total))、占闸内 \(pct(hit.count, shaped.count))）")
    print("  其中 Apple 前缀 \(hitApple.count)｜第三方 \(hit.count - hitApple.count)")
    print("  ⇒ 这一列真能画出名字的只有第三方那一档：\(hit.count - hitApple.count) / \(total) = \(pct(hit.count - hitApple.count, total))")
    print("  命中样本（前 6 条，bundle id → 显示名）：")
    for r in hit.prefix(6) { print("    \(r.stripped) → \(r.resolved ?? "（无显示名）")") }
    print("  未命中样本（前 6 条）：")
    for r in shaped.filter { $0.resolved == nil }.prefix(6) { print("    \(r.stripped)") }
    print("")
}

func pct(_ a: Int, _ b: Int) -> String {
    b == 0 ? "—" : String(format: "%.1f%%", Double(a) * 100.0 / Double(b))
}

let home = FileManager.default.homeDirectoryForCurrentUser
let prefs = home.appendingPathComponent("Library/Preferences")
let byHost = prefs.appendingPathComponent("ByHost")

print("# 口径：NSWorkspace.urlForApplication(withBundleIdentifier:) 是唯一判据；查不到即 nil，UI 该画「—」。")
print("# 三道闸（剥扩展名 / 削 UUID 尾段 / 反向域名形态）语义抄自 OrphanScanner.swift，落地时以真源为准。")
print("")

let top = scan(dir: prefs)
let host = scan(dir: byHost)
report("顶层 \(prefs.path)", top)
report("ByHost \(byHost.path)", host)

let both = top + host
let usable = both.filter { $0.ownerShaped && $0.resolved != nil && !appleShaped($0.stripped) }
print("## 合起来")
print("  两族共 \(both.count) 行；画 owner 列时能给第三方应用名的 \(usable.count) 行（\(pct(usable.count, both.count))），其余 \(both.count - usable.count) 行画「—」。")
