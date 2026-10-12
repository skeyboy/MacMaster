//
//  PreferencesAudit.swift — 「偏好文件」tab 的只读判定（P34b，v1.1 §2 第 3 条）
//
//  这一屏只回答一句话：`~/Library/Preferences` 里有没有读不出来的 plist。
//  判据、代价与"为什么不删"的账在 `docs/analysis/optimizer-corrupt-preferences.md`：
//  不删、不改名、不 `defaults delete`、不为此 spawn `plutil`、不请求 FDA、不碰沙盒容器。
//  所以这里没有 `DeletionGuard`、没有 `FileTrashService`，一行写盘都没有。
//

import Foundation

// MARK: - 四态

/// 一个 plist 的四种结局。
///
/// **「读不到」与「损坏」是两件事，界面上也不许共用图标**：本机实测那 11 条读不到的文件
/// 属主就是当前用户、权限位 0600，拒它的是 macOS 的按文件保护（errno 是
/// `Operation not permitted`），不是内容坏了；而"给了 FDA 的进程读不读得到"这件事
/// 至今没量过，所以这一栏只能说"我们没看到"，不能说"它们是坏的"。
public enum PrefsVerdict: Equatable, Sendable {
    case unreadable(reason: String)
    /// 半路创建的 0 字文件：可能是上次写入中断，不等于"这份偏好已经坏了"。
    case zeroByte
    case unparsable(reason: String)
    /// 解析成功。`root` 是根对象类型名（`dict` / `array` / …）。
    ///
    /// **「解析成功但根不是字典」不在 `isBad` 里**：P34a 夹具档量到一条 8 字节的 `bplist00`
    /// （只有魔数、后面什么都没有），`plutil -lint` 给 OK、Foundation 把它当 openStep 解析出
    /// 一个非字典根——两把尺子都说正常。把它报成损坏会造出一条对照判据不认的假故障。
    case parsed(root: String)

    /// 语义是"要不要占那一栏"，不是"是不是坏了"（0 字节那一档的文案就是为这个区别留的）。
    public var isBad: Bool {
        switch self {
        case .parsed: return false
        case .unreadable, .zeroByte, .unparsable: return true
        }
    }

    /// 独立成栏依据：`unreadable` 走「这一族我们没看到」，另外两个坏态走「读不出来的那些」。
    public var isUnreadable: Bool {
        if case .unreadable = self { return true }
        return false
    }

    /// 档位名照 §5 那张表的「界面位置」列，不另造词。
    public var badgeText: String {
        switch self {
        case .unreadable: return "读不到"
        case .zeroByte: return "可能是写到一半"
        case .unparsable: return "读不成字典"
        case .parsed(let root): return root == "dict" ? "正常" : "根不是字典"
        }
    }
}

// MARK: - 行

public struct PreferenceFileCheck: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    /// ByHost 那一层与顶层不是同一条采集路径（顶层 maxdepth 1、ByHost 递归），
    /// 界面上要能看出这一条来自哪一层。
    public let inByHost: Bool
    /// nil = 连属性都没读到。绝不折成 0——"没量到"和"0 字节"是两件事。
    public let bytes: Int?
    public let modified: Date?
    public let verdict: PrefsVerdict

    public init(id: String, name: String, path: String, inByHost: Bool,
                bytes: Int?, modified: Date?, verdict: PrefsVerdict) {
        self.id = id
        self.name = name
        self.path = path
        self.inByHost = inByHost
        self.bytes = bytes
        self.modified = modified
        self.verdict = verdict
    }
}

// MARK: - 一趟的结果

/// 三段耗时拆分。P34a 只量到"一趟 226 ms/625 条"这一格，
/// 而预算数值要由拆分来定，所以这里当场分开计（枚举 / 读取 / 解析）。
public struct PrefsMillis: Equatable, Sendable {
    public var enumerate: Double
    public var read: Double
    public var parse: Double

    public init(enumerate: Double = 0, read: Double = 0, parse: Double = 0) {
        self.enumerate = enumerate
        self.read = read
        self.parse = parse
    }

    public var total: Double { enumerate + read + parse }
}

public struct PreferencesScan: Equatable, Sendable {
    /// 这一趟真正下过判据的那些文件（含正常）。预算截断时它小于 `foundFiles`。
    public let rows: [PreferenceFileCheck]
    /// 采集时整层没读到的目录（`~/Library/Preferences` 本身读不到 / 不存在就在这一栏）。
    /// **它必须能说话**：整层没读到却说"没有发现"，是把"没看"渲染成"干净"。
    public let skippedRoots: [String]
    /// 跳过的非常规条目（软链、目录、套接字）。它们没下判据，所以不进"检查过 N 个"。
    public let skippedNonRegular: Int
    /// 枚举到的常规 .plist 总条数（截断前），用来能说"剩下的 K 个没看"。
    public let foundFiles: Int
    /// 撞到时间预算就停：页头那句话随之改变，不许静默少报。
    public let isPartial: Bool
    public let millis: PrefsMillis

    public init(rows: [PreferenceFileCheck], skippedRoots: [String], skippedNonRegular: Int,
                foundFiles: Int, isPartial: Bool, millis: PrefsMillis) {
        self.rows = rows
        self.skippedRoots = skippedRoots
        self.skippedNonRegular = skippedNonRegular
        self.foundFiles = foundFiles
        self.isPartial = isPartial
        self.millis = millis
    }

    public var inspectedCount: Int { rows.count }
    public var parsedCount: Int { rows.filter { !$0.verdict.isBad }.count }
    public var unreadableCount: Int { rows.filter { $0.verdict.isUnreadable }.count }
    /// 解析成功但根不是字典的那些：不列行（`isBad` 不含它），只在有的时候进脚注。
    public var nonDictRootCount: Int {
        rows.filter { if case .parsed(let root) = $0.verdict { return root != "dict" } else { return false } }.count
    }
    public var badRows: [PreferenceFileCheck] { rows.filter { $0.verdict.isBad && !$0.verdict.isUnreadable } }
    public var unreadableRows: [PreferenceFileCheck] { rows.filter { $0.verdict.isUnreadable } }
    /// 预算截断掉的那一段（"剩下的 K 个没看"）。
    public var notInspectedCount: Int { max(0, foundFiles - rows.count) }
}

// MARK: - 判定

public struct PrefsListing: Sendable {
    public let files: [URL]
    public let skippedRoots: [String]
    public let skippedNonRegular: Int

    public init(files: [URL], skippedRoots: [String], skippedNonRegular: Int) {
        self.files = files
        self.skippedRoots = skippedRoots
        self.skippedNonRegular = skippedNonRegular
    }

    public static let empty = PrefsListing(files: [], skippedRoots: [], skippedNonRegular: 0)
}

public enum PreferencesAuditor {

    /// 默认预算。**P34b 现量**（`./Scripts/p34b-prefs-scan-probe.sh` →
    /// `docs/verification/p34b-prefs/scan-shape.log`）：本机 625 条一趟，暖趟三十毫秒量级、
    /// 进程内第一趟冷的一百到两百毫秒，**解析始终是大头**（三段拆分是 P34a 留的待测项）。
    /// 规模档（`--scale` → `scale-shape.log`，假 home）：2000 条小文件、200 条约 48 KB 文件
    /// 也都在一百毫秒以内。
    /// **这里故意不写死毫秒数**：同一批文件两跑的绝对值能差三倍（机器负载），
    /// 把会漂的数写进注释，下一跑 log 就和注释打架了——量级要重出就按上面那两条命令各跑一次。
    /// 2000 ms 是本机冷趟的十倍以上，也就是说页头那句"剩下的 K 个没看"在这台机器上永远不会出现：
    /// 这一档是防撞针（外推到上万条大文件、或极慢磁盘才可能撞上），
    /// 所以 `partial` 那一档只能靠夹具拍（夹具把预算压到 12 ms 时截断真会发生，见 `scale-shape.log`）。
    /// 不抄参考实现 Mole 的那 15 秒：它那一趟是"边扫边删"，我们这一趟只是下判据。
    public static let defaultBudgetMillis: Double = 2_000

    /// 保护名单：与 Mole 那一支同源（`docs/github-references/Mole/lib/optimize/maintenance.sh:7-23`）。
    /// 这一族我们照样下判据、照样列行——保护的是"别代删"，不是"别看"。
    public static func isProtectedName(_ name: String) -> Bool {
        name.hasPrefix("com.apple.") || name.hasPrefix(".GlobalPreferences") || name == "loginwindow.plist"
    }

    /// 顶层 maxdepth 1 + `ByHost` 递归，跟 P34a 探针的采集路径一致。
    /// 顶层不跳过隐藏文件：`.GlobalPreferences.plist` 恰好是点开头的，用
    /// `skipsHiddenFiles` 会把它整个漏掉。
    ///
    /// `ByHost` 用 `enumerator(at:)`：本机实测它**不跟随目录软链**（P34b 现量：造一个指向父目录的
    /// 环 + 一个指向 `ByHost` 之外的软链目录，两种都停在原地、`isRegularFile=false`），
    /// 所以既不会有环，也不会把"检查过 N 个"数到这一族外面去。
    public static func list(prefs: URL, fm: FileManager = .default) -> PrefsListing {
        var files: [URL] = []
        var skipped: [String] = []
        var nonRegular = 0

        if let items = try? fm.contentsOfDirectory(at: prefs, includingPropertiesForKeys: [
            .isRegularFileKey, .isSymbolicLinkKey,
        ], options: []) {
            for item in items where item.pathExtension.lowercased() == "plist" {
                let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { nonRegular += 1; continue }
                files.append(item)
            }
        } else {
            skipped.append("\(prefs.path)（顶层读不到或不存在）")
        }

        let byHost = prefs.appendingPathComponent("ByHost")
        if let en = fm.enumerator(at: byHost, includingPropertiesForKeys: [.isRegularFileKey], options: []) {
            for case let url as URL in en {
                guard url.pathExtension.lowercased() == "plist" else { continue }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { nonRegular += 1; continue }
                files.append(url)
            }
        }   // ByHost 读不到或不存在都不算异常：这一层本来就可能没有。

        return PrefsListing(files: files, skippedRoots: skipped, skippedNonRegular: nonRegular)
    }

    /// 判据本体：四态从一次读取的结果里长出来。不 spawn `plutil`——P34a 那 12 条夹具上
    /// Foundation 与 `plutil -lint` 零分歧，所以这条约束不欠账
    /// （对读原文见 `docs/analysis/optimizer-corrupt-preferences.md` §4）。
    public static func verdict(from read: Result<Data, Error>) -> PrefsVerdict {
        let data: Data
        do {
            data = try read.get()
        } catch {
            return .unreadable(reason: describe(error))
        }
        if data.isEmpty { return .zeroByte }
        var format = PropertyListSerialization.PropertyListFormat.xml
        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
            return .parsed(root: rootName(object))
        } catch {
            return .unparsable(reason: describe(error))
        }
    }

    /// `.mappedIfSafe`：大文件走内存映射。**这一句不构成"低内存"的主张**——
    /// 读全量 plist 的内存代价 P34a 没量过。
    public static func readData(at url: URL) -> Result<Data, Error> {
        Result { try Data(contentsOf: url, options: .mappedIfSafe) }
    }

    /// 全注入的那一层：采集、读取、时钟都能替，所以预算截断在单测里钉得住。
    /// 读取与解析**各计一次时钟**，三段耗时因此是量出来的而不是猜的
    /// （P34a 只量到"一趟 226 ms/625 条"，拆分是它留的待测项）。
    ///
    /// 预算检查放在**每个文件之前**（不是每一千个之后）：一条 42 字节的空域和一条
    /// 十几 KB 的 MobileSMS 不是一个价，粗粒度会在慢机器上多跑几十秒还不说。
    public static func scan(prefs: URL,
                            budgetMillis: Double = defaultBudgetMillis,
                            listing: (URL) -> PrefsListing = { list(prefs: $0) },
                            read: (URL) -> Result<Data, Error> = readData,
                            attributes: (URL) -> (bytes: Int?, modified: Date?) = fileAttributes,
                            clock: @escaping () -> Double = { millisNow() }) -> PreferencesScan {
        let started = clock()
        let found = listing(prefs)
        let enumerateMs = clock() - started

        var rows: [PreferenceFileCheck] = []
        var readMs = 0.0, parseMs = 0.0
        var partial = false
        for url in found.files {
            if clock() - started > budgetMillis { partial = true; break }
            let tRead0 = clock()
            let data = read(url)
            let tRead1 = clock()
            let verdict = verdict(from: data)
            parseMs += clock() - tRead1
            readMs += tRead1 - tRead0
            let attr = attributes(url)
            rows.append(PreferenceFileCheck(
                id: url.path, name: url.lastPathComponent, path: url.path,
                inByHost: url.path.contains("/ByHost/"),
                bytes: attr.bytes, modified: attr.modified,
                verdict: verdict
            ))
        }
        return PreferencesScan(
            rows: rows, skippedRoots: found.skippedRoots,
            skippedNonRegular: found.skippedNonRegular,
            foundFiles: found.files.count, isPartial: partial,
            millis: PrefsMillis(enumerate: enumerateMs, read: readMs, parse: parseMs)
        )
    }

    /// 真机入口。home 由调用方给（单测里指假 home，取证脚本指真 home）。
    public static func liveScan(home: String,
                               budgetMillis: Double = defaultBudgetMillis) -> PreferencesScan {
        let prefs = URL(fileURLWithPath: home).appendingPathComponent("Library/Preferences")
        return scan(prefs: prefs, budgetMillis: budgetMillis)
    }

    // MARK: - 内部

    public static func fileAttributes(_ url: URL) -> (bytes: Int?, modified: Date?) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return (values?.fileSize, values?.contentModificationDate)
    }

    static func rootName(_ object: Any) -> String {
        switch object {
        case is [String: Any]: return "dict"
        case is [Any]: return "array"
        case is String: return "string"
        case is Data: return "data"
        case is Date: return "date"
        case is NSNumber: return isBool(object) ? "bool" : "number"
        default: return "其他"
        }
    }

    static func isBool(_ object: Any) -> Bool {
        guard let number = object as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain { return "Cocoa \(ns.code)：\(ns.localizedDescription)" }
        return "\(ns.domain) \(ns.code)：\(ns.localizedDescription)"
    }

    /// 默认档的时钟。public 是因为它同时是 public `scan` 的默认参数（Swift 要求）。
    public static func millisNow() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
    }
}

// MARK: - 文案

/// 「允许说什么 / 禁止说什么」的账在 `docs/analysis/optimizer-corrupt-preferences.md` §5，
/// 这里是它的代码形态：解析成功的那些不表扬（它们只进计数），
/// 根不是字典的不说"损坏"（两把尺子都不认为那是坏），读不到的独立成栏、不与"损坏"共用图标。
public enum PreferencesCopy {
    public static let badSection = "读不出来或空的那些"
    public static let unreadableSection = "这一族我们没看到"

    /// **权限位不写进来**：P34a 在本机量到的是"属主是你、权限位 0600 却仍被拒"，
    /// 而生产实现读的是判据、不是 mode 位——把一台机器的读数写成每台都成立的断言就是假话。
    public static func unreadableNote(_ count: Int) -> String {
        "系统对 \(count) 个文件拒绝读取。这不代表它们坏了，也不代表它们没坏。"
    }

    /// 主人名与建议进 `caveat`（这里是 `advice`），不进单行截断的 `reason`——
    /// 口径同 `DevToolCacheAudit` 那一族：`reason` 会截，`advice` 换行不截。
    public static func advice(_ check: PreferenceFileCheck) -> String {
        switch check.verdict {
        case .zeroByte:
            return "这个文件是空的，可能是上次写入中断。"
        case .unparsable:
            return "这份偏好文件读不出来。要恢复它得由那个 app 自己做（重设它的偏好），MacMaster 不动它。"
        case .unreadable:
            return "这一条我们读不到。这不代表它坏了，也不代表它没坏。"
        case .parsed:
            return ""
        }
    }

    /// 页头那句话：B 档的预算截断必须说得出声，不许静默少报。
    public static func headline(_ scan: PreferencesScan) -> String {
        var text = "检查过 \(scan.inspectedCount) 个偏好文件"
        if scan.isPartial {
            text += "就到了时间预算，剩下的 \(scan.notInspectedCount) 个没看"
        }
        if scan.unreadableCount > 0 {
            text += "；其中 \(scan.unreadableCount) 个我们没能读"
        }
        return text + "。"
    }

    public static let footnote = "这一屏不删、不改这些文件，也不会替你重设任何 app 的偏好。"
        + "MacMaster 只做只读判定，恢复得由那个 app 自己在下次启动时重设。"

    /// 「解析成功但根不是字典」不列行；只有真有这类文件时才以脚注提一句（§5 那一行的口径）。
    public static func nonDictRootNote(_ count: Int) -> String {
        "另有 \(count) 个文件解析成功但根不是字典——两种判据都不认为这是坏，所以它们不列在上面。"
    }

    /// 整层没读到（`~/Library/Preferences` 读不到或不存在）。这一栏不许把"没看"渲染成"干净"。
    public static func skippedRootsNote(_ roots: [String]) -> String {
        roots.joined(separator: "；")
    }
}
