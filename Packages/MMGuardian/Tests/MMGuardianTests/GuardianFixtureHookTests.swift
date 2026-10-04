//
//  GuardianFixtureHookTests.swift — 截图钩子判定逻辑本身的单测
//
//  覆盖的是"夹具档位怎么解析、注入的数据经真实判定管线会产出什么"，
//  不覆盖 SwiftUI 渲染（渲染核对走实机截图，见 docs/analysis/fidelity-guardian.md）。
//  全程零文件写入、零系统调用。
//

import XCTest
@testable import MMGuardian

final class GuardianFixtureHookTests: XCTestCase {

    private let fixtureHome = "/tmp/mmguardian-test-home"

    // MARK: - MM_GUARDIAN_FIXTURE 新增档（combo/conflict）

    func testDeviceFixtureAcceptsNewIndeterminateSubStates() {
        let r = DeviceUsageFixture.parse("mic=combo,camera=conflict")
        XCTAssertTrue(r.rejected.isEmpty)
        XCTAssertEqual(r.overrides[.mic], .indeterminate(.comboAmbiguity))
        XCTAssertEqual(r.overrides[.camera], .indeterminate(.enumeratorConflict))
    }

    func testDeviceFixtureOldTokensKeepMeaning() {
        // 向后兼容：老四档的映射一字不改，其他代理的截图口径依赖它。
        let r = DeviceUsageFixture.parse("camera=inuse,mic=idle")
        XCTAssertEqual(r.overrides[.camera], .inUse)
        XCTAssertEqual(r.overrides[.mic], .idle)
        let r2 = DeviceUsageFixture.parse("camera=unknown,mic=absent")
        XCTAssertEqual(r2.overrides[.camera], .indeterminate(.readFailed))
        XCTAssertEqual(r2.overrides[.mic], .deviceAbsent)
    }

    func testDeviceFixtureRejectsWholeHookWithNewBadToken() {
        // 新档不能变成"半生效"的入口：任何一个坏项整体作废。
        let r = DeviceUsageFixture.parse("mic=combo,camera=comboo")
        XCTAssertEqual(r.rejected, ["camera=comboo"])
        XCTAssertTrue(r.overrides.isEmpty)
    }

    // MARK: - MM_TCC_FIXTURE partial 档

    func testTCCFixturePartialIsUserRowsOnly() {
        guard case .partial(let rows, let note)? = TCCFixture.parse("partial").state else {
            return XCTFail("partial 档必须产出 .partial 状态")
        }
        XCTAssertFalse(rows.isEmpty)
        // 系统级库读不到的档里不许出现系统级行——那是自相矛盾的假数据。
        XCTAssertTrue(rows.allSatisfy { $0.source == .user })
        XCTAssertTrue(note.contains("系统级库读不到"))
        XCTAssertTrue(note.hasSuffix("——清单可能不完整"))
        XCTAssertTrue(TCCFixture.parse("partial").rejected.isEmpty)
    }

    func testTCCFixtureOldTokensKeepMeaning() {
        XCTAssertEqual(TCCFixture.parse("rows").rejected, [])
        XCTAssertEqual(TCCFixture.parse("empty").state, .emptyRead)
        if case .unreadable? = TCCFixture.parse("unreadable").state {} else {
            XCTFail("unreadable 档语义不能变")
        }
        // 非法值依旧整体作废，新档没有放宽合法值集合。
        XCTAssertEqual(TCCFixture.parse("partiall").rejected, ["partiall"])
        XCTAssertNil(TCCFixture.parse("partiall").state)
    }

    // MARK: - MM_GUARDIAN_LOGIN_FIXTURE 解析

    func testLoginFixtureParseWhitelist() {
        XCTAssertEqual(LoginItemFixture.parse("rows").stage, .rows)
        XCTAssertEqual(LoginItemFixture.parse("empty").stage, .empty)
        XCTAssertEqual(LoginItemFixture.parse("indeterminate").stage, .indeterminate)
        XCTAssertEqual(LoginItemFixture.parse("scanerror").stage, .scanerror)
        XCTAssertNil(LoginItemFixture.parse("rows").rejected)
    }

    func testLoginFixtureUnsetMeansNoInjection() {
        // 未设置/空串 = 钩子不存在，生产路径逐字节不变的前提。
        for raw in [nil, ""] {
            let r = LoginItemFixture.parse(raw)
            XCTAssertNil(r.stage)
            XCTAssertNil(r.rejected)
        }
    }

    func testLoginFixtureRejectsBadValueWholesale() {
        let r = LoginItemFixture.parse("/Users/lee/Library/LaunchAgents")
        XCTAssertNil(r.stage)
        XCTAssertEqual(r.rejected, "/Users/lee/Library/LaunchAgents")
    }

    // MARK: - 夹具条目 × 真实判定管线
    //
    // 注意：LoginItemAuditor 的孤儿判定内部用真实 NSHomeDirectory() 拼 knownPlistPaths，
    // 夹具条目也建在同一真实 home 下（名字一律 com.example.*，本机这些路径不存在）。
    // 注入别的 home 会让"条目路径"与"孤儿查找路径"对不上，反而测不到真实管线。

    func testLoginFixtureRowsProduceEachAnomalyBadge() {
        let items = LoginItemFixture.items()
        let audit = LoginItemFixture.audit()
        XCTAssertTrue(audit.determinate)

        func anomaly(_ label: String) -> LoginItemAnomaly? {
            audit.anomalies[items.first { $0.name == label }!.path]
        }
        XCTAssertEqual(anomaly("com.example.backup-agent"), .plistNotLoaded)
        XCTAssertEqual(anomaly("com.example.syncclient"), .disabledButLoaded)
        XCTAssertEqual(anomaly("com.example.viewer"), .plistNotLoaded)
        // 已加载且启用 / 改名停用 / LaunchDaemons / userPreferences 一律不标注。
        XCTAssertNil(anomaly("com.example.clipper"))
        XCTAssertNil(anomaly("com.example.telemetry"))
        XCTAssertNil(anomaly("com.example.daemon"))
        XCTAssertNil(anomaly("Example OldApp"))
    }

    func testLoginFixtureOrphanLabelsExcludeAppleAndTaskFamilies() {
        let audit = LoginItemFixture.audit()
        XCTAssertEqual(audit.orphanLabels, ["com.example.orphanhelper", "com.example.residuedaemon"])
    }

    func testLoginFixtureItemsAreObviouslySyntheticAndAbsentOnDisk() {
        // 与真实数据一眼可分（com.example.* / Example*），且这些路径在本机不存在——
        // 开关真被点到也只会在读取一步 ENOENT 失败，不会写进任何真实文件。
        let fm = FileManager.default
        for item in LoginItemFixture.items() {
            XCTAssertTrue(item.name.lowercased().contains("example"), item.name)
            XCTAssertFalse(fm.fileExists(atPath: item.path), item.path)
        }
    }

    func testLoginFixtureUserItemsMatchWritableDomain() {
        // 域标记与路径前缀自洽：用户域条目必须通过写策略的路径判定，
        // 否则行内开关形态和真实扫描结果就不是一回事。
        let items = LoginItemFixture.items(home: fixtureHome)
        for item in items where item.domain == .user {
            XCTAssertTrue(LaunchItemPolicy.isUserLaunchAgent(path: item.path, home: fixtureHome), item.path)
        }
        for item in items where item.domain == .system {
            XCTAssertFalse(item.isWritable, item.path)
        }
    }

    func testLoginFixtureIndeterminateAuditMarksItselfAsFixture() {
        let audit = LoginItemFixture.indeterminateAudit
        XCTAssertFalse(audit.determinate)
        XCTAssertTrue(audit.reason?.contains("夹具") == true)
    }

    func testLoginFixtureScanErrorLinesAreFlaggedAsFixture() {
        XCTAssertEqual(LoginItemFixture.scanErrorLines.count, 2)
        for line in LoginItemFixture.scanErrorLines {
            XCTAssertTrue(line.contains("夹具值"), line)
        }
    }

    // MARK: - MM_GUARDIAN_LOAD

    func testLoadHookOnlyAcceptsHold() {
        XCTAssertTrue(GuardianLoadHook.parse("hold").holdInitialFrame)
        XCTAssertTrue(GuardianLoadHook.parse("HOLD").holdInitialFrame)
        XCTAssertFalse(GuardianLoadHook.parse(nil).holdInitialFrame)
        XCTAssertFalse(GuardianLoadHook.parse("").holdInitialFrame)
        XCTAssertNil(GuardianLoadHook.parse(nil).rejected)
    }

    func testLoadHookBadValueFallsBackToProductionPath() {
        let r = GuardianLoadHook.parse("delay5")
        XCTAssertFalse(r.holdInitialFrame)
        XCTAssertEqual(r.rejected, "delay5")
    }

    // MARK: - MM_GUARDIAN_CARDS

    func testCardFilterKeepsPageOrderRegardlessOfInputOrder() {
        XCTAssertEqual(GuardianCardFilter.parse("activity,login").keep, [.login, .activity])
        XCTAssertEqual(GuardianCardFilter.parse(" ACTIVITY , tcc ").keep, [.tcc, .activity])
    }

    func testCardFilterUnsetRendersEveryCard() {
        XCTAssertNil(GuardianCardFilter.parse(nil).keep)
        XCTAssertNil(GuardianCardFilter.parse("").keep)
        XCTAssertNil(GuardianCardFilter.parse(nil).rejected)
    }

    /// 半生效的取景比不取景更坏：一张"只剩两张卡"的截图会被读成"这页本来只有两张卡"。
    func testCardFilterRejectsWholesaleOnAnyBadToken() {
        for raw in ["activity,bogus", "cards", "activty"] {
            let r = GuardianCardFilter.parse(raw)
            XCTAssertNil(r.keep, raw)
            XCTAssertEqual(r.rejected, raw)
        }
    }

    func testCardFilterDeduplicatesAndRejectsEmptySelection() {
        XCTAssertEqual(GuardianCardFilter.parse("login,login").keep, [.login])
        XCTAssertEqual(GuardianCardFilter.parse(",").rejected, ",")
        XCTAssertNil(GuardianCardFilter.parse(",").keep)
    }

    func testActivityFixtureParsesBothStagesAndRejectsOthers() {
        XCTAssertEqual(GuardianActivityFixture.parse("rows").stage, .rows)
        XCTAssertEqual(GuardianActivityFixture.parse("EMPTY").stage, .empty)
        XCTAssertNil(GuardianActivityFixture.parse(nil).stage)
        XCTAssertNil(GuardianActivityFixture.parse(nil).rejected)
        let bad = GuardianActivityFixture.parse("3")
        XCTAssertNil(bad.stage)
        XCTAssertEqual(bad.rejected, "3")
    }
}
