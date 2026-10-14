//
//  BatteryTests.swift — P37a 电池只读卡：判据层（装配 + 换算 + 可信区间）
//
//  这台开发机（Mac mini M4）没有电池，正分支不可能在真机上证。所以这套测试就是正分支的证：
//  喂字典进 `BatterySnapshot.assemble(from:)`，逐条钉住"量不出必须是 nil"。
//  字典的形状取自 2026-10-13 实跑 `swift Scripts/p37-battery-probe.swift` 的量测结果：
//  本机 `BatteryInstalled=No`，`CurrentCapacity/MaxCapacity/CycleCount/Voltage/TimeRemaining`
//  这些键**都在且都是 0**，而 `AppleRawMaxCapacity/DesignCapacity` **缺席**。
//  参考实现 stats 把读不到的分母强成 1（`docs/github-references/stats/Modules/Battery/readers.swift:106-116`），
//  于是没电池的机器也能报"健康度 100%"——下面每一条回退分支都在防这种写法。
//

import XCTest
@testable import MMMonitor

/// 假属性字典：只写这台机器会有 / 夹具要演的键，其余键缺席（= 读不出）。
/// NSNumber 那层是照探针量到的真实桥接写的：`BatteryInstalled` 在本机是 objCType `c` 的 NSNumber。
private func props(
    installed: Bool? = nil,
    current: Int? = nil,
    max: Int? = nil,
    rawCurrent: Int? = nil,
    rawMax: Int? = nil,
    design: Int? = nil,
    cycles: Int? = nil,
    minutes: Int? = nil,
    external: Bool? = nil,
    charging: Bool? = nil
) -> [String: Any] {
    var dict: [String: Any] = [:]
    if let installed { dict["BatteryInstalled"] = NSNumber(value: installed) }
    if let current { dict["CurrentCapacity"] = NSNumber(value: current) }
    if let max { dict["MaxCapacity"] = NSNumber(value: max) }
    if let rawCurrent { dict["AppleRawCurrentCapacity"] = NSNumber(value: rawCurrent) }
    if let rawMax { dict["AppleRawMaxCapacity"] = NSNumber(value: rawMax) }
    if let design { dict["DesignCapacity"] = NSNumber(value: design) }
    if let cycles { dict["CycleCount"] = NSNumber(value: cycles) }
    if let minutes { dict["TimeRemaining"] = NSNumber(value: minutes) }
    if let external { dict["ExternalConnected"] = NSNumber(value: external) }
    if let charging { dict["IsCharging"] = NSNumber(value: charging) }
    return dict
}

private func assemble(_ dict: [String: Any]) -> BatterySnapshot {
    BatterySnapshot.assemble(from: BatteryRawValues(from: dict))
}

final class BatteryDecodingTests: XCTestCase {

    /// 本机实测那一档：键都在、值全 0。解码层照实读回 0（那是"读到 0"），
    /// 判状态是装配层的事——这一层不许把 0 改成 nil，也不许反过来。
    func testDesktopShapeDecodesZerosNotMissing() {
        let raw = BatteryRawValues(from: props(
            installed: false, current: 0, max: 0, cycles: 0, minutes: 0, external: true, charging: false))
        XCTAssertEqual(raw.installed, false)
        XCTAssertEqual(raw.currentCapacity, 0)
        XCTAssertEqual(raw.maxCapacity, 0)
        XCTAssertNil(raw.designCapacity, "本机没有 DesignCapacity 这个键，必须是 nil 而不是 0")
        XCTAssertNil(raw.appleRawMaxCapacity)
    }

    /// 布尔键在 IORegistry 里是 NSNumber(objCType `c`)，不是 Swift Bool——桥接要认。
    func testBooleanKeysBridgeFromNSNumber() {
        XCTAssertEqual(BatteryRawValues(from: ["BatteryInstalled": NSNumber(value: true)]).installed, true)
        XCTAssertEqual(BatteryRawValues(from: ["ExternalConnected": true]).externalConnected, true)
        XCTAssertEqual(BatteryRawValues(from: ["IsCharging": NSNumber(value: false)]).isCharging, false)
    }

    /// 类型不是数字也不是布尔（异常环境）→ nil，不塌成 0，也不瞎猜。
    func testUnexpectedValueTypesStayNil() {
        let raw = BatteryRawValues(from: ["CycleCount": "N/A", "BatteryInstalled": "Yes"])
        XCTAssertNil(raw.cycleCount)
        XCTAssertNil(raw.installed)
    }
}

final class BatteryAssemblyTests: XCTestCase {

    // MARK: 状态三档

    /// "这台机器没有电池"是一句事实，不是故障：它必须是 noBattery 档，
    /// 而且整卡一句话——连外接电源那行也不摆（旁边挂个"已接通"看着像在说电池）。
    func testNoBatteryIsItsOwnBranchNotAFailure() {
        let snapshot = assemble(props(installed: false, current: 0, max: 0, cycles: 0, external: true))
        XCTAssertEqual(snapshot.status, .noBattery)
        XCTAssertNil(snapshot.level, "没有电池时 0 是占位值，报成 0% 是假话")
        XCTAssertNil(snapshot.health)
        XCTAssertNil(snapshot.cycleCount)
        XCTAssertNil(snapshot.isExternalConnected)
    }

    /// 键本身缺席 = 连有没有电池都不知道，这必须是"读不到 + 原因"，不能默认成"没有电池"。
    func testMissingInstalledKeyIsUnavailableWithReason() {
        let snapshot = assemble(props(current: 62, max: 100))
        guard case .unavailable(let reason) = snapshot.status else {
            return XCTFail("BatteryInstalled 缺席必须落进 unavailable")
        }
        XCTAssertTrue(reason.contains("BatteryInstalled"), "原因要点名是哪一问不到，实际是：\(reason)")
    }

    /// 有电池但一个可信读数都没有：同 `SensorsSnapshot.loaded` 的规矩——
    /// 不留"状态说 loaded、每行都是 —"这种自相矛盾的分支。
    func testInstalledWithNothingReadableIsUnavailable() {
        let snapshot = assemble(props(installed: true, minutes: 0))
        guard case .unavailable = snapshot.status else {
            return XCTFail("电量/健康度/循环全无可信读数时应落 unavailable，实际 \(snapshot.status)")
        }
    }

    /// 首帧之前不是故障：话术与 `MetricSnapshot.empty`、`SensorsSnapshot.notSampled` 同源。
    func testNotSampledWording() {
        guard case .unavailable(let reason) = BatterySnapshot.notSampled.status else {
            return XCTFail("notSampled 应该是 unavailable 档")
        }
        XCTAssertEqual(reason, "尚未完成首次采样")
    }

    // MARK: 电量

    /// Apple Silicon 上 `CurrentCapacity` 是百分数、`MaxCapacity` 恒为 100：这一对要能除出电量。
    func testPercentPair() {
        let snapshot = assemble(props(installed: true, current: 62, max: 100))
        XCTAssertEqual(snapshot.status, .loaded)
        XCTAssertEqual(snapshot.level!, 0.62, accuracy: 0.0001)
    }

    /// mAh 那一对（`AppleRaw*`）才是真实剩余，优先级高于百分数对。
    func testRawPairWinsOverPercentPair() {
        let snapshot = assemble(props(installed: true, current: 90, max: 100, rawCurrent: 3_000, rawMax: 5_000))
        XCTAssertEqual(snapshot.level!, 0.6, accuracy: 0.0001, "取 mAh 口径的 3000/5000，不是 90/100")
    }

    /// 分母 0：本机那一档就是这个形状（`MaxCapacity=0`）。除它是除零，钳它是编数——只能 nil。
    func testZeroDenominatorNeverDivides() {
        let snapshot = assemble(props(installed: true, current: 0, max: 0, cycles: 12))
        XCTAssertNil(snapshot.level)
        XCTAssertEqual(snapshot.status, .loaded, "还有循环次数可读，整卡不该塌成不可用")
    }

    /// 分子 > 分母（两对口径被混着用的典型形状：3000 mAh 除 100 %）→ nil，
    /// **不钳到 100%**：钳过去就是把"口径错了"报成"电满了"。
    func testImpossibleRatioIsNilNotClamped() {
        let snapshot = assemble(props(installed: true, current: 3_000, max: 100, cycles: 12))
        XCTAssertNil(snapshot.level, "分子大于分母是口径不对，不是 100%")
    }

    // MARK: 健康度

    /// 健康度 = 满充容量 ÷ 设计容量。
    func testHealthIsRawMaxOverDesign() {
        let snapshot = assemble(props(installed: true, current: 62, max: 100, rawMax: 4_100, design: 5_000))
        XCTAssertEqual(snapshot.health!, 0.82, accuracy: 0.0001)
    }

    /// 本机实测就没有 `DesignCapacity`：没有可比的设计容量时必须 nil。
    /// 这一条是对着 stats 那句"读不到就把分母强成 1"写的——那种写法会显示健康度 100%。
    func testHealthNeedsDesignCapacity() {
        let snapshot = assemble(props(installed: true, current: 62, max: 100, rawMax: 4_100))
        XCTAssertNil(snapshot.health, "没有 DesignCapacity 就不是 100%，是 —")
    }

    /// 新电池满充容量略高于设计值是真事，钳到 100% 不算编数。
    func testHealthAboveHundredClamps() {
        let snapshot = assemble(props(installed: true, rawMax: 5_100, design: 5_000))
        XCTAssertEqual(snapshot.health!, 1.0, accuracy: 0.0001)
    }

    /// 单位对不上的形状（ARM 的百分数 `MaxCapacity=100` 冒充 mAh 去除设计容量 5000）→ nil。
    /// 0.02 会被 UI 写成"健康度 2%"，那是一句很像真话的假话，所以设了可信下限。
    func testHealthBelowPlausibleFloorIsNil() {
        let snapshot = assemble(props(installed: true, rawMax: 100, design: 5_000))
        XCTAssertNil(snapshot.health)
        XCTAssertLessThan(100.0 / 5_000.0, BatterySnapshot.plausibleHealthFloor, "前提：这一对确实低于下限")
    }

    // MARK: 循环 / 剩余时间 / 电源

    /// 0 次循环是新电池的真實读数，和"没读到"是两句话。
    func testCycleCountZeroIsRealZero() {
        let snapshot = assemble(props(installed: true, current: 100, max: 100, cycles: 0))
        XCTAssertEqual(snapshot.cycleCount, 0)
        XCTAssertEqual(snapshot.status, .loaded)
    }

    /// 键在胡说（读到几万）→ nil。真实锂电记录在数千量级。
    func testCycleCountAbovePlausibleRangeIsNil() {
        let snapshot = assemble(props(installed: true, current: 62, max: 100, cycles: 50_000))
        XCTAssertNil(snapshot.cycleCount)
    }

    /// `TimeRemaining` 的 0 与 -1 都是"系统没给估计"；超过一天也是胡说。
    func testTimeRemainingPlausibility() {
        XCTAssertNil(assemble(props(installed: true, cycles: 0, minutes: 0)).timeRemainingMinutes)
        XCTAssertNil(assemble(props(installed: true, cycles: 0, minutes: -1)).timeRemainingMinutes)
        XCTAssertNil(assemble(props(installed: true, cycles: 0, minutes: 20_000)).timeRemainingMinutes)
        XCTAssertEqual(assemble(props(installed: true, cycles: 0, minutes: 195)).timeRemainingMinutes, 195)
    }

    /// 充电状态与外接电源是电池在位时才摆的两行；读不出留 nil。
    func testChargingFlagsPassThrough() {
        let snapshot = assemble(props(installed: true, current: 62, max: 100, external: true, charging: true))
        XCTAssertEqual(snapshot.isCharging, true)
        XCTAssertEqual(snapshot.isExternalConnected, true)
        let bare = assemble(props(installed: true, current: 62, max: 100))
        XCTAssertNil(bare.isCharging)
        XCTAssertNil(bare.isExternalConnected)
    }
}

/// 呈现层的三句文案也是判据：它们决定用户看到的是"没有"还是"不知道"。
/// 抽成 `MonitorView` 的静态函数（不是 private）就是为了这一族能被钉住。
final class BatteryPresentationTests: XCTestCase {

    private func snapshot(external: Bool?, charging: Bool?) -> BatterySnapshot {
        BatterySnapshot(status: .loaded, level: 0.63, health: 0.82, cycleCount: 214,
                        isCharging: charging, isExternalConnected: external, timeRemainingMinutes: nil)
    }

    func testPercentTextRoundsAndKeepsNilDash() {
        XCTAssertEqual(MonitorView.batteryPercentText(nil), "—")
        XCTAssertEqual(MonitorView.batteryPercentText(0.634), "63%")
        XCTAssertEqual(MonitorView.batteryPercentText(0.0), "0%")
        XCTAssertEqual(MonitorView.batteryPercentText(1.0), "100%")
    }

    func testTimeTextShapes() {
        XCTAssertEqual(MonitorView.batteryTimeText(45), "45 分钟")
        XCTAssertEqual(MonitorView.batteryTimeText(120), "2 小时")
        XCTAssertEqual(MonitorView.batteryTimeText(96), "1 小时 36 分")
    }

    func testStateTextDistinguishesNoReadingFromNoPower() {
        XCTAssertEqual(MonitorView.batteryStateText(snapshot(external: true, charging: true)), "充电中")
        XCTAssertEqual(MonitorView.batteryStateText(snapshot(external: true, charging: false)), "已接通电源，未充电")
        XCTAssertEqual(MonitorView.batteryStateText(snapshot(external: false, charging: false)), "电池供电")
        // 两个键互相矛盾（没接外接却在充电）→ 不编话。
        XCTAssertEqual(MonitorView.batteryStateText(snapshot(external: false, charging: true)), "—")
        XCTAssertEqual(MonitorView.batteryStateText(snapshot(external: nil, charging: nil)), "—")
        XCTAssertEqual(MonitorView.batteryStateText(snapshot(external: true, charging: nil)),
                       "外接电源已接通（充电状态读不出）")
        XCTAssertEqual(MonitorView.batteryStateText(snapshot(external: nil, charging: true)),
                       "充电中（电源来源读不出）")
    }
}

/// 夹具档位：电池的正分支在真机上不可达，出片全靠这几档，所以"哪一档给了什么值"
/// 与"留痕行说了哪一档"都要能被钉住（取证脚本判夹具生效只看留痕行，不看照片）。
final class BatteryFixtureTierTests: XCTestCase {

    /// 底座说真话：这台开发机没有电池，`populated` 那一档的电池就是 noBattery，
    /// 有电池的每一档必须显式注入，不能靠底座默认值冒充。
    func testBaseTierKeepsMachineTruth() {
        XCTAssertEqual(MonitorSnapshotFixture.parse("populated").snapshot?.battery.status, .noBattery)
    }

    func testLoadedTierValues() {
        let battery = MonitorSnapshotFixture.parse("battery").snapshot?.battery
        XCTAssertEqual(battery?.status, .loaded)
        XCTAssertNil(battery?.timeRemainingMinutes, "loaded 底座不给剩余时间估计")
        XCTAssertEqual(battery?.cycleCount, 214)
        // 夹具的健康度与单测那组字典同源（4100 ÷ 5000 = 82%），出片的数与判据的数不是两套话。
        XCTAssertEqual(battery!.level!, 0.63, accuracy: 0.0001)
        XCTAssertEqual(battery!.health!, 0.82, accuracy: 0.0001)
    }

    func testNoHealthTier() {
        let battery = MonitorSnapshotFixture.parse("batteryNoHealth").snapshot?.battery
        XCTAssertEqual(battery?.status, .loaded)
        XCTAssertNil(battery?.health)
        XCTAssertEqual(battery!.level!, 0.63, accuracy: 0.0001, "只有健康度这一格退掉，其余不动")
    }

    func testChargingTierCarriesBothRows() {
        let battery = MonitorSnapshotFixture.parse("batteryCharging").snapshot?.battery
        XCTAssertEqual(battery?.isCharging, true)
        XCTAssertEqual(battery?.timeRemainingMinutes, 96)
        XCTAssertEqual(MonitorView.batteryStateText(battery!), "充电中")
    }

    func testUnavailableTierReasonPassthrough() {
        let parsed = MonitorSnapshotFixture.parse("battery-unavailable:自定义原因")
        guard case .unavailable(let reason)? = parsed.snapshot?.battery.status else {
            return XCTFail("应落到 unavailable 档")
        }
        XCTAssertEqual(reason, "自定义原因")
        // 冒号后为空 → 整批作废（不留"reason 缺失但档位生效"的半吊子夹具）。
        let empty = MonitorSnapshotFixture.parse("battery-unavailable:")
        XCTAssertNil(empty.snapshot)
        XCTAssertEqual(empty.rejected, ["battery-unavailable:"])
    }

    /// 留痕行的插值必须把档位名说清楚：`VolumeFixtureTier.appliedNote` 那一族第一版
    /// 漏写插值，日志里打印的是字面量，照片照常、判据却是假的。
    func testAppliedNoteNamesTheTier() {
        XCTAssertEqual(MonitorFixtureTier.battery.appliedNote,
                       "MM_MONITOR_FIXTURE=battery 已生效：这是合成快照，不是这台机器的读数")
        XCTAssertTrue(MonitorFixtureTier.batteryNoHealth.appliedNote.contains("batteryNoHealth"))
    }
}
