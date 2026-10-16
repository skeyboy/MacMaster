//
//  VolumeRootsTests.swift — 跨卷枚举的四条规则（P35b）
//
//  立项依据是 P35a 的实测（`docs/analysis/disk-volume-enumeration.md`）：
//  默认档枚举回来 14 条、其中 13 条是系统切片与只读快照卷；同一块启动盘以**同一对容量数**
//  出现在 5 个挂载点上；"最满优先"若按绝对字节排，本机把用户真正要清的那块盘排到第 9。
//  这三件事界面上都看不出来——名单少一条、多一条、或者顺序换了，画面上仍然是一句通顺的话。
//  所以四条规则全部钉在这里，喂的全是假 `[VolumeRootRow]`。
//
//  钉不住的那一半写在这儿：`VolumeRootProbe` 里读这台机器的那一句 Foundation 调用
//  本文件**一条都不测**——单测读不到挂载表，硬测只会变成"断言今天有几个卷"，
//  明天插一块盘就红。那一支由 P35a 的探针日志与本轮的照片负责（口径同 `RunningAppProbe`）。
//  夹具档（`MM_VOLUME_FIXTURE`）测的是**解析与形状**，不是"这台机器有几个卷"。
//

import XCTest
import Foundation
@testable import MMCore

final class VolumeRootsTests: XCTestCase {

    // MARK: 造数据

    /// 一条挂载点。默认"可浏览、是目录"，各条测试只动自己要审的那一个字段。
    private func row(_ path: String, total: UInt64?, regular: UInt64?, important: UInt64?,
                     browsable: Bool = true, isDirectory: Bool = true) -> VolumeRootRow {
        VolumeRootRow(path: path, browsable: browsable, isDirectory: isDirectory,
                      totalBytes: total, availRegularBytes: regular, availImportantBytes: important)
    }

    /// 本机启动卷那一行的实测数（P35a §7：460.4 GiB / 40.3 GiB / 40.6 GiB，换算到字节）。
    private func bootRow(_ path: String) -> VolumeRootRow {
        row(path, total: 494_370_000_000, regular: 43_244_281_856, important: 43_595_157_504)
    }

    // MARK: ① 候选根筛选

    /// 三把闸门各挡一类实测见过的东西；每条只动一个字段，免得一处坏掉遮住另一处。
    /// `removable` 那一档在这里**没有对应的字段**，不是漏了：P35a §6 量到它会把 4 条
    /// 只读快照卷说成"可移出"，所以这一格根本不进快照，界面上也就无从据此写"外置盘"。
    func testCandidateFilterHasThreeIndependentGates() {
        let rows = [
            row("/System/Volumes/Preboot", total: 494_370_000_000, regular: 43_244_281_856,
                important: 0, browsable: false),                                // browsable 否
            row("/dev", total: 0, regular: 0, important: 0, isDirectory: false), // devfs：不是目录
            row("/System/Volumes/Data/home", total: 0, regular: 0, important: 0), // auto_home：total=0
            row("/Volumes/ReadCapacityFailed", total: nil, regular: nil, important: nil),
            bootRow("/"),
        ]
        XCTAssertEqual(VolumeRoots.candidates(from: rows).map(\.path), ["/"], "候选根名单不止能扫的那一条")
    }

    /// 只读快照卷的 `avail重要` 全是 0：让它进名单，它会在"最满优先"里顶到 100%，
    /// 而那个 0 的意思是"这一口径没数"，不是"一个字节都不剩"（§5 第 1 条）。
    func testReadOnlyDistributionVolumeNeverBecomesAFullVolume() {
        let rows = [
            row("/Library/Developer/CoreSimulator/Volumes/watchOS_23T570",
                total: 8_000_000_000, regular: 8_000_000_000, important: 0, browsable: false),
            bootRow("/"),
        ]
        let candidates = VolumeRoots.candidates(from: rows)
        XCTAssertEqual(candidates.map(\.path), ["/"])
        XCTAssertNotNil(candidates.first?.usedRatio, "启动卷该有占比")
    }

    // MARK: ② 容量对去重

    /// P35a §4 那 5 条压成 1 条：`/`、Preboot、Update、VM、Recovery 报同一份
    /// 460.4 GiB / 40.3 GiB。这一档**故意全标成可浏览**——生产路径上它们先被 browsable
    /// 挡掉了，只按真机形态喂的话，去重键这一格就没有单独受审的机会。
    func testCapacityPairCollapsesFiveMountPointsIntoOne() {
        let samePair = ["", "/System/Volumes/Preboot", "/System/Volumes/Update",
                        "/System/Volumes/VM", "/Volumes/Recovery"]
            .map { bootRow($0.isEmpty ? "/" : $0) }
        let deduped = VolumeRoots.dedupe(samePair)
        XCTAssertEqual(deduped.map(\.path), ["/"], "同一对容量数没压成一条，或代表没选最短路径")
    }

    /// 0.5 GiB 那一族（Hardware / iSCPreboot / xarts）三条并一条。
    func testSmallSliceFamilyAlsoCollapses() {
        let rows = ["/A/xarts", "/B/iSCPreboot", "/C/Hardware"].map {
            row($0, total: 536_870_912, regular: 536_870_912, important: 0)
        }
        XCTAssertEqual(VolumeRoots.dedupe(rows).count, 1)
    }

    /// 不同容量对不许并掉——否则两块真的盘会说成一块。
    func testDifferentCapacityPairsStayApart() {
        let rows = [bootRow("/"),
                    row("/Volumes/Ext", total: 2_000_000_000_000, regular: 900_000_000_000,
                        important: 950_000_000_000)]
        XCTAssertEqual(VolumeRoots.dedupe(rows).count, 2)
    }

    /// 结果与输入顺序无关：乱序喂进去还是同一条代表。取证脚本换枚举顺序时画面不许变。
    func testDedupeDoesNotDependOnInputOrder() {
        let rows = [bootRow("/System/Volumes/VM"), bootRow("/"), bootRow("/System/Volumes/Update")]
        XCTAssertEqual(VolumeRoots.dedupe(rows).map(\.path), ["/"])
        XCTAssertEqual(VolumeRoots.dedupe(rows.reversed()).map(\.path), ["/"])
    }

    /// 读不到的那位在键里是 `—`，不许折成 0：折了就把"没读到"当成"空的"，
    /// 两条读不到的不同卷还会被这一格并成一条。
    func testCapacityKeyKeepsUnreadableAsItsOwnToken() {
        XCTAssertEqual(VolumeRoots.capacityKey(of: row("/x", total: nil, regular: nil, important: nil)),
                       "—|—")
        XCTAssertEqual(VolumeRoots.capacityKey(of: row("/y", total: 10, regular: 0, important: 5)), "10|0")
    }

    // MARK: ③ 排序键：使用率降序，两把口径各钉一条

    /// 重要用途口径（生产默认）：夹具卷 52.5% 排在启动卷 91.2% 后面。
    func testFullestFirstUnderImportantCaliber() {
        let rows = [row("/Volumes/Ext", total: 2_000_000_000_000, regular: 900_000_000_000,
                            important: 950_000_000_000),
                    bootRow("/")]
        XCTAssertEqual(VolumeRoots.candidates(from: rows).map(\.path), ["/", "/Volumes/Ext"],
                       "重要用途口径下不是最满优先")
    }

    /// 同一批数据换普通口径，取的是普通口径那份数。
    /// 这一条钉的是"占比的分母跟排序用同一把尺子"，不是"两把尺子永远同序"——
    /// §7 实测本机 14 条里 `普通>重要` 12 条，同序只是这两条样本上的巧合。
    func testCaliberFlowsIntoTheRatioDenominator() {
        let rows = [row("/Volumes/Ext", total: 2_000_000_000_000, regular: 900_000_000_000,
                            important: 950_000_000_000),
                    bootRow("/")]
        let ordered = VolumeRoots.candidates(from: rows, caliber: .regular)
        XCTAssertEqual(ordered.map(\.availBytes), [43_244_281_856, 900_000_000_000])
    }

    /// 两把尺子真的分胜负的样本：普通口径快满（96%）、重要口径还剩一半（50%）。
    /// 这是"口径必须显式选一个并留在文案里"的否证钉子——不显式选就会看实现心情。
    func testCaliberChoiceCanChangeTheOrder() {
        let nearlyFullOnRegular = row("/Volumes/Ext", total: 100, regular: 4, important: 50)
        XCTAssertEqual(VolumeRoots.candidates(from: [nearlyFullOnRegular, bootRow("/")],
                                             caliber: .important).map(\.path), ["/", "/Volumes/Ext"])
        XCTAssertEqual(VolumeRoots.candidates(from: [nearlyFullOnRegular, bootRow("/")],
                                             caliber: .regular).map(\.path), ["/Volumes/Ext", "/"])
    }

    // MARK: ④ 读不到排最后

    /// 总容量读得到、可用读不到：这块盘**确实能扫**，所以留在名单里，只是没有占比，
    /// 并且排在所有量得出使用率的卷后面。
    func testRootWithoutAvailableCapacityStaysListedButLast() {
        let rows = [row("/Volumes/UnknownAvail", total: 500_000_000_000, regular: nil, important: nil),
                    bootRow("/"),
                    row("/Volumes/Ext", total: 2_000_000_000_000, regular: 900_000_000_000,
                        important: 950_000_000_000)]
        let ordered = VolumeRoots.candidates(from: rows)
        XCTAssertEqual(ordered.map(\.path), ["/", "/Volumes/Ext", "/Volumes/UnknownAvail"])
        XCTAssertNil(ordered.last?.usedRatio, "读不到可用却算出了占比")
    }

    /// 可用大于总量时按 0 已用处理，不报负占比（`SystemSpaceReport.swift:30` 记的是同族问题）。
    func testUsedRatioNeverGoesNegative() {
        XCTAssertEqual(VolumeRoot(path: "/Volumes/Weird", totalBytes: 100, availBytes: 180).usedRatio, 0)
    }

    /// 排序对可用容量完全读不到的一批也要给出确定顺序（全 nil ⟹ 按路径升序，不是按输入顺序）。
    func testAllUnreadableStillSortsDeterministically() {
        let rows = [row("/Volumes/b", total: 10, regular: nil, important: nil),
                    row("/Volumes/a", total: 20, regular: nil, important: nil)]
        XCTAssertEqual(VolumeRoots.candidates(from: rows).map(\.path), ["/Volumes/a", "/Volumes/b"])
        XCTAssertEqual(VolumeRoots.candidates(from: rows.reversed()).map(\.path), ["/Volumes/a", "/Volumes/b"])
    }

    // MARK: ⑤ 新旧口径的否证钉子（B 档）

    /// 旧口径 = "枚举回来几条"（`DashboardModel` 原先那句 `.skipHiddenVolumes` 的条数），
    /// 新口径 = "我们能扫的卷"。本机今天都读成 1，画面上看不出差别，语义却不同。
    /// 这一批假数据照 P35a §3 本机默认档的形态摆（14 条、13 条 browsable 否）：
    /// 条数 14、候选根 1。谁将来把那一格改回 `rows.count`，这一条会先红。
    func testEnumeratedRowCountIsNotTheNumberOfScannableVolumes() {
        var rows: [VolumeRootRow] = [bootRow("/")]
        for name in ["Preboot", "Update", "VM", "Hardware", "iSCPreboot", "xarts"] {
            // 同一对容量数，且 browsable 否
            rows.append(bootRow("/System/Volumes/" + name).mapBrowsableTo(false))
        }
        rows.append(bootRow("/Volumes/Recovery").mapBrowsableTo(false))
        rows.append(row("/System/Volumes/Data", total: 494_370_000_000, regular: 43_244_281_856,
                        important: 0, browsable: false))
        rows.append(row("/Library/Developer/CoreSimulator/Cryptex/Images/bundle/SIMULATOR",
                        total: 4_000_000_000, regular: 4_000_000_000, important: 0, browsable: false))
        rows.append(row("/Library/Developer/CoreSimulator/Volumes/watchOS_23T570",
                        total: 8_000_000_000, regular: 8_000_000_000, important: 0, browsable: false))
        rows.append(row("/System/Volumes/Data/home", total: 0, regular: 0, important: 0, browsable: false))
        rows.append(row("/Users/lee/Library/Developer/CoreDevice/DeviceFS",
                        total: 1_099_511_627_776, regular: 1_099_511_627_776,
                        important: 1_099_511_627_776, browsable: false))
        rows.append(row("/Network", total: nil, regular: nil, important: nil, browsable: false))

        XCTAssertEqual(rows.count, 14, "这批假数据该照本机默认档的条数摆")
        XCTAssertEqual(rows.filter(\.browsable).count, 1)
        XCTAssertEqual(VolumeRoots.candidates(from: rows).count, 1, "候选根这一格该与枚举条数脱钩")
    }

    /// 筛选跑在去重前面：同一对容量数里不可浏览的那条没资格当代表。
    func testFilterRunsBeforeDedupe() {
        let slice = VolumeRootRow(path: "/System/Volumes/Preboot", browsable: false, isDirectory: true,
                                  totalBytes: 494_370_000_000, availRegularBytes: 43_244_281_856,
                                  availImportantBytes: 43_595_157_504)
        XCTAssertEqual(VolumeRoots.candidates(from: [slice, bootRow("/")]).map(\.path), ["/"])
        XCTAssertEqual(VolumeRoots.candidates(from: [slice]).isEmpty, true, "只剩不可浏览的那条就该是空名单")
    }

    // MARK: ⑥ 夹具档位（照片那一支的正分支靠它）

    /// `two` 档的形状：两条候选根，第三条（与启动卷同一对容量数的系统切片）不许冒出来。
    /// 这一条同时是徽标那句的分母钉子：N = count − 1，count 错一位就多报一块盘。
    func testFixtureTierTwoYieldsExactlyTwoCandidateRoots() {
        XCTAssertNotNil(VolumeFixtureTier.two.rows)
        let candidates = VolumeRoots.candidates(from: VolumeFixtureTier.two.rows ?? [])
        XCTAssertEqual(candidates.map(\.path), ["/", "/Volumes/p35b-fixture-data"])
        XCTAssertEqual(candidates.count - 1, 1)
    }

    /// 卸载页与应用监听只要"除启动卷之外的那些挂载点"。这一格的价值全在去重那一步：
    /// 本机本轮实测（`mountedVolumeURLs(options: [])` 14 条）`/Volumes/Recovery` 与 `/`
    /// 报同一对容量数（494384795648 / 24033464320），少了去重就会给同一个 `/Applications`
    /// 开两个 kqueue —— 装卸事件成双出现，那是监听侧的假话。
    func testNonBootPathsDropTheBootVolumeAndItsAliasMounts() {
        let rows = [bootRow("/"), bootRow("/Volumes/Macintosh HD"), bootRow("/Volumes/Recovery"),
                    row("/Volumes/Ext", total: 2_000_000_000_000, regular: 900_000_000_000,
                        important: 950_000_000_000)]
        XCTAssertEqual(VolumeRoots.nonBootVolumePaths(from: rows), ["/Volumes/Ext"])
        XCTAssertEqual(VolumeRoots.nonBootVolumePaths(from: [bootRow("/")]), [],
                       "只有启动卷的机器（本机默认档）不该拼出任何外接卷目录")
        XCTAssertEqual(VolumeRoots.nonBootVolumePaths(from: VolumeFixtureTier.two.rows ?? []),
                       ["/Volumes/p35b-fixture-data"])
    }

    func testFixtureTierZeroAndFailShapes() {
        guard let rows = VolumeFixtureTier.zero.rows else { return XCTFail("zero 档不该返回 nil") }
        XCTAssertEqual(VolumeRoots.candidates(from: rows).count, 0, "zero 档该有挂载点、没有候选根")
        XCTAssertNil(VolumeFixtureTier.fail.rows, "fail 档模拟的是「一行都没读到」")
        XCTAssertNil(VolumeFixtureTier.off.rows, "off 档不该有合成快照")
    }

    /// 钩子解析：合法档位给合成快照，`fail` 给 nil，大小写与空格都认；
    /// 非法值回落 off（= 读这台机器），回落那一档的留痕由照片族的 .log 核对。
    func testProbeResolvesFixtureWithoutReadingTheMachine() {
        XCTAssertEqual(VolumeRootProbe.snapshot(env: ["MM_VOLUME_FIXTURE": "two"])?.count, 3)
        XCTAssertEqual(VolumeRootProbe.snapshot(env: ["MM_VOLUME_FIXTURE": " zero "])?.count, 1)
        XCTAssertNil(VolumeRootProbe.snapshot(env: ["MM_VOLUME_FIXTURE": "fail"]))
        let rejected = MMHookValue.resolve(raw: "tw0", fallback: VolumeFixtureTier.off,
                                          cases: VolumeFixtureTier.allCases)
        XCTAssertEqual(rejected.selected, .off)
        XCTAssertEqual(rejected.accepts, "off|two|zero|fail")
    }

    /// 留痕行必须**点名档位**。这一条是本轮自己撞出来的坑：第一版写的是
    /// `"MM_VOLUME_FIXTURE=\tier.rawValue 已生效…"`（`\(…)` 少了括号），
    /// `\t` 被当成制表符，于是 stderr 上打的是「=〈TAB〉ier.rawValue 已生效」。
    /// 照片照常拍到徽标、日志照常有一行"已生效"——**这一族唯一的机械判据当场变成假绿**，
    /// 而它是 P6.6/P6.7 两轮专门立起来防那个坑的。所以档位名要当数据钉，不当"看得见的字"。
    func testAppliedNoteNamesTheTier() {
        for tier in VolumeFixtureTier.allCases where tier != .off {
            let note = tier.appliedNote
            XCTAssertTrue(note.hasPrefix("MM_VOLUME_FIXTURE=\(tier.rawValue) 已生效"),
                          "\(tier.rawValue) 档的留痕行没点名档位：\(note)")
            XCTAssertFalse(note.contains("rawValue"), "留痕行里漏进了未求值的插值：\(note)")
            XCTAssertTrue(note.contains("合成快照"), "留痕行要自报这不是这台机器的读数：\(note)")
        }
    }
}

private extension VolumeRootRow {
    /// 只翻转 browsable 的写法糖：上面那批假数据里"系统切片"一大族共用同一对容量数，
    /// 逐个写六遍构造函数会把注意力引到无关字段上。
    func mapBrowsableTo(_ value: Bool) -> VolumeRootRow {
        VolumeRootRow(path: path, browsable: value, isDirectory: isDirectory,
                      totalBytes: totalBytes, availRegularBytes: availRegularBytes,
                      availImportantBytes: availImportantBytes)
    }
}
