import XCTest
@testable import MMCore
import MMUI
import MMFileScanner
@testable import MMOptimizer

/// 全部只读或写临时目录：绝不碰真实用户文件。
final class DashboardMetricsTests: XCTestCase {

    // MARK: 真实采样取值范围

    func testMemorySampleRanges() {
        let reading = DashboardMemory.sample()
        XCTAssertGreaterThan(reading.total, 0)
        // 在本机（能读 vm_statistics64）used 必须非 nil；真拿不到就是 nil，UI 走 "—"。
        XCTAssertNotNil(reading.used)
        if let used = reading.used {
            // active + wired + compressed 都在物理内存页里，不可能超过总量。
            XCTAssertLessThanOrEqual(used, reading.total)
        }
        if let compressed = reading.compressed, let used = reading.used {
            // compressed 是 used 的组成部分。
            XCTAssertLessThanOrEqual(compressed, used)
        }
        if let swapUsed = reading.swapUsed, let swapTotal = reading.swapTotal {
            XCTAssertLessThanOrEqual(swapUsed, swapTotal)
        }
        if let pressure = reading.pressure {
            XCTAssertTrue((0...1).contains(pressure))
        }
    }

    func testCPULoadSampleRangeOnRealMachine() {
        let first = SystemSampler.cpuTicks()
        XCTAssertNotNil(first)
        // "0.25 s 的跨度里 tick 一定前进"**不是这个 API 给的前提**：P28 在这台机器上现读到过
        // 整包跑到这一条时差分为 0 的一刻（单跑三次全绿、整包两次红一次，而直接探 `host_cpu_load_info`
        // 的 12 帧全都在走；见 release-readiness §7.19）。把它当前提，判据就变成一枚会随机亮红的灯，
        // 而发版门禁要的正是"红了就一定有事的"。所以这里改成：**跨度是要测的事**——
        // 最多取 6 帧、每帧间隔 0.25 s，凡是算得出数的帧都必须在 0~1 之间，一帧都没算出来才判失败。
        var previous = first
        var loads: [Double] = []
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 0.25)
            guard let current = SystemSampler.cpuTicks() else { continue }
            if let load = SystemSampler.load(from: previous, to: current) { loads.append(load) }
            previous = current
        }
        XCTAssertFalse(loads.isEmpty, "6 帧 × 0.25 s 里 host_cpu_load_info 的累计 tick 一次都没前进")
        for load in loads {
            XCTAssertTrue((0...1).contains(load))
        }
    }

    func testCPULoadSyntheticDelta() {
        let a = SystemSampler.CPUTicks(user: 100, system: 100, idle: 800, nice: 0)
        let b = SystemSampler.CPUTicks(user: 150, system: 150, idle: 800, nice: 0)
        // idle 没有增长 → 100%。
        XCTAssertEqual(SystemSampler.load(from: a, to: b), 1.0)
        // 零跨度返回 nil（让 UI 沿用上次数），而不是假 0%。
        XCTAssertNil(SystemSampler.load(from: a, to: a))
        XCTAssertNil(SystemSampler.load(from: nil, to: b))
        // 半 idle → 50%。
        let c = SystemSampler.CPUTicks(user: 100, system: 100, idle: 850, nice: 0)
        XCTAssertEqual(SystemSampler.load(from: a, to: c) ?? -1, 0.0, accuracy: 0.0001)
    }

    func testVolumeRanges() {
        let volume = SystemSampler.volume()
        XCTAssertNotNil(volume, "本机启动卷容量必须可读")
        if let volume {
            XCTAssertGreaterThan(volume.total, 0)
            XCTAssertLessThanOrEqual(volume.available, volume.total)
            XCTAssertTrue((0...1).contains(volume.usedRatio))
        }
    }

    // MARK: "—" 分支（纯函数）

    func testPlaceholdersWhenDataMissing() {
        XCTAssertEqual(DashboardText.percent(nil), DashboardText.placeholder)
        XCTAssertEqual(DashboardText.memoryUsedText(nil), DashboardText.placeholder)

        // 量到 total 但 vm_statistics64 失败：所有派生显示都是 "—"，不许是 "0"。
        let partial = DashboardMemory.Reading(
            total: 17_179_869_184, used: nil, compressed: nil, swapUsed: nil, swapTotal: nil)
        XCTAssertEqual(DashboardText.memoryUsedText(partial), DashboardText.placeholder)
        XCTAssertEqual(DashboardText.memoryPressureText(partial), DashboardText.placeholder)
        XCTAssertNil(partial.pressure)
        XCTAssertEqual(DashboardText.compressedText(partial), DashboardText.placeholder)
        XCTAssertTrue(DashboardText.swapText(partial).contains(DashboardText.placeholder))
    }

    func testSwapTextOnlyClaimsUnusedWhenMeasured() {
        let zeroSwap = DashboardMemory.Reading(total: 1, used: 1, compressed: 0, swapUsed: 0, swapTotal: 8_589_934_592)
        XCTAssertEqual(DashboardText.swapText(zeroSwap), "交换空间 0 字节")
        let someSwap = DashboardMemory.Reading(total: 1, used: 1, compressed: 0, swapUsed: 1_048_576, swapTotal: 8_589_934_592)
        let text = DashboardText.swapText(someSwap)
        XCTAssertTrue(text.contains("交换"))
        XCTAssertFalse(text.contains(DashboardText.placeholder), "量到非零 swap 时不能显示 —")
    }

    func testReclaimableTextStates() {
        XCTAssertTrue(DashboardText.reclaimableText(.notMeasured).contains("未扫描"))
        XCTAssertEqual(DashboardText.reclaimableText(.measuring), "扫描中…")
        XCTAssertTrue(DashboardText.reclaimableText(.failed(reason: "扫描没有返回结果")).contains("失败"))
        let measured = ReclaimMeasureState.measured(totalBytes: 3_000_000_000, categoryCount: 4)
        let totalValue: UInt64 = 3_000_000_000
        XCTAssertEqual(DashboardText.reclaimableText(measured), MMFormat.bytes(totalValue))
        XCTAssertTrue(measured.isMeasuredValue)
        XCTAssertFalse(ReclaimMeasureState.notMeasured.isMeasuredValue)
        // 四个类别全关着：既不能说"未扫描"（等下去也不会有数），也不能说"测量失败"。
        let noScope = DashboardText.reclaimableText(.noCategorySelected)
        XCTAssertTrue(noScope.contains("未勾选"))
        XCTAssertTrue(DashboardText.reclaimDetailText(.noCategorySelected).contains("清理页"))
        XCTAssertFalse(ReclaimMeasureState.noCategorySelected.isMeasuredValue)
    }

    func testCPUCaliberIsStated() {
        let note = DashboardText.cpuCaliberNote(coreCount: 10)
        XCTAssertTrue(note.contains("总占用"))
        XCTAssertTrue(note.contains("10"))
    }

    // MARK: 可清理 = 注入扫描结果的真实求和

    private func makeCategory(_ name: String, size: UInt64, risk: MMRisk = .safe) -> CacheCategory {
        var category = CacheCategory(id: name, name: name, subtitle: "",
                                     iconName: "doc", risk: risk, scope: .appCache, paths: [])
        category.scannedSize = size
        return category
    }

    func testReclaimTotalIsExactlyCategorySum() {
        let categories = [makeCategory("系统缓存", size: 1_240_000_000),
                          makeCategory("日志", size: 386_000_000),
                          makeCategory("临时文件", size: 123_456)]
        let expected: UInt64 = 1_240_000_000 + 386_000_000 + 123_456
        XCTAssertEqual(DashboardReclaim.totalBytes(of: categories), expected)

        guard case .measured(let total, let count) = DashboardReclaim.state(from: categories) else {
            return XCTFail("注入扫描结果应得到 measured 状态")
        }
        XCTAssertEqual(total, expected)
        XCTAssertEqual(count, categories.count)
    }

    func testReclaimFailurePathsNeverClaimNumber() {
        XCTAssertFalse(DashboardReclaim.state(from: nil).isMeasuredValue)
        XCTAssertFalse(DashboardReclaim.state(from: []).isMeasuredValue)
    }

    /// 概览页那个数字标的是"可清理"，只读类别用户点了也不会变小，算进去就是虚报。
    func testReadOnlyCategoriesAreExcludedFromReclaimTotal() {
        let categories = [makeCategory("系统级缓存", size: 5_000_000_000, risk: .readOnly),
                          makeCategory("用户缓存", size: 1_000_000_000)]

        XCTAssertEqual(DashboardReclaim.totalBytes(of: categories), 1_000_000_000,
                       "总量只能包含删得掉的那部分")
        guard case .measured(let total, let count) = DashboardReclaim.state(from: categories) else {
            return XCTFail("存在可清理项时必须给出数字")
        }
        XCTAssertEqual(total, 1_000_000_000)
        XCTAssertEqual(count, 1, "类别数要与求和集合一致，不能显示 2 类却只算了 1 类")
    }

    /// 全都是只读：这不是"可清理 0 B"，而是没有可操作项，不能报一个像成功一样的数字。
    func testAllReadOnlyYieldsNoNumber() {
        let categories = [makeCategory("系统级缓存", size: 5_000_000_000, risk: .readOnly)]
        XCTAssertTrue(DashboardReclaim.state(from: categories).isMeasuredValue == false)
    }

    /// 端到端：CacheScanner 指向临时目录（home/varRoot/systemLibrary 全在 tmp 下），
    /// 概览页的可清理数字来自这份真实扫描，且与分类求和一致。
    func testScanAgainstTempHomeSumsToReportedTotal() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacMaster-DashboardTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let caches = tmp.appendingPathComponent("Library/Caches/test.app")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: 4096).write(to: caches.appendingPathComponent("blob.bin"))

        let scanner = CacheScanner(home: tmp.path,
                                   varRoot: tmp.appendingPathComponent("varf").path,
                                   systemLibrary: tmp.appendingPathComponent("lib").path,
                                   userCacheRoot: nil)
        let categories = await scanner.scanAll()
        let total = DashboardReclaim.totalBytes(of: categories)
        XCTAssertGreaterThan(total, 0, "临时目录里放了 4 KB 缓存，扫描结果不能为零")
        // 与"可清理"口径一致：只累加删得掉的类别。
        let deletable = DashboardReclaim.deletableCategories(categories)
        XCTAssertEqual(total, deletable.reduce(UInt64(0)) { $0 + $1.scannedSize })

        guard case .measured(let stateTotal, let count) = DashboardReclaim.state(from: categories) else {
            return XCTFail("有效扫描必须进入 measured 状态")
        }
        XCTAssertEqual(stateTotal, total)
        XCTAssertEqual(count, deletable.count)
    }

    // MARK: 存储堆叠条

    private func bytes(_ gib: Double) -> UInt64 { UInt64(gib * 1_073_741_824) }

    func testStorageSegmentsAlwaysSumToVolumeTotal() {
        let cases: [(UInt64, UInt64, UInt64?, UInt64?)] = [
            (bytes(500), bytes(28), bytes(3), bytes(1)),
            (bytes(500), bytes(28), nil, nil),          // 还没扫描
            (bytes(500), bytes(28), bytes(400), nil),   // 扫描结果异常偏大
            (bytes(500), bytes(500), bytes(10), bytes(10)),
            (0, 0, nil, nil),
        ]
        for (total, available, reclaim, trash) in cases {
            let segments = StorageBreakdown.segments(total: total, available: available,
                                                     reclaimable: reclaim, trash: trash)
            XCTAssertEqual(segments.reduce(UInt64(0)) { $0 + $1.bytes }, total,
                           "分段之和必须等于整卷容量：\(segments)")
            XCTAssertFalse(segments.contains { $0.bytes == 0 }, "零字节段不该出现在条子上")
        }
    }

    func testStorageSegmentsDropUnmeasuredParts() {
        let segments = StorageBreakdown.segments(total: bytes(100), available: bytes(40),
                                                 reclaimable: nil, trash: nil)
        XCTAssertEqual(segments.map(\.id), ["used", "available"], "没扫过就不该凭空多出一段“可清理”")
        XCTAssertEqual(segments.first?.bytes, bytes(60))
    }

    func testStorageSegmentsClampStaleScanAgainstCurrentVolume() {
        // 扫描之后用户又清掉了一半：可清理 + 废纸篓 超过当前已用量时必须截断，
        // 否则“其他已用”会下溢成一个天文数字。
        let segments = StorageBreakdown.segments(total: bytes(100), available: bytes(95),
                                                 reclaimable: bytes(3), trash: bytes(3))
        XCTAssertEqual(segments.map(\.id), ["reclaimable", "trash", "available"])
        XCTAssertEqual(segments.first?.bytes, bytes(3))
        XCTAssertEqual(segments.first { $0.id == "trash" }?.bytes, bytes(2),
                       "已用 5 - 可清理 3 = 2，废纸篓只能占剩下的 2")
        XCTAssertEqual(segments.reduce(UInt64(0)) { $0 + $1.bytes }, bytes(100))
    }

    func testLowSpaceThresholdIsTenPercent() {
        XCTAssertTrue(StorageBreakdown.isLowSpace(total: bytes(100), available: bytes(9)))
        XCTAssertFalse(StorageBreakdown.isLowSpace(total: bytes(100), available: bytes(11)))
        XCTAssertFalse(StorageBreakdown.isLowSpace(total: 0, available: 0), "读不到卷就不许报警")
    }

    // MARK: 内存构成

    func testMemoryCompositionRequiresAllThreeCounters() {
        let complete = DashboardMemory.Reading(total: bytes(24), used: bytes(16),
                                               active: bytes(9), wired: bytes(4),
                                               compressed: bytes(3), swapUsed: 0, swapTotal: bytes(8))
        let parts = MemoryComposition.parts(complete)
        XCTAssertEqual(parts?.map(\.id), ["active", "wired", "compressed", "free"])
        XCTAssertEqual(parts?.reduce(UInt64(0)) { $0 + $1.bytes }, bytes(24), "各段之和必须正好是物理内存")

        let missingWired = DashboardMemory.Reading(total: bytes(24), used: bytes(16),
                                                   active: bytes(9), wired: nil,
                                                   compressed: bytes(3), swapUsed: 0, swapTotal: 0)
        XCTAssertNil(MemoryComposition.parts(missingWired),
                     "缺 wired 就不能把差额全塞进“未占用”，那是一条骗人的绿条")
    }

    func testMemoryCompositionRejectsImpossibleReading() {
        let bogus = DashboardMemory.Reading(total: bytes(8), used: bytes(16),
                                            active: bytes(9), wired: bytes(8),
                                            compressed: bytes(3), swapUsed: 0, swapTotal: 0)
        XCTAssertNil(MemoryComposition.parts(bogus))
    }

    // MARK: 结论文案

    func testLoadVerdictNeedsBothNumbers() {
        XCTAssertNil(LoadVerdict.text(cpu: nil, memoryPressure: 0.2), "没量到就不下“运行平稳”的结论")
        XCTAssertEqual(LoadVerdict.text(cpu: 0.3, memoryPressure: 0.5), "运行平稳")
        XCTAssertEqual(LoadVerdict.text(cpu: 0.8, memoryPressure: 0.1), "负载偏高")
        XCTAssertEqual(LoadVerdict.text(cpu: 0.1, memoryPressure: 0.9), "负载偏高")
    }

    func testCoreNoteFallsBackToCaliberWhenSplitMissing() {
        XCTAssertEqual(DashboardText.cpuCoreNote(total: 10, performance: 4, efficiency: 6), "4 性能 + 6 能效")
        XCTAssertEqual(DashboardText.cpuCoreNote(total: 10, performance: nil, efficiency: 6), "跨所有核总占用")
        XCTAssertEqual(DashboardText.cpuCoreNote(total: 10, performance: 4, efficiency: 4), "跨所有核总占用",
                       "拆分加起来对不上总核数就是读错了，宁可不报")
    }
}
