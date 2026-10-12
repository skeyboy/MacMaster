// P34b 取证探针：把生产判据层 `PreferencesAuditor` 在真机上跑一趟，量出**三段耗时的拆分**、
// ByHost 那一层的真实形状，以及"上千条时会是什么样"。全程只读：不写、不删、不改任何偏好域，
// 也不动 cfprefsd（唯一会写盘的是 `--scale` 档，它只往调用方给的 /tmp 假 home 里造样本）。
//
// 与 P34a 那支的分工（两支问的不是一个问题）：
// - `p34a-prefs-plist-probe.swift` 问"这些文件到底是什么状态，两种判据分不分家"——它自带判据，
//   因为那一轮生产代码还不存在；
// - 这一支问"**做成了产品代码之后**，一趟花多久、花在哪一段、上千条什么形状"。
//   所以它**不重写判据**：编译清单里就有 `PreferencesAudit.swift`，量的是将来界面调的那一条路。
//
// 为什么预算数值非要现量：`defaultBudgetMillis` 是"页头会不会说'剩下的 K 个没看'"的唯一开关。
// 抄参考实现 Mole 的 15 秒等于把它的扫描形状当成我们的——它那一趟边扫边删，
// 我们这一趟只下判据，量出来的数差着量级（见本探针的 `parse` 段）。
//
// 档位：
//   默认（真 home）        量本机这一族：三段耗时、逐条读取分布、读不到的归因、FDA 现状
//   P34B_PROBE_SCALE=N     在 /tmp 假 home 里造 N 条 plist，量"上千条"的形状（外推用）
//
// 退出码恒为 0：这是量尺，不是门。真正的门是 p16、单测与实拍照片。
import Foundation

@main struct PrefsScanProbe {

    static func main() {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["P34B_PROBE_SCALE"], let count = Int(raw), count > 0 {
            runScale(files: count, shape: env["P34B_PROBE_SHAPE"] ?? "small",
                     root: env["P34B_PROBE_ROOT"] ?? "/tmp/mm-p34b-scale")
            return
        }
        runReal(home: env["P34B_PROBE_HOME"] ?? NSHomeDirectory())
    }

    // MARK: - 真 home 档

    static func runReal(home: String) {
        let prefs = URL(fileURLWithPath: home).appendingPathComponent("Library/Preferences")

        print("## 进程身份（这一条决定下面那些读数是谁拿到的）")
        print("  bundle id：\(Bundle.main.bundleIdentifier ?? "（无：裸二进制，不是 .app）")")
        print("  可执行文件：\(CommandLine.arguments.first ?? "（未知）")")
        print("  home：\(home)")
        print("")

        printTccProbe(home: home)

        // ---- 枚举段单独计时：scan 内部那一段是它自己的表，这里复核一遍口径 ----
        let e0 = PreferencesAuditor.millisNow()
        let found = PreferencesAuditor.list(prefs: prefs)
        let e1 = PreferencesAuditor.millisNow()
        print("## 枚举段（PreferencesAuditor.list）")
        print("  单层计时：\(ms(e1 - e0))   条数：\(found.files.count)"
            + "   非正则跳过：\(found.skippedNonRegular)   读不到的根：\(found.skippedRoots.count)")
        for r in found.skippedRoots { print("  ⚠ 读不到的根：\(r)") }
        let topLevel = found.files.filter { !$0.path.contains("/ByHost/") }.count
        let byHost = found.files.count - topLevel
        print("  顶层 \(topLevel) 条 / ByHost \(byHost) 条"
            + "（§11.4 那句「ByHost 递归在本机贡献多少条」的答案就是这行）")
        printByHostShape(prefs: prefs)
        print("")

        // ---- 整趟：生产入口，跑三遍看方差 ----
        print("## 整趟 PreferencesAuditor.liveScan（默认预算 \(Int(PreferencesAuditor.defaultBudgetMillis)) ms）")
        var passes: [PreferencesScan] = []
        for i in 1...3 {
            let s = PreferencesAuditor.liveScan(home: home)
            passes.append(s)
            print("  第 \(i) 遍：枚举 \(ms(s.millis.enumerate)) / 读取 \(ms(s.millis.read)) /"
                + " 解析 \(ms(s.millis.parse)) = 合计 \(ms(s.millis.total))"
                + "   检查 \(s.inspectedCount)/\(s.foundFiles) 条"
                + "   截断=\(s.isPartial)")
        }
        guard let s = passes.last else { print("  ⚠ 一趟都没跑出来"); return }
        if s.foundFiles > 0 {
            print("  每条平均：读取 \(ms(s.millis.read / Double(s.rows.count))) /"
                + " 解析 \(ms(s.millis.parse / Double(s.rows.count)))"
                + "（**这两段一个是 IO 一个是 CPU，预算该由大的那段定**）")
            print("  外推：按第 3 遍的形状，\(Int(PreferencesAuditor.defaultBudgetMillis)) ms 预算大约够"
                + " \(Int(Double(s.foundFiles) * PreferencesAuditor.defaultBudgetMillis / max(s.millis.total, 0.001))) 条"
                + "（这是「这一台机器、这一批文件」的外推，不是产品承诺）")
        }
        print("")

        print("## 四态计数（与界面页头/两栏用的是同一批属性）")
        print("  检查过 \(s.inspectedCount) 条：解析成功 \(s.parsedCount) / 读不到 \(s.unreadableCount)"
            + " / 坏的那一栏 \(s.badRows.count) / 根不是字典 \(s.nonDictRootCount)")
        print("  页头会打成：「\(PreferencesCopy.headline(s))」")
        print("")

        print("## 「读不到」逐条归因（§11.1：GUI 进程是不是同样的答复，由实拍照片那一档回答）")
        for row in s.unreadableRows {
            print("  \(row.name)  保护名=\(PreferencesAuditor.isProtectedName(row.name))"
                + "  ByHost=\(row.inByHost)  \(row.verdict.badgeText)")
            print("      \(truncate(row.verdict.reasonText, 160))")
        }
        print("")

        printPerFileReads(files: found.files)
    }

    /// TCC 现状：这个进程有没有"完全磁盘访问"。不问"能不能读 Preferences"（那是本轮的主角，
    /// 已知能读），而是拿几处**一定要 FDA 才读得到**的地方当对照——读得到说明这一轮的
    /// "读不到"不是"我们没权限"造成的，读不到才需要把这句写进文案。
    static func printTccProbe(home: String) {
        print("## 这个进程的 FDA 现状（对照路径，决定「读不到」那一栏的语义）")
        let gated = ["Library/Mail", "Library/Safari", "Library/Messages",
                     "Library/Application Support/com.apple.TCC"]
        for rel in gated {
            let url = URL(fileURLWithPath: home).appendingPathComponent(rel)
            let result = Result { try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) }
            switch result {
            case .success(let items): print("  \(rel)：读得到（\(items.count) 项）")
            case .failure(let error): print("  \(rel)：读不到 — \(truncate(error.localizedDescription, 90))")
            }
        }
        print("  对照：Library/Preferences 本身读得到（下面整段就是它的数据）")
        print("")
    }

    /// §11.4：ByHost 这一层的深度与条数，以及**目录软链**在本层的真实条数。
    /// `enumerator(at:)` 不跟随目录软链（P34b 单测 `testListDoesNotEscapeThroughSymlinkedDirectories` 钉着），
    /// 这里量的是"本机这一层到底有没有这类东西、有几条"。
    static func printByHostShape(prefs: URL) {
        let byHost = prefs.appendingPathComponent("ByHost")
        guard let en = FileManager.default.enumerator(at: byHost, includingPropertiesForKeys: [
            .isRegularFileKey, .isSymbolicLinkKey,
        ], options: []) else {
            print("  ByHost：这一层读不到或不存在（按判据不算异常）")
            return
        }
        var depthCount: [Int: Int] = [:]
        var symlinks = 0, dirs = 0, plists = 0, maxDepth = 0
        for case let url as URL in en {
            let rel = url.path.hasPrefix(byHost.path) ? String(url.path.dropFirst(byHost.path.count)) : url.path
            let depth = rel.split(separator: "/").count
            maxDepth = max(maxDepth, depth)
            depthCount[depth, default: 0] += 1
            let v = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            if v?.isSymbolicLink == true { symlinks += 1 }
            if v?.isDirectory == true { dirs += 1 }
            if url.pathExtension.lowercased() == "plist" { plists += 1 }
        }
        print("  ByHost 遍历形状：条目 \(depthCount.values.reduce(0, +)) 个，最深 \(maxDepth) 层，"
            + "其中 plist \(plists) 条、软链 \(symlinks) 条、目录 \(dirs) 个")
        for d in depthCount.keys.sorted() { print("      深度 \(d)：\(depthCount[d] ?? 0) 条") }
    }

    /// 逐条读取耗时分布。这里**故意重走一遍**读取（用生产 `readData`），因为 `scan` 只累计、
    /// 不保留每条的表；预算是不是该按条数还是按体积定，只有分布能回答。
    static func printPerFileReads(files: [URL]) {
        print("## 逐条读取耗时分布（同一支生产 readData，重新走一遍）")
        var samples: [(ms: Double, bytes: Int?, name: String)] = []
        samples.reserveCapacity(files.count)
        for url in files {
            let t0 = PreferencesAuditor.millisNow()
            let _ = PreferencesAuditor.readData(at: url)
            let t1 = PreferencesAuditor.millisNow()
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            samples.append((t1 - t0, bytes, url.lastPathComponent))
        }
        let sorted = samples.sorted { $0.ms < $1.ms }
        let count = sorted.count
        func pct(_ p: Double) -> (ms: Double, bytes: Int?, name: String) {
            sorted[min(count - 1, Int(Double(count - 1) * p))]
        }
        print("  条数 \(count)：中位 \(ms(pct(0.5).ms)) / p90 \(ms(pct(0.9).ms)) /"
            + " p99 \(ms(pct(0.99).ms)) / 最慢 \(ms(sorted.last?.ms ?? 0))")
        print("  最慢 5 条（**看它是不是同时也是最大的那些**——是的话预算该看体积，不是的话看条数）：")
        for s in sorted.suffix(5).reversed() {
            print("      \(ms(s.ms))  \(s.bytes.map { "\($0) 字节" } ?? "体积未知")  \(s.name)")
        }
        let total = samples.reduce(0) { $0 + $1.ms }
        let bytes = samples.reduce(0) { $0 + ($1.bytes ?? 0) }
        print("  合计读取 \(ms(total))，总体积 \(bytes) 字节 →"
            + " \(ms(total / Double(max(count, 1))))/条、\(String(format: "%.3f", total / Double(max(bytes, 1)))) ms/字节")
        print("")
    }

    // MARK: - 规模档（上千条的形状）

    /// 往一棵 /tmp 假 home 里造 `count` 条 plist，再用**同一个生产 scan** 过一遍。
    /// 两种形状：`small`（每条几行键值，贴近真实分布）/ `big`（每条 ~48 KB，贴近 MobileSMS 那种）。
    /// 这一档存在的理由：本机 625 条 226 ms，预算截断那句话在真机上永远拍不到，
    /// 也不该等到 6 万条才发现"原来一趟要 20 秒"。
    static func runScale(files count: Int, shape: String, root: String) {
        let prefs = URL(fileURLWithPath: root).appendingPathComponent("Library/Preferences")
        try? FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        let body = shape == "big" ? String(repeating: "<key>k</key><integer>1</integer>", count: 3000) : ""
        for i in 0..<count {
            let url = prefs.appendingPathComponent("mm.scale.\(i).plist")
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>\(body)<key>index</key><integer>\(i)</integer></dict></plist>
            """
            try? Data(xml.utf8).write(to: url)
        }

        var inner = PreferencesAuditor.millisNow()
        _ = PreferencesAuditor.list(prefs: prefs)
        let coldEnumerate = PreferencesAuditor.millisNow() - inner
        inner = PreferencesAuditor.millisNow()
        _ = PreferencesAuditor.list(prefs: prefs)
        let warmEnumerate = PreferencesAuditor.millisNow() - inner

        print("## 规模档：假 home \(root)，\(count) 条，形状 \(shape)")
        print("  写盘耗时不计入判据（探针行为，不是生产行为）")
        print("  枚举：冷 \(ms(coldEnumerate)) / 再跑一次 \(ms(warmEnumerate))")
        for pass in 1...2 {
            let s = PreferencesAuditor.scan(prefs: prefs, budgetMillis: .infinity)
            print("  第 \(pass) 遍：枚举 \(ms(s.millis.enumerate)) / 读取 \(ms(s.millis.read)) /"
                + " 解析 \(ms(s.millis.parse)) = 合计 \(ms(s.millis.total))"
                + "   检查 \(s.inspectedCount)/\(s.foundFiles) 条   截断=\(s.isPartial)")
            if pass == 2, s.foundFiles > 0 {
                print("  每条：\(ms(s.millis.total / Double(s.foundFiles)))"
                    + " → 1 万条约 \(Int(s.millis.total / Double(s.foundFiles) * 10_000)) ms"
                    + "（**这才是预算该对齐的形状**；外推只在同一批形状内成立，真机文件有大有小）")
            }
        }
        // 截断这一支在真机上拍不到，规模档里当场证明它会发生、且页头会说清楚。
        let tiny = PreferencesAuditor.scan(prefs: prefs, budgetMillis: 12)
        print("  把预算压到 12 ms：检查 \(tiny.inspectedCount)/\(tiny.foundFiles) 条，截断=\(tiny.isPartial)")
        print("  页头读数：「\(PreferencesCopy.headline(tiny))」")
    }

    // MARK: - 小工具

    static func ms(_ v: Double) -> String { String(format: "%.1f ms", v) }

    static func truncate(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n)) + "…"
    }
}

extension PrefsVerdict {
    /// 探针专用：把 reason 摊出来打印。生产界面只说档名，不说 errno 原文
    /// （`Operation not permitted` 这种字符串对使用者没有信息量，界面上留给 `MMRevealButton`）。
    var reasonText: String {
        switch self {
        case .unreadable(let r), .unparsable(let r): return r
        case .zeroByte: return "0 字节"
        case .parsed(let root): return "root=\(root)"
        }
    }
}
