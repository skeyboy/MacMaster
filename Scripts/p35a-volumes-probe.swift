// P35a 取证探针：本机现在挂着哪些卷、Foundation 的卷枚举会把它们说成什么，以及
// 「最满的那卷优先」这句话在几种可用容量口径下是不是同一个排序。
//
// 用法在 `Scripts/p35a-volumes-probe.sh`（它负责编译与归因头）。全程只读：
// 不扫描任何目录树、不写、不弹面板、不 mount/diskutil，**也不 spawn `mount`**
// （disktree 那一支用 `Command::new("mount")` 解析文本，v1.1 §2 第 4 条明确不学它；
//  挂载表这一格我们走进程内 `getmntinfo`，同一个进程内的系统调用，不是子进程）。
//
// 为什么这一族要先量四件事：
// 1. **同一块盘会不会被数两次**。Catalina 之后 `/` 是只读系统卷、用户能写的都在
//    Data 卷，两者靠 firmlink 拼在一起。`/System/Volumes/Data` 是不是出现在
//    Foundation 的枚举里、出现时它的容量是不是和 `/` 一模一样，决定
//    「最满的卷优先」会不会端出两条同容量的假列表。
// 2. **可用容量有三种口径**。我们磁盘页已经选了「重要用途」那一档
//    （普通口径把 purgeable 算成已用，进度条常年 95% 满），而 disktree 排序用的是
//    `statvfs` 的 `f_bavail`。三种口径下的**排序**是否一致，本轮量，不推。
// 3. **枚举回来的一堆路径里，哪些能当扫描根**。`volumeIsBrowsable`、`volumeIsReadOnly`、
//    `volumeIsRemovable`（外置）、`volumeIsLocal` 各自在本机给什么答复，再和挂载表的
//    `MNT_DONTBROWSE` / `MNT_ROOTFS` / `MNT_LOCAL` / `MNT_RDONLY` 交叉对读——
//    这两把尺子如果给的不是同一个答案，"候选根"就得选一个说了算。
// 4. **Foundation 的枚举方向和前一轮的假设相反**。这个 SDK 里
//    `FileManager.VolumeEnumerationOptions` 只有 `.skipHiddenVolumes`（现读编译核实：
//    `.includeHiddenVolumes` 这个成员**不存在**）。也就是默认档**已经包含隐藏卷**，
//    想要"少"才要传选项。这一条直接决定将来生产代码该传什么。
//
// 判据不在这里落地：将来它落 `Packages/MMDisk`，这一支只做对读与打印。
import Foundation

@main struct VolumesProbe {

    /// Foundation 那一侧的读数（`URL.resourceValues`）。
    struct Row {
        let path: String
        let name: String
        let browsable: Bool?
        let readOnly: Bool?
        let removable: Bool?
        let ejectable: Bool?
        let isLocal: Bool?
        let isDirectory: Bool?
        let total: Int?
        let availPlain: Int?
        let availImportant: Int?
        let availOpportunistic: Int?
        let mount: Mount?
    }

    /// 挂载表那一侧的读数（进程内 `getmntinfo` + `statvfs`，disktree 的同一族来源）。
    struct Mount {
        let mountPoint: String
        let device: String
        let flags: UInt32
        let fsid: String
        let statfsTotal: Int
        let statvfsTotal: Int
        let statvfsAvail: Int
        /// `statvfs` 能取到、但 `f_frsize == 0`（disktree 这时会回落到 `f_bsize`）。
        let statvfsFrsizeZero: Bool
    }

    struct MountRef { let device: String; let fsid: String; let total: Int; let avail: Int }

    static func main() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeLocalizedNameKey, .volumeIsBrowsableKey, .volumeIsReadOnlyKey,
            .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey, .isDirectoryKey,
        ]

        let mounts = mountTable()
        let byMountPoint = Dictionary(grouping: mounts, by: { $0.mountPoint })

        let t0 = DispatchTime.now()
        let visible = fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? []
        let skippingHidden = fm.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                  options: [.skipHiddenVolumes]) ?? []
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000

        print(String(format: "两趟枚举耗时=%.0f ms（挂载表另算，见下）", ms))
        print("挂载表条数（getmntinfo，全部挂载点）=\(mounts.count)  "
              + "默认档（options=[]）=\(visible.count)  "
              + "传 .skipHiddenVolumes 档=\(skippingHidden.count)")
        print("说明：这个 SDK 里没有 `.includeHiddenVolumes` 这个成员，默认档就已经含隐藏卷；"
              + "上面两档的差集是「被标记为隐藏、默认仍能枚举到」的那些。")
        print("disktree 的 `f_frsize==0` 回落（`space.rs:61-67`）在本机挂载表里的触发条数="
              + "\(mounts.filter { $0.statvfsFrsizeZero }.count) / \(mounts.count)"
              + "（触发=0 说明这台机器上 statvfs 的 `f_frsize` 一直有数，回落那条支路量不到）")

        let hiddenOnly = visible.filter { u in !skippingHidden.contains(where: { $0.path == u.path }) }
        print("")
        print("---- 默认档比 .skipHiddenVolumes 档多出来的每一条（这些是界面上不该出现、但枚举会给的）----")
        if hiddenOnly.isEmpty { print("（无）") }
        for url in hiddenOnly.sorted(by: { $0.path < $1.path }) {
            let r = row(for: url, keys, byMountPoint)
            print("  \(r.path)  browsable=\(b(r.browsable))  local=\(b(r.isLocal))  "
                  + "total=\(gib(r.total))  device=\(r.mount?.device ?? "—")  "
                  + "flags=\(flagText(r.mount?.flags))")
        }

        let rows = visible.map { row(for: $0, keys, byMountPoint) }
        print("")
        print("---- 默认档每一条的完整读数（Foundation 一侧 + 挂载表一侧并排）----")
        for r in rows.sorted(by: { $0.path < $1.path }) {
            print(r.path)
            print("    name=\(r.name)  isDirectory=\(b(r.isDirectory))  browsable=\(b(r.browsable))  "
                  + "readOnly=\(b(r.readOnly))  local=\(b(r.isLocal))  removable=\(b(r.removable))  ejectable=\(b(r.ejectable))")
            print("    total=\(gib(r.total))  avail普通=\(gib(r.availPlain))  avail重要=\(gib(r.availImportant))  avail机会=\(gib(r.availOpportunistic))")
            print("    used%普通=\(usedPct(r.total, r.availPlain))  used%重要=\(usedPct(r.total, r.availImportant))  used%机会=\(usedPct(r.total, r.availOpportunistic))")
            if let m = r.mount {
                print("    挂载表：device=\(m.device)  fsid=\(m.fsid)  flags=\(flagText(m.flags))")
                print("    容量对账：Foundation total \(m.totalVsFoundation(r.total))  "
                      + "statfs blocks×bsize=\(gib(m.statfsTotal))  statvfs blocks×frsize=\(gib(m.statvfsTotal))")
                print("    可用对账：statvfs f_bavail（disktree 口径）=\(gib(m.statvfsAvail))  used%statvfs=\(usedPct(m.statvfsTotal, m.statvfsAvail))")
            } else {
                print("    ⚠ 挂载表里找不到同路径条目（Foundation 给了路径，`getmntinfo` 没这一条挂载点）")
            }
        }

        printSameDevice(rows, mounts)
        printOrdering(rows, mounts)
        printRootCandidates(rows, mounts)
        printBootVolumeRow(rows, keys, byMountPoint)
    }

    // MARK: - 挂载表

    static func mountTable() -> [Mount] {
        var ptr: UnsafeMutablePointer<statfs>?
        let n = getmntinfo(&ptr, MNT_NOWAIT)
        guard n > 0, let base = ptr else { return [] }
        var out: [Mount] = []
        for i in 0..<Int(n) {
            let e = base[i]
            let mp = cString(e.f_mntonname)
            let dev = cString(e.f_mntfromname)
            let bsize = Int(e.f_bsize)
            let statfsTotal = Int(e.f_blocks) &* bsize
            var sv = statvfs()
            let ok = statvfs(mp, &sv) == 0
            let frsizeZero = ok && sv.f_frsize == 0
            let frsize = ok ? (frsizeZero ? Int(sv.f_bsize) : Int(sv.f_frsize)) : bsize
            let statvfsTotal = ok ? Int(sv.f_blocks) &* frsize : statfsTotal
            let rawAvail = ok ? Int(sv.f_bavail) &* frsize : 0
            out.append(Mount(mountPoint: mp, device: dev,
                             flags: UInt32(e.f_flags),
                             fsid: "\(e.f_fsid.val.0)/\(e.f_fsid.val.1)",
                             statfsTotal: statfsTotal,
                             statvfsTotal: statvfsTotal,
                             statvfsAvail: rawAvail,
                             statvfsFrsizeZero: frsizeZero))
        }
        return out
    }

    // MARK: - 同一块盘数两次

    /// 同一 `fsid`（或同一设备名）出现在多条路径上 = 那一块盘被数了两次。
    /// 这是「最满的那卷优先」最可能出的假账，所以单独一节，不混在表里。
    static func printSameDevice(_ rows: [Row], _ mounts: [Mount]) {
        print("")
        print("---- 按 fsid 归组：挂载表全量（不看 Foundation，先看系统本来给了几条）----")
        group(mounts.map { MountRef(device: $0.device, fsid: $0.fsid, total: $0.statvfsTotal, avail: $0.statvfsAvail) },
              key: { $0.fsid })
        print("")
        print("---- 按设备名归组：挂载表全量 ----")
        group(mounts.map { MountRef(device: $0.device, fsid: $0.fsid, total: $0.statvfsTotal, avail: $0.statvfsAvail) },
              key: { $0.device })
        print("")
        print("---- Foundation 默认档里被数了几次（这才是界面会拿到的条数）----")
        let dataPath = "/System/Volumes/Data"
        print("\(dataPath) 在挂载表=\(mounts.contains { $0.mountPoint == dataPath })  "
              + "在 Foundation 默认档=\(rows.contains { $0.path == dataPath })")
        let dupInFoundation = Dictionary(grouping: rows, by: { $0.mount?.fsid ?? "（无挂载表条目）" })
            .filter { $0.value.count > 1 }
        if dupInFoundation.isEmpty {
            print("Foundation 默认档里没有一个 fsid 对应两条以上路径（同一块盘只被数一次）")
        } else {
            for (fsid, list) in dupInFoundation.sorted(by: { $0.key < $1.key }) {
                print("⚠ fsid=\(fsid) 在默认档里有 \(list.count) 条：" + list.map { $0.path }.sorted().joined(separator: " "))
            }
        }
        // fsid 不重复 ≠ 容量不重复：APFS 同一容器里几个挂载点报的是同一份总容量与同一份空闲。
        // 所以去重的键不能是 fsid，也不能是设备名——得看容量这一对数。
        print("")
        print("按（total, avail普通）这一对数归组，默认档里有几条共享同一对数：")
        var byPair: [String: [String]] = [:]
        var decoded: [String: (total: Int, avail: Int)] = [:]
        for r in rows where (r.total ?? 0) > 0 {
            let total = r.total ?? 0, avail = r.availPlain ?? 0
            let key = "\(total)|\(avail)"
            byPair[key, default: []].append(r.path)
            decoded[key] = (total, avail)
        }
        let bootKey: String? = rows.first(where: { $0.path == "/" && ($0.total ?? 0) > 0 }).map { "\($0.total ?? 0)|\($0.availPlain ?? 0)" }
        for (key, list) in byPair.sorted(by: { $0.value.count > $1.value.count }) where list.count > 1 {
            let d = decoded[key]!
            let mark = (bootKey == key) ? "⚠（就是启动卷那一对）" : "·"
            print("  \(mark) total=\(gib(d.total)) avail普通=\(gib(d.avail)) 条数=\(list.count)")
            for p in list.sorted() { print("        \(p)") }
        }
        let distinctPairs = Set(byPair.keys).count
        print("默认档里有容量的条数=\(byPair.values.reduce(0) { $0 + $1.count })，不同的容量对=\(distinctPairs)")
    }

    static func group(_ refs: [MountRef], key: (MountRef) -> String) {
        var byKey: [String: [MountRef]] = [:]
        for r in refs { byKey[key(r), default: []].append(r) }
        for (k, list) in byKey.sorted(by: { $0.key < $1.key }) {
            let totals = Set(list.map { $0.total })
            let avails = Set(list.map { $0.avail })
            let tag = list.count > 1 ? "⚠ 同一键的多条路径" : "单条"
            print("\(tag)  \(k)  路径数=\(list.count)  容量集合数=\(totals.count)  可用集合数=\(avails.count)")
            for r in list.sorted(by: { $0.device < $1.device }) {
                print("      \(r.device)  total=\(gib(r.total))  avail=\(gib(r.avail))")
            }
        }
    }

    // MARK: - 排序对读

    /// 三种可用容量口径给出的「最满优先」是不是同一个顺序。
    static func printOrdering(_ rows: [Row], _ mounts: [Mount]) {
        print("")
        print("---- 「最满的那卷优先」：三种口径各排一次（只排 Foundation 默认档会给界面的那些）----")
        let byPlain = rank(rows) { usedRatio($0.total, $0.availPlain) }
        let byImportant = rank(rows) { usedRatio($0.total, $0.availImportant) }
        let byOpportunistic = rank(rows) { usedRatio($0.total, $0.availOpportunistic) }
        print("按 used%普通 排：" + byPlain.map { "\($0.path)(\(usedPct($0.total, $0.availPlain)))" }.joined(separator: " → "))
        print("按 used%重要 排：" + byImportant.map { "\($0.path)(\(usedPct($0.total, $0.availImportant)))" }.joined(separator: " → "))
        print("按 used%机会 排：" + byOpportunistic.map { "\($0.path)(\(usedPct($0.total, $0.availOpportunistic)))" }.joined(separator: " → "))
        let plainOrder = byPlain.map { $0.path }
        let importantOrder = byImportant.map { $0.path }
        let oppOrder = byOpportunistic.map { $0.path }
        print("普通 vs 重要 排序相同=\(plainOrder == importantOrder)")
        print("重要 vs 机会 排序相同=\(importantOrder == oppOrder)")
        print("第一条是否同一路径：普通=\(byPlain.first?.path ?? "—")  重要=\(byImportant.first?.path ?? "—")  机会=\(byOpportunistic.first?.path ?? "—")")
        if plainOrder != importantOrder {
            print("⚠ 排序不同——界面用哪一口径做「最满优先」必须显式选一个，另一个会在同一台机器上给出不同的第一条。")
        }

        // 这一格是给 `SystemSpaceReport.swift:30` 那条「普通可用会大于重要用途可用」的注释补分布数字。
        var plainBigger = 0, importantBigger = 0, equalCount = 0, zeroImportant = 0
        for r in rows {
            if let i = r.availImportant, i == 0 { zeroImportant += 1 }
            guard let p = r.availPlain, let i = r.availImportant else { continue }
            if p > i { plainBigger += 1 } else if p < i { importantBigger += 1 } else { equalCount += 1 }
        }
        print("avail普通 vs avail重要（默认档 \(rows.count) 条）："
              + "普通>重要=\(plainBigger)  普通<重要=\(importantBigger)  相等=\(equalCount)  "
              + "avail重要读到 0 的条数=\(zeroImportant)")

        print("")
        print("---- 假如改成「挂载表全量」来排（disktree 的枚举面）：前六条 ----")
        let mountRows = mounts.map { MountRef(device: $0.device, fsid: $0.fsid, total: $0.statvfsTotal, avail: $0.statvfsAvail) }
        let rankedMounts = mountRows.sorted { a, b2 in
            let ka = usedRatio(a.total, a.avail), kb = usedRatio(b2.total, b2.avail)
            switch (ka, kb) {
            case (nil, nil): return a.device < b2.device
            case (nil, _): return false
            case (_, nil): return true
            case (let x?, let y?): return x != y ? x > y : a.device < b2.device
            }
        }
        for m in rankedMounts.prefix(6) {
            print("  used%=\(usedPct(m.total, m.avail))  \(m.device)  total=\(gib(m.total))  avail=\(gib(m.avail))")
        }
        let sameTwice = rankedMounts.prefix(2).map { $0.device }
        if sameTwice.count == 2 && sameTwice[0] == sameTwice[1] {
            print("⚠ 全量挂载表排出来前两条是同一个设备名——这一族就是「同一块盘占掉两个名额」。")
        }

        let noTotal = rows.filter { ($0.total ?? 0) <= 0 }
        print("total 读不到或为 0 的条数=\(noTotal.count)" + (noTotal.isEmpty ? "" : "：" + noTotal.map { $0.path }.joined(separator: " ")))

        print("")
        print("---- 照抄 disktree 那一把排序键（可用字节**升序**，读不到排最后）在本机给什么 ----")
        // 它的键是 available 的绝对字节数升序，不是使用率。默认档这 14 条里，
        // 0.5 GiB 的系统切片可用只有 0.5 GiB，会排在 40 GiB 可用的启动卷**前面**。
        let byAvail = rank(rows) { r in r.availPlain.map { Double(-$0) } }
        print("按 avail普通 升序（disktree 的键）："
              + byAvail.prefix(8).map { "\($0.path)(\(gib($0.availPlain)))" }.joined(separator: " → ")
              + (byAvail.count > 8 ? " ……共 \(byAvail.count) 条" : ""))
        if let idx = byAvail.firstIndex(where: { $0.path == "/" }) {
            print("启动卷 / 在这一把尺子下排第 \(idx + 1)（默认档共 \(byAvail.count) 条，前面 \(idx) 条的可用字节都比它小）")
            print("解读：它把「可用字节少」当成「最满」。本机排在 / 之前的全是可用零点几 GiB 的系统卷，"
                  + "而 / 的可用有几十 GiB——照抄这一把键会把用户真正要清理的那块盘排到名单后头。"
                  + "排序键得按使用率，不能按绝对字节。")
        }
    }

    static func rank(_ rows: [Row], _ key: (Row) -> Double?) -> [Row] {
        rows.sorted { a, b2 in
            let ka = key(a), kb = key(b2)
            switch (ka, kb) {
            case (nil, nil): return a.path < b2.path
            case (nil, _): return false      // 读不到的排最后，别让"读不到"变成"最满"
            case (_, nil): return true
            case (let x?, let y?): return x != y ? x > y : a.path < b2.path
            }
        }
    }

    // MARK: - 候选根

    /// 哪些条目真的能被端成扫描根：可浏览 + 是目录 + 容量读得到。
    static func printRootCandidates(_ rows: [Row], _ mounts: [Mount]) {
        print("")
        print("---- 候选根（默认档里 browsable=true 且 isDirectory=true 的那些）----")
        let candidates = rows.filter { $0.browsable == true && $0.isDirectory == true }
        print("默认档条数=\(rows.count)  候选根=\(candidates.count)  被 browsable/isDirectory 挡掉的=\(rows.count - candidates.count)")
        for r in candidates.sorted(by: { $0.path < $1.path }) {
            print("  ✓ \(r.path)  total=\(gib(r.total))  used%重要=\(usedPct(r.total, r.availImportant))  "
                  + "readOnly=\(b(r.readOnly))  local=\(b(r.isLocal))  removable=\(b(r.removable))  "
                  + "flags=\(flagText(r.mount?.flags))")
        }
        print("")
        print("---- 被挡掉的每一条，以及是被哪把尺子挡掉的 ----")
        for r in rows.sorted(by: { $0.path < $1.path }) where !(r.browsable == true && r.isDirectory == true) {
            var why: [String] = []
            if r.browsable != true { why.append("Foundation browsable=\(b(r.browsable))") }
            if r.isDirectory != true { why.append("Foundation isDirectory=\(b(r.isDirectory))") }
            if let f = r.mount?.flags, hasFlag(f, MNT_DONTBROWSE) { why.append("挂载表 MNT_DONTBROWSE") }
            print("  ✗ \(r.path)  " + why.joined(separator: "  ") + "  flags=\(flagText(r.mount?.flags))")
        }
        print("")
        print("---- 两把尺子有没有互相打脸：Foundation browsable vs 挂载表 MNT_DONTBROWSE ----")
        var agreeB = 0, agreeN = 0, onlyFoundation = 0, onlyFlags = 0, noMountEntry = 0
        for r in rows {
            guard let f = r.mount?.flags else { noMountEntry += 1; continue }
            let foundationBrowsable = (r.browsable == true)
            let flagsBrowsable = !hasFlag(f, MNT_DONTBROWSE)
            if foundationBrowsable && flagsBrowsable { agreeB += 1 }
            else if !foundationBrowsable && !flagsBrowsable { agreeN += 1 }
            else if !foundationBrowsable { onlyFoundation += 1; print("⚠ 只有 Foundation 判不可浏览：\(r.path)  flags=\(flagText(f))") }
            else { onlyFlags += 1; print("⚠ 只有挂载表带 MNT_DONTBROWSE、Foundation 却说可浏览：\(r.path)") }
        }
        print("默认档=\(rows.count)  两边都说可浏览=\(agreeB)  两边都说不可浏览=\(agreeN)  "
              + "只有 Foundation 报不可浏览=\(onlyFoundation)  只有挂载表报=\(onlyFlags)  挂载表无同路径条目=\(noMountEntry)")

        print("")
        print("---- disktree 会跳过的那几条在本机是什么样子（它的 never_scanned：Data 卷与 /Network 一族）----")
        for path in ["/System/Volumes/Data", "/Network"] {
            let m = mounts.first { $0.mountPoint == path }
            let exact = rows.contains { $0.path == path }
            let prefixed = rows.filter { $0.path != path && $0.path.hasPrefix(path + "/") }.map { $0.path }
            print("  \(path)：挂载表=\(m == nil ? "无" : "有（device=\(m!.device)  flags=\(flagText(m!.flags)))")  "
                  + "默认档里有这一条本身=\(exact)  有它下面的子挂载=\(prefixed.count) 条"
                  + (prefixed.isEmpty ? "" : "（" + prefixed.joined(separator: " ") + "）"))
        }

        print("")
        print("---- 挂载表里有、但 Foundation 默认档没给的那几条（枚举本身就把它们挡在外面）----")
        let enumerated = Set(rows.map { $0.path })
        let mountOnly = mounts.filter { !enumerated.contains($0.mountPoint) }
        print("挂载表=\(mounts.count)  默认档=\(rows.count)  只在挂载表里的=\(mountOnly.count)")
        for m in mountOnly.sorted(by: { $0.mountPoint < $1.mountPoint }) {
            print("  \(m.mountPoint)  device=\(m.device)  flags=\(flagText(m.flags))  total=\(gib(m.statvfsTotal))  avail=\(gib(m.statvfsAvail))")
        }

        print("")
        print("---- 同一份空闲空间被几个挂载点共享（按设备名里的 diskN 段归组，APFS 容器口径）----")
        var byContainer: [String: [Mount]] = [:]
        for m in mounts {
            byContainer[containerKey(m.device), default: []].append(m)
        }
        for (key, list) in byContainer.sorted(by: { $0.key < $1.key }) where list.count > 1 {
            let totals = Set(list.map { $0.statvfsTotal })
            let avails = Set(list.map { $0.statvfsAvail })
            let shared = totals.count == 1 && avails.count == 1
            print("\(shared ? "⚠" : "·") 容器 \(key)：挂载点数=\(list.count)  "
                  + "容量集合数=\(totals.count)  可用集合数=\(avails.count)  "
                  + "总容量=\(gib(list.first?.statvfsTotal))  可用=\(gib(list.first?.statvfsAvail))")
            for m in list.sorted(by: { $0.mountPoint < $1.mountPoint }) {
                print("      \(m.mountPoint)  device=\(m.device)  在默认档枚举里=\(enumerated.contains(m.mountPoint) ? "有这条" : "没给这条")")
            }
        }
        print("解读：同一容器里那几个挂载点报的是同一份空闲空间。把它们各算一卷，就是"
              + "把同一块盘的剩余量数了好几遍——「最满优先」的名单长度和「共 N 卷」都是假账。")

        print("")
        print("---- 「只读」这一格两把尺子打不打脸：Foundation volumeIsReadOnly vs 挂载表 MNT_RDONLY ----")
        var agreeRO = 0, clashRO = 0
        for r in rows.sorted(by: { $0.path < $1.path }) {
            guard let f = r.mount?.flags else { continue }
            let flagsRO = hasFlag(f, MNT_RDONLY)
            if r.readOnly == flagsRO { agreeRO += 1; continue }
            clashRO += 1
            print("⚠ \(r.path)：Foundation readOnly=\(b(r.readOnly))  挂载表 MNT_RDONLY=\(flagsRO ? "是" : "否")  flags=\(flagText(f))")
        }
        print("默认档=\(rows.count)  两把尺子说同一件事=\(agreeRO)  打脸=\(clashRO)")
    }

    /// 设备名里 `diskN` 那一段当容器键（`/dev/disk3s5s1` 与 `/dev/disk3s1` 同容器）。
    /// 非磁盘设备（`devfs`、`map auto_home`、`devices -- file:///…`）各归各的键，不冒充容器。
    static func containerKey(_ device: String) -> String {
        let last = device.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? device
        guard last.hasPrefix("disk") else { return device }
        var digits = ""
        for ch in last.dropFirst(4) {
            if ch.isNumber { digits.append(ch) } else { break }
        }
        return digits.isEmpty ? device : "disk" + digits
    }

    /// 启动卷那一行单独打：这是"最满优先"默认应该给的那一条，界面上要能自证。
    static func printBootVolumeRow(_ rows: [Row], _ keys: [URLResourceKey], _ byMountPoint: [String: [Mount]]) {
        print("")
        print("---- 启动卷 / 的单独读数（枚举给不给它、和直接对 / 取值是不是一回事）----")
        let boot = row(for: URL(fileURLWithPath: "/"), keys, byMountPoint)
        print("/ ：browsable=\(b(boot.browsable))  isDirectory=\(b(boot.isDirectory))  total=\(gib(boot.total))  "
              + "used%普通=\(usedPct(boot.total, boot.availPlain))  used%重要=\(usedPct(boot.total, boot.availImportant))  "
              + "device=\(boot.mount?.device ?? "—")  flags=\(flagText(boot.mount?.flags))")
        let enumeratedRoot = rows.first { $0.path == "/" }
        print("枚举结果里有没有恰好等于「/」的那一条=\(enumeratedRoot != nil)")
        if let e = enumeratedRoot {
            print("直接对 / 取值 vs 枚举那条：total \(e.total == boot.total ? "同数" : "⚠ 不同数（枚举=\(gib(e.total)) 直接=\(gib(boot.total))）")  "
                  + "avail重要 \(e.availImportant == boot.availImportant ? "同数" : "⚠ 不同数（枚举=\(gib(e.availImportant)) 直接=\(gib(boot.availImportant))）")  "
                  + "browsable \(b(e.browsable)) vs \(b(boot.browsable))")
        }
    }

    // MARK: - 取值与格式化

    static func row(for url: URL, _ keys: [URLResourceKey], _ byMountPoint: [String: [Mount]]) -> Row {
        let vals = try? url.resourceValues(forKeys: Set(keys))
        return Row(
            path: url.path,
            name: url.lastPathComponent,
            browsable: vals?.volumeIsBrowsable,
            readOnly: vals?.volumeIsReadOnly,
            removable: vals?.volumeIsRemovable,
            ejectable: vals?.volumeIsEjectable,
            isLocal: vals?.volumeIsLocal,
            isDirectory: vals?.isDirectory,
            total: vals?.volumeTotalCapacity,
            availPlain: vals?.volumeAvailableCapacity.map { Int($0) },
            availImportant: vals?.volumeAvailableCapacityForImportantUsage.map { Int($0) },
            availOpportunistic: vals?.volumeAvailableCapacityForOpportunisticUsage.map { Int($0) },
            mount: byMountPoint[url.path]?.first
        )
    }

    static func cString<T>(_ tuple: T) -> String {
        var copy = tuple
        return withUnsafePointer(to: &copy) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
        }
    }

    static func hasFlag(_ flags: UInt32, _ bit: Int32) -> Bool {
        flags & UInt32(truncatingIfNeeded: bit) != 0
    }

    static func flagText(_ flags: UInt32?) -> String {
        guard let flags else { return "—" }
        let table: [(Int32, String)] = [
            (MNT_RDONLY, "RDONLY"), (MNT_SYNCHRONOUS, "SYNCHRONOUS"), (MNT_NOEXEC, "NOEXEC"),
            (MNT_NOSUID, "NOSUID"), (MNT_NODEV, "NODEV"), (MNT_UNION, "UNION"),
            (MNT_REMOVABLE, "REMOVABLE"), (MNT_DONTBROWSE, "DONTBROWSE"),
            (MNT_IGNORE_OWNERSHIP, "IGNORE_OWNERSHIP"), (MNT_LOCAL, "LOCAL"),
            (MNT_QUOTA, "QUOTA"), (MNT_ROOTFS, "ROOTFS"), (MNT_JOURNALED, "JOURNALED"),
            (MNT_MULTILABEL, "MULTILABEL"), (MNT_SNAPSHOT, "SNAPSHOT"), (MNT_ASYNC, "ASYNC"),
        ]
        let names = table.filter { hasFlag(flags, $0.0) }.map { $0.1 }
        return "0x" + String(flags, radix: 16) + (names.isEmpty ? "" : " " + names.joined(separator: "|"))
    }

    static func usedRatio(_ total: Int?, _ avail: Int?) -> Double? {
        guard let total, total > 0, let avail else { return nil }
        return Double(total - min(total, max(0, avail))) / Double(total)
    }

    static func usedPct(_ total: Int?, _ avail: Int?) -> String {
        guard let r = usedRatio(total, avail) else { return "—" }
        return String(format: "%.1f%%", r * 100)
    }

    static func gib(_ bytes: Int?) -> String {
        guard let bytes else { return "—" }
        // %d 会把超过 Int32 的字节数打成负数（本机 3.1 GiB 那卷实测打成 -998244352），
        // 所以字节数走整数插值，只有 GiB 那一档用格式串。
        return String(format: "%.1f GiB", Double(bytes) / 1_073_741_824) + " (\(bytes) B)"
    }

    static func b(_ v: Bool?) -> String { v.map { $0 ? "是" : "否" } ?? "—" }
}

extension VolumesProbe.Mount {
    /// Foundation 的 total 和挂载表算出来的 total 是不是同一个数——
    /// 不是的话，"容量"这一格和"排序"那一格说的不是同一块盘的大小。
    func totalVsFoundation(_ foundationTotal: Int?) -> String {
        let gib = VolumesProbe.gib
        guard let f = foundationTotal else { return "读不到（挂载表 statfs=\(gib(statfsTotal))）" }
        if f == statfsTotal { return "与 statfs 同数" }
        if f == statvfsTotal { return "与 statvfs 同数（statfs=\(gib(statfsTotal))）" }
        return "⚠ 两边都不等（Foundation=\(gib(f))  statfs=\(gib(statfsTotal))  statvfs=\(gib(statvfsTotal)))"
    }
}
