import Foundation

// MARK: - 跨卷枚举（纯判定 + 只读快照）
//
// 这一层的形状由 P35a 的三笔实测决定（`docs/analysis/disk-volume-enumeration.md`）：
// ① Foundation 默认档枚举回来的 14 条里 13 条是系统切片、只读快照卷、`map auto_home` 占位
//    （§3）——"你能扫哪些卷"的名单不能把枚举全量直接端上去；
// ② "同一块盘被数两次"的真实形态不是 fsid，是**同一对容量数**：一个 APFS 容器的几个挂载点
//    报的是同一份 total/avail（容器 disk3：6 个挂载点、1 对容量数，§4）；
// ③ "最满的那卷优先"只能跑在候选根上、且必须用使用率：绝对字节那把键在本机把用户真正要清的盘
//    排到第 9 / 共 14（§5）。
//
// 判据与读取分开（与 `Packages/MMUninstaller` 的 `RunningAppProbe` 同一套规矩）：
// `VolumeRoots` 是纯函数，只吃 `VolumeRootRow` 这种值类型，四条规则连同夹具档位全能在单测里跑完；
// `VolumeRootProbe.snapshot()` 才是那一句 Foundation 调用，它不假装单测能读到系统状态。
// 放在 MMCore 而不是 MMDisk：消费这一格的有两处——磁盘页的徽标位和概览页页脚的"个卷"，
// 而后者在壳层（`Sources/MacMaster`），壳层不该为了一个只读系统枚举去 import 一个功能模块。
//
// 这一层只到"看见并说出来"为止。下拉选卷、换根重扫是 P35a §9 的 C 档，另开版本：
// 今天用户要换卷，走的是磁盘页原有的「选择目录」。

/// 一个挂载点的只读快照。全是值，所以"这台机器上有几个能扫的卷"这件事
/// 可以用假数据在单测里问完，不必真插一块盘。
public struct VolumeRootRow: Sendable, Equatable {
    public let path: String
    /// Foundation 的 `volumeIsBrowsable`。P35a §3 实测它与挂载表的 `MNT_DONTBROWSE`
    /// 在本机 14 条上**逐条一致**，所以"要不要显示这一条"这一格不需要第二把尺子，
    /// 也不需要 spawn `mount`。
    public let browsable: Bool
    public let isDirectory: Bool
    /// nil = 这一格没读到。读不到不等于 0：0 会被 §6 的筛选当成"自动挂载占位"扔掉，
    /// 而"没读到"在界面上另有说法（不报占比）。
    public let totalBytes: UInt64?
    /// 普通口径（`volumeAvailableCapacity`）。**去重键用它**：§4 的分组就是在这对上量的
    /// （启动卷那一对在本机对应 5 个挂载点）。
    public let availRegularBytes: UInt64?
    /// 重要用途口径（`volumeAvailableCapacityForImportantUsage`）。磁盘页的进度条与概览页
    /// 早就选了这一把（`MMDisk.swift` 的 `freeSize`、`SystemSampler.swift` 的卷那一节），
    /// 新名单沿用同一把尺子，不引入第四把。
    public let availImportantBytes: UInt64?

    public init(path: String, browsable: Bool, isDirectory: Bool,
                totalBytes: UInt64?, availRegularBytes: UInt64?, availImportantBytes: UInt64?) {
        self.path = path
        self.browsable = browsable
        self.isDirectory = isDirectory
        self.totalBytes = totalBytes
        self.availRegularBytes = availRegularBytes
        self.availImportantBytes = availImportantBytes
    }
}

/// 可用容量的口径。排序键必须带它，不许在实现里即兴选一把尺子（§5 第 3 条）。
public enum VolumeCapacityCaliber: String, Sendable, CaseIterable {
    /// 含 purgeable，与"关于本机"同量级。生产路径用这一把。
    case important
    /// 不含 purgeable。磁盘页的注释记着它为什么不能当进度条的分母：
    /// 它把可清除空间算成已用，常年 95% 满。
    case regular

    func avail(of row: VolumeRootRow) -> UInt64? {
        switch self {
        case .important: return row.availImportantBytes
        case .regular: return row.availRegularBytes
        }
    }
}

/// 一个"我们能扫的卷"。
public struct VolumeRoot: Sendable, Equatable {
    public let path: String
    public let totalBytes: UInt64
    /// nil = 所选口径读不到可用容量。这一格不许报占比，也不许当成 0%（§9 文案合同最后一行）。
    public let availBytes: UInt64?

    public init(path: String, totalBytes: UInt64, availBytes: UInt64?) {
        self.path = path
        self.totalBytes = totalBytes
        self.availBytes = availBytes
    }

    /// 使用率。读不到可用 = nil，不是"满"也不是"空"：本机 13 条系统卷的 `avail重要` 全是 0，
    /// 那个 0 的含义是"这一口径没数"，不是"一个字节都不剩"（§5 第 1 条）。
    public var usedRatio: Double? {
        guard let availBytes, totalBytes > 0 else { return nil }
        let used = totalBytes > availBytes ? totalBytes - availBytes : 0
        return Double(used) / Double(totalBytes)
    }
}

// MARK: 纯判定

public enum VolumeRoots {

    /// ① 候选根筛选：`browsable && isDirectory && total > 0`（§6）。
    /// 三把闸门各自兜住一类实测见过的东西：
    /// `browsable` 挡系统切片与快照卷（本机 13 条），`isDirectory` 挡 devfs 这类稀疏挂载，
    /// `total > 0` 挡 `map auto_home` 那种占位（它排进"最满优先"时是 0 B 打头，§5 表第四行）。
    static func passesFilter(_ row: VolumeRootRow) -> Bool {
        guard row.browsable, row.isDirectory else { return false }
        guard let total = row.totalBytes, total > 0 else { return false }
        return true
    }

    /// ② 去重键：（总容量, 普通口径可用）这一对数。
    /// 为什么不用 fsid 也不用设备名：§4 实测默认档里没有任何一个 fsid 对应两条以上路径，
    /// 而同一对容量数在本机对应 5 个挂载点——按前者去重等于不去重，按后者去重才压成 1 条。
    /// 已知代价：同一型号、同样用量的两块独立外置盘会被并成一条。本机零样本（§11.1），
    /// 真撞上时要加的是设备名这一维，不是把这一格改成"不去重"。
    static func capacityKey(of row: VolumeRootRow) -> String {
        "\(row.totalBytes.map(String.init) ?? "—")|\(row.availRegularBytes.map(String.init) ?? "—")"
    }

    /// 同一对容量数留一条代表。代表选**路径最短**的那个：本机就是 `/` 而不是
    /// `/System/Volumes/Preboot`（那一族的 5 条里只有 `/` 是可浏览的，所以这条规则
    /// 在生产路径上是兜底，在单测里才是主角）。输入顺序不影响结果。
    static func dedupe(_ rows: [VolumeRootRow]) -> [VolumeRootRow] {
        var kept: [String: VolumeRootRow] = [:]
        for row in rows {
            let key = capacityKey(of: row)
            if let current = kept[key], !preferred(row, over: current) { continue }
            kept[key] = row
        }
        return Array(kept.values)
    }

    private static func preferred(_ candidate: VolumeRootRow, over current: VolumeRootRow) -> Bool {
        if candidate.path.count != current.path.count { return candidate.path.count < current.path.count }
        return candidate.path < current.path
    }

    /// ③+④ 排序：使用率降序（最满的那卷优先），**读不到可用的排最后**。
    /// 同分按路径升序，所以输出与输入顺序无关——取证时喂进去的顺序不该改变画面。
    static func sorted(_ roots: [VolumeRoot]) -> [VolumeRoot] {
        roots.sorted { a, b in
            switch (a.usedRatio, b.usedRatio) {
            case let (x?, y?):
                if x != y { return x > y }
            case (nil, nil):
                break
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
            return a.path < b.path
        }
    }

    /// 快照 → 这份机器上"我们能扫的卷"，最满的在前。默认重要用途口径。
    /// 不碰文件系统、不碰 NSWorkspace/Foundation，所以四条规则的每一档都能在单测里跑完。
    public static func candidates(from rows: [VolumeRootRow],
                                  caliber: VolumeCapacityCaliber = .important) -> [VolumeRoot] {
        let kept = dedupe(rows.filter(passesFilter))
        return sorted(kept.map { row in
            VolumeRoot(path: row.path, totalBytes: row.totalBytes ?? 0, availBytes: caliber.avail(of: row))
        })
    }

    /// 卸载页与应用监听要看的**外接卷挂载点** = 候选根里除启动卷之外的那些。
    ///
    /// 复用 `candidates(from:)` 而不是只看 `browsable`：这一步得连带容量去重。
    /// 本机本轮实测（`FileManager.mountedVolumeURLs(options: [])` 14 条，只有 `/` 是 browsable）：
    /// `/Volumes/Recovery` 与 `/` 报同一对容量数（494384795648 / 24033464320），
    /// 一块容器的第二个挂载点如果不去重就会被列两遍，`AppFolderWatcher` 于是为同一个
    /// `/Applications` 开两个 kqueue —— 装卸事件成双出现，那是监听侧的假话，不是功能的功劳。
    public static func nonBootVolumePaths(from rows: [VolumeRootRow]) -> [String] {
        candidates(from: rows).map(\.path).filter { $0 != "/" }
    }
}

// MARK: 夹具档位（`MM_VOLUME_FIXTURE`）

/// 界面上那三档本机拍不出来的分支，由这一档合成快照。
///
/// 本机候选根恒为 1（一块内部盘，`/Volumes` 是空的），所以"还有 N 卷"这一句和
/// "读不到卷列表"那一句**只能由合成值出照片**——照片证明的是界面会写这句话、放得下这句话，
/// 不证明这台机器真有两块盘。每条 .log 里都留一行 stderr 痕迹，把"档位生效了"与
/// "档位被忽略、画面恰好同形"分开（P6.6 那两张 md5 相同的照片就是这个坑）。
public enum VolumeFixtureTier: String, MMHookKeyed, CaseIterable, Sendable {
    /// 不注入：读这台机器。
    case off
    /// 两条候选根：本机那条真的形状 + 一条 `/Volumes/…` 夹具卷。正分支（N=1）靠它。
    case two
    /// 有挂载点、但没有一条能当候选根（全被 browsable 挡掉）。"缺席就是缺席"那一档。
    case zero
    /// 枚举一行都没给出来（nil）。"这里不猜数字"那一档。
    case fail

    public var hookKey: String { rawValue }

    /// 生效时写给 stderr 的那一行。**做成纯函数是为了钉住插值**：这一族第一版把
    /// `\(tier.rawValue)` 漏写成 `\tier.rawValue`，于是留痕行打印的是字面量
    /// 「MM_VOLUME_FIXTURE=〈tab〉ier.rawValue 已生效」——照片照常拍到徽标、日志照常有一行
    /// "已生效"，而那一行**没有说出用的是哪一档**，判据当场变成假绿（P6.7 查的就是这一族）。
    /// 所以这一句要能被单测喂进档位名，而不是只能在 stderr 里靠人眼读出来。
    public var appliedNote: String {
        "MM_VOLUME_FIXTURE=\(rawValue) 已生效：这是合成快照，不是这台机器的读数"
    }

    /// 档位对应的快照。nil = 这一档模拟"读不到"；`.off` 不该走到这里。
    /// 数字全部照 P35a 本机实测那一行抄（460.4 GiB / 40.3 GiB / 40.6 GiB），
    /// 夹具卷那条特意选成**与本机不同的一对容量数**，否则会被去重键并掉，正分支就拍不出来。
    public var rows: [VolumeRootRow]? {
        switch self {
        case .off, .fail: return nil
        case .two:
            return [
                VolumeRootRow(path: "/", browsable: true, isDirectory: true,
                              totalBytes: 494_370_000_000, availRegularBytes: 43_244_281_856,
                              availImportantBytes: 43_595_157_504),
                VolumeRootRow(path: "/Volumes/p35b-fixture-data", browsable: true, isDirectory: true,
                              totalBytes: 2_000_000_000_000, availRegularBytes: 900_000_000_000,
                              availImportantBytes: 950_000_000_000),
                // 与真机同一对容量的系统切片：它在画面里不该出现，出现就是去重没跑。
                VolumeRootRow(path: "/System/Volumes/Preboot", browsable: false, isDirectory: true,
                              totalBytes: 494_370_000_000, availRegularBytes: 43_244_281_856,
                              availImportantBytes: 0),
            ]
        case .zero:
            return [
                VolumeRootRow(path: "/System/Volumes/Data", browsable: false, isDirectory: true,
                              totalBytes: 494_370_000_000, availRegularBytes: 43_244_281_856,
                              availImportantBytes: 43_595_157_504),
            ]
        }
    }
}

// MARK: 只读快照

public enum VolumeRootProbe {
    /// 这台机器上现在挂了哪些卷。**只读**：不扫目录树、不 mount/diskutil、不请求权限，
    /// 也不需要 TCC——P35a §1 的两把尺子里只有 Foundation 这一支进生产代码（§10 第 1 条：
    /// 不 spawn `mount`，全量挂载表只用于交叉对读）。
    ///
    /// 取**默认档**（`options: []`）再自己按 `browsable` 筛，而不是直接要 `.skipHiddenVolumes` 的条数：
    /// 后者今天在本机也给 1，但那是"没被标隐藏的挂载点"，不是"我们能扫的卷"——
    /// 语义不同，且两者在有外置卷的机器上可以不等（§9-B）。
    ///
    /// 返回 nil = 一条都没读到（Foundation 给 nil，或给空数组）。调用方据此说"读不到"，
    /// 不许说"0 卷"。
    public static func snapshot(env: [String: String] = ProcessInfo.processInfo.environment) -> [VolumeRootRow]? {
        let tier = MMHookValue.selected(key: "MM_VOLUME_FIXTURE", env: env,
                                        fallback: VolumeFixtureTier.off)
        guard tier != .off else { return liveSnapshot() }
        MMHookValue.emit(tier.appliedNote)
        return tier.rows
    }

    private static func liveSnapshot() -> [VolumeRootRow]? {
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []),
              !urls.isEmpty else { return nil }
        let keys: Set<URLResourceKey> = [
            .volumeIsBrowsableKey, .isDirectoryKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        return urls.map { url in
            // 整条读不出来就当这条没有数：三个容量都留 nil、browsable 按 false 处理，
            // 于是它进不了候选根，也不会挤掉别条。这一条不是猜——它一条都不报。
            let values = try? url.resourceValues(forKeys: keys)
            return VolumeRootRow(
                path: url.path,
                browsable: values?.volumeIsBrowsable ?? false,
                isDirectory: values?.isDirectory ?? false,
                totalBytes: values?.volumeTotalCapacity.map { UInt64(max(0, $0)) },
                availRegularBytes: values?.volumeAvailableCapacity.map { UInt64(max(0, $0)) },
                availImportantBytes: values?.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
            )
        }
    }
}
