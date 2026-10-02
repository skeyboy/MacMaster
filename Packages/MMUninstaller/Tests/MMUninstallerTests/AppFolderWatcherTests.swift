import Foundation
import XCTest
@testable import MMUninstaller

// MARK: - 判定规则（纯函数）

/// `AppWatchRule` 的两个判据都是纯函数：给两份清单，要一个差异结论。
/// 这里不放任何监听器，因为事件什么时候到是不确定的，而判据必须每次都一样。
final class AppWatchRuleTests: XCTestCase {

    private func snapshot(_ entry: String, _ bundleID: String, _ name: String? = nil) -> AppWatchRule.Snapshot {
        AppWatchRule.Snapshot(entry: entry, bundleID: bundleID, name: name ?? bundleID)
    }

    /// 消失的判据是**条目名**，身份却必须从基线取：本体一旦离开目录，
    /// `Info.plist` 就读不到了，那时候再想知道它的包标识已经太晚。
    func testDepartedTakesIdentityFromBaselineNotFromDisk() {
        let baseline = [snapshot("Foo.app", "com.example.Foo", "富"),
                        snapshot("Bar.app", "com.example.Bar")]
        let gone = AppWatchRule.departed(current: ["Bar.app"], baseline: baseline)
        XCTAssertEqual(gone.count, 1)
        XCTAssertEqual(gone.first?.entry, "Foo.app")
        XCTAssertEqual(gone.first?.bundleID, "com.example.Foo")
        XCTAssertEqual(gone.first?.name, "富", "显示名要在还能读的时候记下来")
    }

    func testDepartedReportsEveryMissingEntry() {
        let baseline = [snapshot("A.app", "a"), snapshot("B.app", "b")]
        XCTAssertEqual(AppWatchRule.departed(current: [], baseline: baseline).count, 2,
                       "整个目录被清空时一条都不能漏")
        XCTAssertEqual(AppWatchRule.departed(current: ["A.app", "B.app"], baseline: baseline).count, 0)
    }

    /// 反向判据只给条目名：这里报的是"清单过期"，不是"这是个可卸载应用"。
    func testAppearedReportsOnlyNewNames() {
        XCTAssertEqual(AppWatchRule.appeared(current: ["Foo.app", "note.txt", "Bar.app"],
                                             baseline: ["Bar.app"]),
                       ["Foo.app", "note.txt"])
    }

    /// 空基线时整个目录都是新条目 —— 第一次列举之后基线就建立了，这一步只在夹具里出现。
    func testAppearedAgainstEmptyBaselineReportsEveryEntry() {
        XCTAssertEqual(AppWatchRule.appeared(current: ["Foo.app", "Bar.app"], baseline: []),
                       ["Foo.app", "Bar.app"])
    }
}

// MARK: - 监听器（/tmp 或临时目录夹具）

@MainActor
final class AppFolderWatcherFixtureTests: XCTestCase {
    private var fixture: ResidualFixture!
    private var appsPath: String = ""

    override func setUpWithError() throws {
        fixture = try ResidualFixture(caseName: name)
        appsPath = fixture.root.appendingPathComponent("Applications", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: appsPath, withIntermediateDirectories: true)
    }

    override func tearDown() {
        fixture?.cleanup()
        fixture = nil
        super.tearDown()
    }

    private func watcher(directories: [String]? = nil) -> AppFolderWatcher {
        AppFolderWatcher(directories: directories ?? [appsPath])
    }

    /// 事件合并窗口（400 ms）之后再轮条件，不把测试绑死在固定睡眠上。
    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(3)) async {
        let deadline = ContinuousClock().now.advanced(by: timeout)
        while ContinuousClock().now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// kqueue 在测试进程里不保证投递，所以这里直接喂一个事件：
    /// 判据来自重扫目录后的差异，与事件是谁产生的无关（探针实测事件体里本来就没有条目信息）。
    private func poke(_ watcher: AppFolderWatcher) { watcher.handleEvents(.write) }

    // MARK: 基线

    /// 首帧只建基线：进这一页之前就已经躺在目录里的应用，不是"刚消失"也不是"刚出现"。
    func testStartBuildsBaselineAndReportsNothing() async {
        _ = try? fixture.makeApp(name: "Already", bundleID: "com.example.Already",
                                 inApplicationsOf: fixture.root)
        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()

        XCTAssertEqual(watcher.status, .watching)
        await waitUntil({ !watcher.departures.isEmpty || !watcher.appearances.isEmpty },
                        timeout: .milliseconds(800))
        XCTAssertTrue(watcher.departures.isEmpty)
        XCTAssertTrue(watcher.appearances.isEmpty)
    }

    // MARK: 消失

    func testDepartureCarriesIdentityCapturedWhileTheAppWasStillThere() async throws {
        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()

        let path = try fixture.makeApp(name: "Ghost", bundleID: "com.example.Ghost",
                                       inApplicationsOf: fixture.root)
        poke(watcher)
        await waitUntil({ watcher.appearances.count == 1 })

        // 本体一旦没了就再也读不到 Info.plist：这一步是对整条设计的核心断言。
        try FileManager.default.removeItem(atPath: path)
        poke(watcher)
        await waitUntil({ watcher.departures.count == 1 })

        let departure = watcher.departures.first
        XCTAssertEqual(departure?.name, "Ghost")
        XCTAssertEqual(departure?.bundleID, "com.example.Ghost")
        XCTAssertEqual(departure?.path, "\(appsPath)/Ghost.app")
        XCTAssertEqual(departure?.directory, appsPath)
    }

    /// 消失又被放回来：那条提示当场失效。继续挂着就是给一个活应用递上删残留的入口。
    func testDepartureIsPrunedWhenTheAppComesBack() async throws {
        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()

        let path = try fixture.makeApp(name: "Back", bundleID: "com.example.Back",
                                       inApplicationsOf: fixture.root)
        poke(watcher)
        await waitUntil({ watcher.appearances.count == 1 })

        try FileManager.default.removeItem(atPath: path)
        poke(watcher)
        await waitUntil({ watcher.departures.count == 1 })
        XCTAssertEqual(watcher.departures.first?.entry, "Back.app")

        try fixture.makeApp(name: "Back", bundleID: "com.example.Back", inApplicationsOf: fixture.root)
        poke(watcher)
        await waitUntil({ watcher.departures.isEmpty })
        XCTAssertTrue(watcher.departures.isEmpty, "已经回到目录里的那条不能再报消失")
    }

    /// 离页再回页（同一个实例 stop → start）：上一轮的结论可能早就不成立。
    func testRestartReconcilesBothDirections() async throws {
        let watcher = watcher()
        watcher.start()
        let path = try fixture.makeApp(name: "Round", bundleID: "com.example.Round",
                                       inApplicationsOf: fixture.root)
        poke(watcher)
        await waitUntil({ watcher.appearances.count == 1 })
        try FileManager.default.removeItem(atPath: path)
        poke(watcher)
        await waitUntil({ watcher.departures.count == 1 })

        watcher.stop()
        // 期间用户把目录恢复了，然后又彻底删掉那个刚装的：两次 stop/start 之间没有任何事件。
        try fixture.makeApp(name: "Round", bundleID: "com.example.Round", inApplicationsOf: fixture.root)
        watcher.start()
        await waitUntil({ watcher.departures.isEmpty && watcher.appearances.isEmpty })
        XCTAssertTrue(watcher.departures.isEmpty, "已经回到目录里的那条不能再报消失")
        XCTAssertTrue(watcher.appearances.isEmpty, "已经在基线里的那条不能再报新出现")
        watcher.stop()
    }

    /// 没有包标识（缺 Info.plist）与系统自带包名都不报：
    /// 前者没有可靠的残留匹配线索，报出来只会给出一句"没找到残留"的假话。
    func testUnreadableBundleIDAndAppleOwnedEntriesAreNotReported() async throws {
        try FileManager.default.createDirectory(atPath: "\(appsPath)/Alias.app/Contents",
                                                withIntermediateDirectories: true)
        _ = try fixture.makeApp(name: "Safari", bundleID: "com.apple.Safari", inApplicationsOf: fixture.root)

        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()

        try FileManager.default.removeItem(atPath: "\(appsPath)/Alias.app")
        try FileManager.default.removeItem(atPath: "\(appsPath)/Safari.app")
        poke(watcher)
        await waitUntil({ !watcher.departures.isEmpty }, timeout: .milliseconds(800))
        XCTAssertTrue(watcher.departures.isEmpty)
    }

    // MARK: 新出现

    func testAppearanceReportsEntryNamesWithoutBundleIdentity() async throws {
        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()

        _ = try fixture.makeApp(name: "Notion", bundleID: "com.example.Notion", inApplicationsOf: fixture.root)
        // 一个读不出包标识的条目同样算"多了个东西"：这里报的是清单过期，不是"可卸载"。
        try FileManager.default.createDirectory(atPath: "\(appsPath)/Broken.app/Contents",
                                                withIntermediateDirectories: true)
        try fixture.writeFile("\(appsPath)/loose.txt")
        poke(watcher)
        await waitUntil({ watcher.appearances.count == 2 })

        XCTAssertEqual(watcher.appearances.map(\.entry).sorted(), ["Broken.app", "Notion.app"])
        XCTAssertTrue(watcher.departures.isEmpty)
    }

    func testDismissAppearancesKeepsDepartures() async throws {
        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()

        let gone = try fixture.makeApp(name: "Gone", bundleID: "com.example.Gone", inApplicationsOf: fixture.root)
        poke(watcher)
        await waitUntil({ watcher.appearances.count == 1 })
        try FileManager.default.removeItem(atPath: gone)
        poke(watcher)
        await waitUntil({ watcher.departures.count == 1 })

        watcher.dismissAppearances()
        XCTAssertTrue(watcher.appearances.isEmpty)
        XCTAssertEqual(watcher.departures.count, 1, "忽略「多了条目」不该顺手抹掉另一张卡")
    }

    // MARK: 降级

    /// 目录读不动要说"读不到"，不能冒充"目录是空的"。
    func testUnreadableDirectoryReportsReasonNotEmptiness() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: appsPath)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appsPath)
        }

        let watcher = watcher()
        watcher.start()
        defer { watcher.stop() }

        guard case .unreadable(let reason, let needsPermission) = watcher.status else {
            return XCTFail("读不到目录应升成 .unreadable，实际是 \(watcher.status)")
        }
        XCTAssertTrue(needsPermission, "0o000 是权限错误，该给授权入口")
        XCTAssertFalse(reason.isEmpty)
        XCTAssertTrue(watcher.departures.isEmpty)
    }

    /// 目录不存在与读不到是两件事：`~/Applications` 在多数机器上根本不存在，
    /// 那是事实不是故障，所以它只进 skipped 表，不升成横幅。
    func testMissingDirectoryIsSkippedNotEscalated() throws {
        let missing = fixture.root.appendingPathComponent("Nope", isDirectory: true).path
        let watcher = watcher(directories: [appsPath, missing])
        defer { watcher.stop() }
        watcher.start()

        XCTAssertEqual(watcher.status, .watching, "还有一个目录开着就不该说读不到")
        XCTAssertEqual(Array(watcher.skippedDirectories.keys), [missing])
        XCTAssertEqual(watcher.skippedDirectories[missing], "这台机器没有这个目录")
    }

    /// 全部目标都没打开才升成 `.unreadable`，并且逐个目录把原因列出来。
    func testAllTargetsMissingReportsUnreadableWithoutPermissionClaim() throws {
        let missingA = fixture.root.appendingPathComponent("A", isDirectory: true).path
        let missingB = fixture.root.appendingPathComponent("B", isDirectory: true).path
        let watcher = watcher(directories: [missingA, missingB])
        watcher.start()
        defer { watcher.stop() }

        guard case .unreadable(let reason, let needsPermission) = watcher.status else {
            return XCTFail("实际是 \(watcher.status)")
        }
        XCTAssertFalse(needsPermission, "目录不存在不是权限问题，这里不该给授权按钮")
        XCTAssertTrue(reason.contains(missingA) && reason.contains(missingB), reason)
    }

    // MARK: 监听范围与夹具钩子

    /// 钩子只认 /tmp：这条链路的下游会刷新归属清单并给出删除入口。
    func testWatchTargetsAcceptsOnlyTmpFixture() {
        let key = "MM_APPS_WATCH_FIXTURE_DIR"
        defer { unsetenv(key) }

        setenv(key, NSHomeDirectory() + "/Applications", 1)
        XCTAssertEqual(AppFolderWatcher.watchTargets(),
                       AppScanner.defaultSearchDirectories(home: NSHomeDirectory()),
                       "拒绝钩子时监听范围必须等于列举范围")

        setenv(key, "/tmp/mm-apps-watch-probe", 1)
        XCTAssertEqual(AppFolderWatcher.watchTargets(), ["/tmp/mm-apps-watch-probe"])
    }

    /// 默认监听范围必须**等于** `AppScanner` 的列举范围。
    /// 更宽就会为从来不在清单里的条目（`/Applications/Utilities/Foo.app`）报事件，
    /// 更窄就会漏报 —— 两边都算凭空造一次"装卸"。
    func testDefaultTargetsMatchScannerEnumeration() {
        XCTAssertEqual(AppFolderWatcher.watchTargets(),
                       AppScanner.defaultSearchDirectories(home: NSHomeDirectory()))
    }

    func testAggregateTextListsEveryDirectoryWithItsReason() {
        let text = AppFolderWatcher.aggregateText(["/Applications": "读不动", "~/Applications": "这台机器没有这个目录"])
        XCTAssertTrue(text.contains("/Applications：读不动"), text)
        XCTAssertTrue(text.contains("这台机器没有这个目录"), text)
    }
}

// MARK: - 消失之后必须先刷新清单再扫（回归）

/// `docs/analysis/apps-watch.md` §4.3 的那条陷阱：孤儿判定的依据是"本机已装应用清单"，
/// 而应用刚消失的那一刻清单**还是旧的、里面仍有它** —— 直接扫会把它自己的残留
/// 判成"有主人"，**恰好漏掉我们正要提示的那几项**。
/// 这条测试锁死"先刷清单、再扫"的顺序，不是"扫一下看看"。
@MainActor
final class StaleOwnerListingTests: XCTestCase {
    private var fixture: ResidualFixture!

    override func setUpWithError() throws {
        fixture = try ResidualFixture(caseName: "StaleOwner")
    }

    override func tearDown() {
        fixture?.cleanup()
        fixture = nil
        super.tearDown()
    }

    func testDepartedAppOwnResidualStopsBeingOwnedOnlyAfterRelisting() async throws {
        let model = UninstallerModel()
        model.optionsFactory = { ResidualScanOptions(home: self.fixture.homePath) }
        model.appDirectoriesFactory = { _ in [self.fixture.homePath + "/Applications"] }
        model.provenancePrefixesFactory = { _ in [] }
        model.provenanceReceiptsRootFactory = { _ in nil }

        let departing = try fixture.makeApp(name: "Highball", bundleID: "com.example.Highball",
                                            inApplicationsOf: self.fixture.home)
        _ = try fixture.makeApp(name: "Keeper", bundleID: "com.example.Keeper",
                                inApplicationsOf: self.fixture.home)
        // 它散在 ~/Library 的那部分：这就是提示要交给用户处置的东西。
        _ = try fixture.libraryFolder("Caches/com.example.Highball", under: self.fixture.home)

        await model.loadApps()
        XCTAssertEqual(model.apps.count, 2)

        try FileManager.default.removeItem(atPath: departing)

        await model.scanOrphans(home: fixture.homePath)
        XCTAssertFalse(model.orphans.contains { $0.owner == "com.example.Highball" },
                       "清单里它还在，所以这一版把它自己的残留认成了有主人 —— 这正是不能直接扫的理由")

        await model.reloadListing()
        XCTAssertEqual(model.apps.count, 1, "刷新只重举清单，不等体积测量")

        await model.scanOrphans(home: fixture.homePath)
        XCTAssertTrue(model.orphans.contains { $0.owner == "com.example.Highball" },
                      "刷完清单再扫，它才第一次成为没有主人的残留")
    }
}
