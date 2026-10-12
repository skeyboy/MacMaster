// P34a 取证探针：`~/Library/Preferences` 这一族 plist 在本机上到底是什么状态。
//
// 用法在 `Scripts/p34a-prefs-plist-probe.sh`（它负责编译与归因头）。全程只读：
// 不写、不删、不改任何偏好域，也不动 cfprefsd。
//
// 为什么先要这么一支探针：这一族能力的主张是"检测损坏的 plist"，而"损坏"在界面上是一句
// 会被当成事实的话。真机上 `~/Library/Preferences` 里那几种"看起来坏"的状态
// （读不到、0 字节、解析失败、根对象不是字典）在语义上**互相不同**，其中至少一种在 macOS 上是
// 正常现象。不先把这几类的真实条数量出来，写出来的文案就会把正常说成故障——那是这一族最容易犯的假话。
//
// `plutil -lint` 在这里只当**对照 oracle**（探针不是生产代码）。生产实现按 v1.1 §2 第 3 条的约束
// 走 `PropertyListSerialization`、不为此 spawn 进程，所以必须当场量出两种判据**会不会给出不同答案**、
// 差在哪一类文件上——差值不知道就不该上界面。对照走**批量一趟**（一次 spawn 传全部路径），
// 不是抽样：抽样问不出"有没有"，只问得出"我这 20 条里有没有"。
import Foundation

@main struct PrefsPlistProbe {

    /// 一个文件的四种结局。`unreadable` 与 `empty` 都不等于"损坏"，界面上也不该说成损坏。
    enum Verdict {
        case unreadable(String)
        case empty
        case parseFailed(String)
        case parsed(format: String, root: String)
    }

    struct Row {
        let path: String
        let bytes: Int
        let modified: String
        let verdict: Verdict
    }

    static func main() {
        if let synth = ProcessInfo.processInfo.environment["P34A_PROBE_SYNTH"] {
            runSynthetic(root: synth)
            return
        }
        let home = ProcessInfo.processInfo.environment["P34A_PROBE_HOME"] ?? NSHomeDirectory()
        let prefs = URL(fileURLWithPath: home).appendingPathComponent("Library/Preferences")
        let fm = FileManager.default

        let t0 = DispatchTime.now()
        let collected = collect(prefs: prefs, fm)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
        // 对照 oracle：一次 spawn 把全部路径交给 plutil，逐行收回。
        let lint = plutilBatch(collected.rows.map { $0.path })
        report(collected.rows, home: home, skippedDirs: collected.skipped, scanMillis: ms, lint: lint)
    }

    /// 顶层 + ByHost 两层的采集。真 home 与夹具档走同一条代码路径——
    /// 夹具那一跑要能证明"判据在真机上会怎么说"，采集方式就不能是两套。
    static func collect(prefs: URL, _ fm: FileManager) -> (rows: [Row], skipped: [String]) {
        var rows: [Row] = []
        var skippedDirs: [String] = []

        // 顶层：只取这一层里的普通文件（含 `.GlobalPreferences.plist` 这种点开头的，
        // 它恰好是要单独说清楚的那一类，用 skipsHiddenFiles 会把它整个漏掉）。
        if let items = try? fm.contentsOfDirectory(at: prefs, includingPropertiesForKeys: nil, options: []) {
            for ent in items where ent.pathExtension.lowercased() == "plist" {
                if isDirectory(ent.path, fm) { continue }
                rows.append(row(for: ent, fm))
            }
        } else {
            skippedDirs.append("\(prefs.path)（顶层读不到）")
        }

        // ByHost：递归（Mole 那一支对这一层不限深度，文件名里带主机/UUID 后缀）。
        let byHost = prefs.appendingPathComponent("ByHost")
        if let en = fm.enumerator(at: byHost, includingPropertiesForKeys: [.isRegularFileKey], options: []) {
            for case let url as URL in en {
                let vals = try? url.resourceValues(forKeys: [.isRegularFileKey])
                if vals?.isRegularFile != true { continue }
                if url.pathExtension.lowercased() != "plist" { continue }
                rows.append(row(for: url, fm))
            }
        } else {
            skippedDirs.append("\(byHost.path)（ByHost 读不到或不存在）")
        }
        return (rows, skippedDirs)
    }

    static func isDirectory(_ path: String, _ fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// 夹具档：把**我们自己造**的十二种"看起来坏"与"确实在 macOS 上正常"的文件放进一棵假 home，
    /// 用与真 home 完全相同的采集路径过一遍，再和 `plutil -lint` 对读。
    ///
    /// 这一档存在的理由：真机上这一族几乎全是好的（本轮实测 625 条里 0 条解析失败），
    /// 所以"我们的判据会不会把好文件说成坏的"这件事**在真 home 上问不出来**——
    /// 只有把已知答案的样本摆在面前，才量得出两种判据各自的边界在哪。
    static func runSynthetic(root: String) {
        let fm = FileManager.default
        // 登记的键必须是**枚举返回的那个形态**：/tmp 是 /private/tmp 的软链，
        // 拿写进去的路径当键会一条都对不上（本探针第一跑就是这个现象，12 条全说"没登记期望"）。
        let canonRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        let prefs = URL(fileURLWithPath: canonRoot).appendingPathComponent("Library/Preferences")
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: canonRoot)
        try? fm.removeItem(atPath: canonRoot)
        try! fm.createDirectory(at: prefs.appendingPathComponent("ByHost"), withIntermediateDirectories: true)

        let dict: [String: Any] = ["enabled": true, "count": 3, "name": "MacMaster"]
        let bin = try! PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        let xml = try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        // OpenStep（老式 ASCII）这一条**不能**用 `PropertyListSerialization` 造——本机实测
        // `data(fromPropertyList:format:.openStep:)` 直接抛
        // "Property list format kCFPropertyListOpenStepFormat not supported for writing"
        // （探针第一跑就是被这一下打死的，所以这一句是量出来的，不是查来的）。
        // 手写一份是真的要问的问题：**读**这一族它支不支持——生产判据只读不写。
        let ascii = Data("{\n  enabled = 1;\n  count = 3;\n  name = MacMaster;\n}\n".utf8)
        let emptyDict = try! PropertyListSerialization.data(fromPropertyList: [String: Any](), format: .binary, options: 0)
        let arrRoot = try! PropertyListSerialization.data(fromPropertyList: ["a", 1], format: .binary, options: 0)
        let strRoot = try! PropertyListSerialization.data(fromPropertyList: "just a string", format: .xml, options: 0)

        let cases: [(name: String, expected: String, data: Data, mode: Int32)] = [
            ("valid-binary", "正常", bin, 0o600),
            ("valid-xml", "正常", xml, 0o600),
            ("valid-openstep", "正常", ascii, 0o600),
            ("empty-dict", "正常", emptyDict, 0o600),
            ("root-array", "正常但根不是字典", arrRoot, 0o600),
            ("root-string", "正常但根不是字典", strRoot, 0o600),
            ("zero-byte", "0 字节", Data(), 0o600),
            ("truncated-binary", "解析失败", bin.prefix(12), 0o600),
            ("garbage-text", "解析失败", Data("这不是 plist，是一段随便的文本\n".utf8), 0o600),
            ("xml-unclosed", "解析失败", xml.prefix(xml.count - 20), 0o600),
            ("perm-000", "读不到", bin, 0o000),
            // 这一条只有 8 个字节 = `bplist00` 魔数本身，后面什么都没有。
            // 本轮实测：`plutil -lint` 说 OK，Foundation 把它当 openStep 解析出一个非字典根。
            // 期望登记成「正常但根不是字典」而不是「解析失败」，是把这两把尺子共同的答复写下来——
            // 界面若把这种文件报成损坏，对照判据不认，那是一条没人能复核的主张。
            ("byhost-truncated", "正常但根不是字典", bin.prefix(8), 0o600),
        ]

        var expectedByPath: [String: String] = [:]
        for c in cases {
            let dir = c.name.hasPrefix("byhost-") ? prefs.appendingPathComponent("ByHost") : prefs
            let url = dir.appendingPathComponent("\(c.name).plist")
            try! c.data.write(to: url)
            try! fm.setAttributes([.posixPermissions: NSNumber(value: c.mode)], ofItemAtPath: url.path)
            // 期望按「`Library/Preferences/` 之后的相对段」登记，不按整条路径：
            // 枚举返回的是 `/private/tmp/…`，而 `resolvingSymlinksInPath()` 在本机对
            // `/tmp/…`（哪怕已经存在）并不换成 `/private/tmp`，两边永远对不上——
            // 第一跑 12 条全说"没登记期望"就是这个错位，不是判据错。
            expectedByPath[relKey(url.path)] = c.expected
        }

        let rows = collect(prefs: prefs, fm).rows
        let lint = plutilBatch(rows.map { $0.path })
        print("---- 夹具档：已知答案的样本过同一条采集路径 ----")
        print("样本数=\(rows.count)（造了 \(cases.count) 条）")
        var matched = 0, mismatched = 0
        for r in rows.sorted(by: { $0.path < $1.path }) {
            let expected = expectedByPath[relKey(r.path)] ?? "（没登记期望）"
            let got = kind(r.verdict)
            let ok = got == expected
            if ok { matched += 1 } else { mismatched += 1 }
            print("\(ok ? "  " : "⚠ ")\(label(r.path))  bytes=\(r.bytes)  Foundation=\(got)  plutil=\"\(lintText(lint, r.path))\"  期望=\(expected)  \(detail(r.verdict))")
        }
        print("与期望一致=\(matched)  不一致=\(mismatched)")

        // 另一种对读：不看我们的期望登记，只看**两种判据本身**在这些样本上分不分得住。
        var judgeDiff = 0
        for r in rows {
            let fBad = isBad(r.verdict)
            let pBad = (lint[r.path] ?? "") != "OK"
            if fBad != pBad {
                judgeDiff += 1
                print("⚠ 两种判据在这一条上分开：\(label(r.path))  Foundation=\(kind(r.verdict))（\(fBad ? "算异常" : "不算异常")）  plutil=\"\(lintText(lint, r.path))\"（\(pBad ? "算异常" : "不算异常")）")
            }
        }
        print("Foundation 与 plutil 判「异常/不异常」分开的条数=\(judgeDiff)")

        if ProcessInfo.processInfo.environment["KEEP_SYNTH"] == nil {
            // URL 直接插值会打成 file:///…，所以这里一律走 .path。
            try? fm.setAttributes([.posixPermissions: 0o600],
                                  ofItemAtPath: prefs.appendingPathComponent("perm-000.plist").path)
            let liveRoot = URL(fileURLWithPath: canonRoot).resolvingSymlinksInPath().path
            try? fm.removeItem(atPath: liveRoot)
            print("夹具已清理：\(liveRoot)")
        } else {
            print("KEEP_SYNTH 已设，夹具留在：\(canonRoot)")
        }
    }

    /// 界面上会进"这一条有问题"那一栏的那些类别。
    /// **「解析成功但根对象不是字典」不在这里**——本轮夹具档量到一条 8 字节的 `bplist00`
    /// （只有魔数、后面什么都没有），`plutil -lint` 说 OK、Foundation 也能解析出一个非字典的根，
    /// 把它算进"损坏"会造出一个对照判据不认的假故障。
    static func isBad(_ v: Verdict) -> Bool {
        switch v {
        case .parsed: return false
        default: return true
        }
    }

    static func kind(_ v: Verdict) -> String {
        switch v {
        case .unreadable: return "读不到"
        case .empty: return "0 字节"
        case .parseFailed: return "解析失败"
        case .parsed(_, let root): return root == "dict" ? "正常" : "正常但根不是字典"
        }
    }

    /// 只有被判为异常的那些才需要细节；正常行只打类别，表才不会宽到没法读。
    static func detail(_ v: Verdict) -> String {
        switch v {
        case .unreadable(let e), .parseFailed(let e): return e
        case .parsed(let f, _): return "格式=\(f)"
        case .empty: return ""
        }
    }

    static func row(for url: URL, _ fm: FileManager) -> Row {
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? Int) ?? -1
        let mtime = (attrs?[.modificationDate] as? Date).map { date in
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        } ?? "未知"

        let verdict: Verdict
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if data.isEmpty {
                verdict = .empty
            } else {
                var fmt = PropertyListSerialization.PropertyListFormat.xml
                do {
                    let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &fmt)
                    verdict = .parsed(format: name(fmt), root: rootName(obj))
                } catch {
                    verdict = .parseFailed(describe(error))
                }
            }
        } catch {
            verdict = .unreadable(describe(error))
        }
        return Row(path: url.path, bytes: bytes, modified: mtime, verdict: verdict)
    }

    static func name(_ f: PropertyListSerialization.PropertyListFormat) -> String {
        switch f {
        case .xml: return "xml"
        case .binary: return "binary"
        case .openStep: return "openStep"
        @unknown default: return "未知(\(f.rawValue))"
        }
    }

    static func rootName(_ obj: Any) -> String {
        switch obj {
        case is [String: Any]: return "dict"
        case is [Any]: return "array"
        case is String: return "string"
        case is Data: return "data"
        case is Date: return "date"
        case is NSNumber: return NSNumberIsBool(obj) ? "bool" : "number"
        default: return "其他"
        }
    }

    static func NSNumberIsBool(_ obj: Any) -> Bool {
        guard let n = obj as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            return "Cocoa \(ns.code)：\(ns.localizedDescription)"
        }
        return "\(ns.domain) \(ns.code)：\(ns.localizedDescription)"
    }

    // MARK: - 汇总

    static func report(_ rows: [Row], home: String, skippedDirs: [String],
                       scanMillis: Double, lint: [String: String]) {
        print("home=\(home)")
        print("扫到的 .plist 条数=\(rows.count)")
        for s in skippedDirs { print("⚠ 整层没读到：\(s)") }
        print(String(format: "Foundation 一趟（枚举+读取+解析，不含 plutil 对照）耗时=%.0f ms", scanMillis))

        var ok = 0, empty = 0, failed = 0, unreadable = 0
        var formats: [String: Int] = [:]
        var roots: [String: Int] = [:]
        var nonDictRoots: [Row] = []
        var flagged: [Row] = []
        for r in rows {
            switch r.verdict {
            case .parsed(let f, let root):
                ok += 1
                formats[f, default: 0] += 1
                roots[root, default: 0] += 1
                if root != "dict" { nonDictRoots.append(r) }
            case .empty: empty += 1; flagged.append(r)
            case .parseFailed: failed += 1; flagged.append(r)
            case .unreadable: unreadable += 1; flagged.append(r)
            }
        }
        print("解析成功=\(ok)  0 字节=\(empty)  解析失败=\(failed)  读不到=\(unreadable)")
        print("格式分布: \(sorted(formats))")
        print("根对象分布: \(sorted(roots))")

        print("")
        print("---- 被 Foundation 判为非正常的每一条（含 plutil 对照）----")
        if flagged.isEmpty { print("（无）") }
        for r in flagged {
            print("\(label(r.path))  bytes=\(r.bytes)  mtime=\(r.modified)  plutil=\"\(lintText(lint, r.path))\"  \(verdictText(r.verdict))")
        }

        print("")
        print("---- 解析成功但根对象不是字典（对照档：这类算不算异常要人决定）----")
        if nonDictRoots.isEmpty { print("（无）") }
        for r in nonDictRoots.prefix(20) {
            print("\(label(r.path))  bytes=\(r.bytes)  mtime=\(r.modified)  plutil=\"\(lintText(lint, r.path))\"  \(verdictText(r.verdict))")
        }
        if nonDictRoots.count > 20 { print("……共 \(nonDictRoots.count) 条，只打前 20 条") }

        print("")
        print("---- 两种判据的全量对读（Foundation × plutil，每一条都比）----")
        var agreeBad = 0, foundationStricter = 0, plutilStricter = 0, unmatched = 0
        for r in rows {
            guard let status = lint[r.path] else { unmatched += 1; continue }
            let plutilOK = status == "OK"
            let foundationOK: Bool
            if case .parsed = r.verdict { foundationOK = true } else { foundationOK = false }
            if foundationOK && plutilOK { continue }
            if !foundationOK && !plutilOK { agreeBad += 1; continue }
            if !foundationOK && plutilOK {
                foundationStricter += 1
                print("⚠ Foundation 说不正常、plutil 说 OK：\(label(r.path))  \(verdictText(r.verdict))")
            } else {
                plutilStricter += 1
                print("⚠ plutil 说不正常、Foundation 说 OK：\(label(r.path))  plutil=\"\(status)\"  \(verdictText(r.verdict))")
            }
        }
        print("全量=\(rows.count)  都正常=\(rows.count - agreeBad - foundationStricter - plutilStricter - unmatched)  "
              + "都不正常=\(agreeBad)  只有 Foundation 报=\(foundationStricter)  只有 plutil 报=\(plutilStricter)  "
              + "对不上号的行=\(unmatched)")

        print("")
        print("---- 受保护名那一族（com.apple.* / .GlobalPreferences* / loginwindow.plist）的真实构成 ----")
        let protected = rows.filter { isProtectedName($0.path) }
        let protectedBad = protected.filter { isParsed($0.verdict) == false }
        print("受保护名条数=\(protected.count)  其中被 Foundation 判为非正常=\(protectedBad.count)")
        for r in protectedBad {
            print("  \(label(r.path))  bytes=\(r.bytes)  plutil=\"\(lintText(lint, r.path))\"  \(verdictText(r.verdict))")
        }

        print("")
        print("---- 这一族里有多少条是我们自己的单测留下的（名字含 Tests）----")
        let ours = rows.filter { ($0.path as NSString).lastPathComponent.contains("Tests") }
        let oursBytes = ours.reduce(0) { $0 + max(0, $1.bytes) }
        print("条数=\(ours.count)  合计字节=\(oursBytes)")
        for r in ours.prefix(12) {
            print("  \(label(r.path))  bytes=\(r.bytes)  mtime=\(r.modified)  \(verdictText(r.verdict))")
        }
        if ours.count > 12 { print("  ……共 \(ours.count) 条，只打前 12 条") }
    }

    static func isParsed(_ v: Verdict) -> Bool {
        if case .parsed = v { return true }
        return false
    }

    static func isProtectedName(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.hasPrefix("com.apple.") || name.hasPrefix(".GlobalPreferences") || name == "loginwindow.plist"
    }

    static func label(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// `Library/Preferences/` 之后那一段，用来把"造的时候"和"枚举回来"两种形态对齐。
    static func relKey(_ path: String) -> String {
        guard let r = path.range(of: "/Library/Preferences/") else {
            return (path as NSString).lastPathComponent
        }
        return String(path[r.upperBound...])
    }

    static func lintText(_ lint: [String: String], _ path: String) -> String {
        lint[path] ?? "plutil 的输出里没有这一条"
    }

    static func sorted(_ d: [String: Int]) -> String {
        d.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    static func verdictText(_ v: Verdict) -> String {
        switch v {
        case .unreadable(let e): return "Foundation=读不到 \(e)"
        case .empty: return "Foundation=0 字节"
        case .parseFailed(let e): return "Foundation=解析失败 \(e)"
        case .parsed(let f, let r): return "Foundation=正常(\(f), 根=\(r))"
        }
    }

    /// 一次 spawn 把全部路径交给 `plutil -lint`，收回每条一行「<路径>: <状态>」。
    /// 认路径用 `hasPrefix(path + ": ")`（plutil 把原路径逐字打在行首），不靠切冒号——
    /// 失败信息里也有冒号。认不出是哪一个的行走「对不上号」那一格，不猜。
    /// 只作对照 oracle 用，生产实现不走这条路。
    static func plutilBatch(_ paths: [String]) -> [String: String] {
        guard paths.isEmpty == false else { return [:] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        p.arguments = ["-lint"] + paths
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            print("⚠ plutil 对照跑不起来：\(describe(error))（下面所有对照格都会空着）")
            return [:]
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        var status: [String: String] = [:]
        for rawLine in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if let hit = paths.first(where: { line.hasPrefix("\($0): ") }) {
                status[hit] = String(line.dropFirst(hit.count + 2))
            }
        }
        return status
    }
}
