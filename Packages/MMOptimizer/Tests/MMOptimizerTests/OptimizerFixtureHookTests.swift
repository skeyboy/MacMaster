import Foundation
import XCTest
@testable import MMOptimizer

/// MM_OPTIMIZER_FIXTURE 的判据：合法档位逐个对上、含非法取值整批作废。
/// 与其它夹具（`GuardianFixtureHookTests` / `SensorTests`）同一条口径——
/// "半生效夹具 = 假通过"这句话只有钉住才算数。
final class OptimizerFixtureHookTests: XCTestCase {
    func testNilAndEmptyLeaveEverythingAlone() {
        for raw in [nil, ""] {
            let r = OptimizerFixture.parse(raw)
            XCTAssertNil(r.duplicates)
            XCTAssertNil(r.browser)
            XCTAssertNil(r.status)
            XCTAssertNil(r.devtools)
            XCTAssertNil(r.preferences)
            XCTAssertNil(r.caveat)
            XCTAssertFalse(r.protected)
            XCTAssertTrue(r.rejected.isEmpty)
        }
    }

    func testLegalTiersParse() {
        XCTAssertEqual(OptimizerFixture.parse("duplicates:3").duplicates, .groups(count: 3))
        XCTAssertEqual(OptimizerFixture.parse("duplicates:empty").duplicates, .empty)
        XCTAssertEqual(OptimizerFixture.parse("duplicates:scannedEmpty").duplicates, .scannedEmpty)
        XCTAssertEqual(OptimizerFixture.parse("browser:rows").browser, .rows)
        XCTAssertEqual(OptimizerFixture.parse("browser:empty").browser, .empty)
        XCTAssertEqual(OptimizerFixture.parse("status:allReadOnly").status, .allReadOnly)
        XCTAssertEqual(OptimizerFixture.parse("devtools:notInstalled").devtools, .notInstalled)
        XCTAssertEqual(OptimizerFixture.parse("devtools:unreadable").devtools, .unreadable)
        XCTAssertEqual(OptimizerFixture.parse("prefs:broken").preferences, .broken)
        XCTAssertEqual(OptimizerFixture.parse("prefs:unreadable").preferences, .unreadable)
        XCTAssertEqual(OptimizerFixture.parse("prefs:empty").preferences, .empty)
        XCTAssertEqual(OptimizerFixture.parse("prefs:partial").preferences, .partial)
        XCTAssertTrue(OptimizerFixture.parse("protected").protected)
        XCTAssertTrue(OptimizerFixture.parse("protected").rejected.isEmpty)
    }

    func testSeveralTiersCanBeGivenTogether() {
        let r = OptimizerFixture.parse("duplicates:2,browser:rows,status:allReadOnly,protected")
        XCTAssertEqual(r.duplicates, .groups(count: 2))
        XCTAssertEqual(r.browser, .rows)
        XCTAssertEqual(r.status, .allReadOnly)
        XCTAssertTrue(r.protected)
        XCTAssertTrue(r.rejected.isEmpty)
    }

    func testIllegalValueVoidsWithTheWholeHook() {
        // duplicates 合法、devtools 打错一个字 → 整批作废，且点名是哪一项。
        let r = OptimizerFixture.parse("duplicates:2,devtools:notinstal")
        XCTAssertNil(r.duplicates)
        XCTAssertNil(r.devtools)
        XCTAssertEqual(r.rejected, ["devtools:notinstal"])
    }

    /// prefs 那一族同一条铁律：写错一个字母就整批作废（`prefs:brokenn`）。
    func testPrefsTierTypoVoidsWithTheWholeHook() {
        let r = OptimizerFixture.parse("prefs:brokenn")
        XCTAssertNil(r.preferences)
        XCTAssertEqual(r.rejected, ["prefs:brokenn"])
        // 与别的 tab 叠加时也不许只落 prefs 之外的那一半。
        let mixed = OptimizerFixture.parse("browser:rows,prefs:unreadablee")
        XCTAssertNil(mixed.browser)
        XCTAssertNil(mixed.preferences)
    }

    func testZeroOrNegativeGroupCountIsRejected() {
        for raw in ["duplicates:0", "duplicates:-2", "duplicates:abc"] {
            let r = OptimizerFixture.parse(raw)
            XCTAssertNil(r.duplicates, raw)
            XCTAssertEqual(r.rejected, [raw], raw)
        }
    }

    // MARK: caveat 横幅计数

    func testCaveatCountsParseAndCombine() {
        XCTAssertEqual(OptimizerFixture.parse("duplicates:2,caveat:unreadable:3").caveat,
                       OptimizerFixture.CaveatCounts(unreadable: 3, dataless: 0))
        XCTAssertEqual(OptimizerFixture.parse("duplicates:2,caveat:dataless:5").caveat,
                       OptimizerFixture.CaveatCounts(unreadable: 0, dataless: 5))
        let both = OptimizerFixture.parse("duplicates:2,caveat:unreadable:3,caveat:dataless:5")
        XCTAssertEqual(both.caveat, OptimizerFixture.CaveatCounts(unreadable: 3, dataless: 5))
        XCTAssertTrue(both.rejected.isEmpty)
    }

    /// 计数没有分组可挂，拍出来就是"列表说没有结果、横幅说有些文件没参与判定"的自相矛盾照片。
    func testCaveatWithoutGroupsIsRejected() {
        let r = OptimizerFixture.parse("caveat:unreadable:3")
        XCTAssertNil(r.caveat)
        XCTAssertEqual(r.rejected.count, 1)
        XCTAssertTrue(r.rejected[0].contains("caveat"))
    }

    func testMalformedCaveatIsRejected() {
        for raw in ["duplicates:2,caveat:unreadable", "duplicates:2,caveat:unreadable:0",
                    "duplicates:2,caveat:unreadable:x", "duplicates:2,caveat:something:2",
                    "duplicates:2,caveat:unreadable:3:4"] {
            let r = OptimizerFixture.parse(raw)
            XCTAssertNil(r.caveat, raw)
            XCTAssertNil(r.duplicates, raw)
            XCTAssertFalse(r.rejected.isEmpty, raw)
        }
    }

    // MARK: 合成数据自身的形状

    /// 夹具条目必须一眼可辨：路径在 /tmp 下、走真实构造器算 wastedSpace（size × (n-1)）。
    func testSyntheticGroupsAreIdentifiablyFixtureData() {
        let groups = OptimizerFixture.duplicateGroups(count: 3)
        XCTAssertEqual(groups.count, 3)
        for (i, group) in groups.enumerated() {
            XCTAssertTrue(group.files.allSatisfy { $0.path.path.hasPrefix("/tmp/mm-optimizer-fixture/") })
            XCTAssertEqual(group.files.count, 3)
            XCTAssertEqual(group.wastedSpace, UInt64(1_048_576 * (i + 1)) * 2)
        }
    }

    /// 末位一行 size=nil 是"测量中"那一档的来源，不能悄悄变成 0。
    func testBrowserRowsEndWithAnUnmeasuredRow() {
        let rows = OptimizerFixture.browserRows()
        XCTAssertEqual(rows.count, 3)
        XCTAssertNil(rows.last?.size)
        XCTAssertTrue(rows.dropLast().allSatisfy { $0.size != nil })
    }

    /// 两档 devtools 夹具走的是同一套 caveat 文案口径：一条说"没装"、一条说"读不动"，
    /// 都不给数字（bytes=nil），否则照片上会出现"没装却报着体积"。
    func testDevtoolsFixtureNeverReportsASize() {
        for tier: OptimizerFixture.DevToolsTier in [.notInstalled, .unreadable] {
            let rows = OptimizerFixture.devtoolsRows(tier: tier)
            XCTAssertEqual(rows.count, 1)
            XCTAssertNil(rows[0].bytes)
            XCTAssertNotNil(rows[0].caveat)
            XCTAssertTrue(rows[0].root.hasPrefix("/tmp/mm-optimizer-fixture/"))
        }
    }

    /// 偏好文件四档各自的形状：两栏各归各的，夹具路径一眼可辨，
    /// 而且 `prefs:broken` 那档必须带一条非字典根（§5 那条脚注唯一能被拍到的入口）。
    func testPrefsFixtureTiersHaveTheirOwnShapes() {
        for tier: OptimizerFixture.PrefsTier in [.broken, .unreadable, .empty, .partial] {
            let scan = OptimizerFixture.prefsScan(tier: tier)
            XCTAssertTrue(scan.rows.allSatisfy { $0.path.hasPrefix("/tmp/mm-optimizer-fixture/Library/Preferences/") },
                          "\(tier)")
        }
        let broken = OptimizerFixture.prefsScan(tier: .broken)
        XCTAssertEqual(broken.badRows.count, 2)
        XCTAssertTrue(broken.unreadableRows.isEmpty)
        XCTAssertEqual(broken.nonDictRootCount, 1)

        let unreadable = OptimizerFixture.prefsScan(tier: .unreadable)
        XCTAssertEqual(unreadable.unreadableCount, 2)
        XCTAssertTrue(unreadable.badRows.isEmpty, "「读不到」不许混进「读不出来或空的那些」")

        let empty = OptimizerFixture.prefsScan(tier: .empty)
        XCTAssertTrue(empty.badRows.isEmpty)
        XCTAssertTrue(empty.unreadableRows.isEmpty)
        XCTAssertFalse(empty.isPartial)

        let partial = OptimizerFixture.prefsScan(tier: .partial)
        XCTAssertTrue(partial.isPartial)
        XCTAssertEqual(partial.notInspectedCount, 10_416)
        XCTAssertTrue(PreferencesCopy.headline(partial).contains("剩下的 10416 个没看"))
    }
}

/// 钉住 P6.6 实机撞到的那个坑：视图自己的 `.task` 会启动真实扫描，
/// 而真实扫描**比脚本等待的时间快**时，它会把夹具结果整批盖掉——
/// 照片上"没有发现可清理的浏览器缓存"看着像夹具生效，其实钩子白跑了一趟
/// （`browser:rows` 与 `browser:empty` 两张 PNG 的 md5 当时完全相同）。
@MainActor
final class OptimizerFixturePinTests: XCTestCase {
    func testBrowserFixtureSurvivesALaterRealScan() async {
        let model = BrowserCacheModel()
        model.applyFixture(.rows)
        XCTAssertEqual(model.items.count, 3)
        await model.scan()                       // 真实扫描：本机结果无所谓，重点是它不许覆盖夹具
        XCTAssertEqual(model.items.count, 3, "夹具注入后真实扫描不许把行盖掉")
        XCTAssertNil(model.items.last?.size, "末位那行「测量中」是这一档要拍的东西")
    }

    func testStatusFixtureSurvivesALaterRealRefresh() async {
        let model = SystemDiagnosticsModel()
        model.applyFixture(.allReadOnly)
        XCTAssertEqual(model.checks.count, 3)
        XCTAssertTrue(model.checks.allSatisfy { $0.value == "—" })
        await model.refresh()
        XCTAssertEqual(model.checks.count, 3, "夹具注入后真实读数不许把三行「—」换成实测值")
        XCTAssertTrue(model.checks.allSatisfy { $0.value == "—" })
    }

    func testUnpinnedModelsStillScanNormally() async {
        // 反向保底：没有夹具时不得有任何"钉住"痕迹，否则生产路径被钩子改坏了。
        let model = BrowserCacheModel()
        await model.scanIfNeeded()
        XCTAssertTrue(model.hasScanned)
        XCTAssertFalse(model.isScanning)
    }

    /// 新加的偏好文件 tab 自带 `.task`，而本机一趟只要两三百毫秒——
    /// 比脚本等待的时间快，正是 P6.6 那个"夹具被真实扫描盖掉"的坑的形态。
    func testPreferencesFixtureSurvivesALaterRealScan() async {
        let model = PreferenceFilesModel()
        model.applyFixture(.broken)
        XCTAssertEqual(model.scan?.badRows.count, 2)
        await model.refresh()
        XCTAssertEqual(model.scan?.badRows.count, 2, "夹具注入后真实那一趟不许把行盖掉")
        XCTAssertTrue(model.scan?.rows.allSatisfy { $0.path.hasPrefix("/tmp/mm-optimizer-fixture/") } == true)
    }

    func testUnpinnedPreferencesModelScansNormally() async {
        let model = PreferenceFilesModel()
        await model.refreshIfNeeded()
        XCTAssertNotNil(model.scan, "没给夹具时生产路径必须真的跑一趟")
    }
}
