import Foundation
import Darwin
import XCTest
@testable import MMUninstaller

// MARK: - 判定规则

/// 纯规则：真实 `~/.Trash` 需要完全磁盘访问才读得动，测试不能拿它当前提，
/// 所以判定全部在 /tmp 夹具上跑。
final class TrashWatchRuleTests: XCTestCase {

    func testOnlyVisibleAppBundleNamesPass() {
        XCTAssertTrue(TrashWatchRule.isAppBundleEntry("Foo.app"))
        XCTAssertTrue(TrashWatchRule.isAppBundleEntry("My App.app"))
        XCTAssertTrue(TrashWatchRule.isAppBundleEntry("Foo 2.app"))
        XCTAssertFalse(TrashWatchRule.isAppBundleEntry("Foo"), "没有 .app 后缀就不是应用")
        XCTAssertFalse(TrashWatchRule.isAppBundleEntry(".DS_Store"))
        XCTAssertFalse(TrashWatchRule.isAppBundleEntry(".Hidden.app"), "隐藏项不进提示")
        XCTAssertFalse(TrashWatchRule.isAppBundleEntry(".app"), "只剩后缀的空名字不是应用")
    }

    /// 首帧只建基线：启动时废纸篓里已经躺着的应用不是"刚被拖进来"。
    func testFirstFrameReportsNothing() {
        XCTAssertEqual(TrashWatchRule.appearedEntries(current: ["Foo.app", "Bar.app"], previous: nil), [])
    }

    func testAppearedEntriesReportsOnlyNewNames() {
        let appeared = TrashWatchRule.appearedEntries(
            current: ["Foo.app", "Bar.app", "note.txt"],
            previous: ["Bar.app"]
        )
        XCTAssertEqual(appeared.sorted(), ["Foo.app", "note.txt"])
    }

    /// 读不出包名（替身、缺 Info.plist）与系统自带应用都不报：
    /// 前者没有可靠的残留匹配线索，后者删数据会破坏系统而不是回收空间。
    func testReportableRejectsBlankAndAppleBundleIDs() {
        XCTAssertTrue(TrashWatchRule.isReportable(bundleID: "com.example.Foo"))
        XCTAssertFalse(TrashWatchRule.isReportable(bundleID: ""))
        XCTAssertFalse(TrashWatchRule.isReportable(bundleID: "com.apple.Safari"))
        XCTAssertFalse(TrashWatchRule.isReportable(bundleID: "COM.APPLE.Safari"), "前缀判定不看大小写")
    }

    /// 验证钩子只能指向 /tmp：这条链路的尽头是删除按钮。
    func testFixtureHookRejectsPathsOutsideTmp() {
        let key = "MM_TRASH_FIXTURE_PROBE"
        defer { unsetenv(key) }

        setenv(key, NSHomeDirectory() + "/.Trash", 1)
        XCTAssertNil(TrashWatcher.fixtureEnvironmentValue(key: key))

        setenv(key, "/tmp/mm-trash-fixture", 1)
        XCTAssertEqual(TrashWatcher.fixtureEnvironmentValue(key: key), "/tmp/mm-trash-fixture")

        setenv(key, "", 1)
        XCTAssertNil(TrashWatcher.fixtureEnvironmentValue(key: key), "空值等于没设")
    }

    /// 我们自己卸载出来的那一条不读盘：目的地在 `~/.Trash`，而没有「完全磁盘访问」时
    /// 那里连列目录都做不到。拿不存在的路径构造也得成功 —— 一旦它去 stat 或读 Info.plist，
    /// 这张回声卡在真实机器上就会时隐时现。
    func testSelfMovedArrivalNeedsNoDiskAccess() {
        let ghost = "/tmp/does-not-exist-anywhere/Highball.app"
        guard let arrival = TrashArrival(selfMovedPath: ghost, name: "Highball",
                                         bundleID: "com.example.Highball") else {
            return XCTFail("卸载回声不该依赖读得到废纸篓")
        }
        XCTAssertEqual(arrival.path, ghost)
        XCTAssertEqual(arrival.id, ghost)
        XCTAssertEqual(arrival.entry, "Highball.app", "标题与「还在不在」都按条目名说话")
        XCTAssertEqual(arrival.name, "Highball", "名字用卸载前已读到的显示名，不是磁盘名")
        XCTAssertEqual(arrival.bundleID, "com.example.Highball")

        // 同一位置交给读盘的那条构造路径：文件不存在 → 读不出包名 → 不成立。
        XCTAssertNil(TrashArrival(trashDirectory: "/tmp/does-not-exist-anywhere", entry: "Highball.app"))
    }

    /// 系统自带应用即便被我们移走也不报：删它的数据是破坏系统，不是回收空间。
    func testSelfMovedArrivalRejectsSystemOwned() {
        XCTAssertNil(TrashArrival(selfMovedPath: "/tmp/x/Safari.app", name: "Safari",
                                  bundleID: "com.apple.Safari"))
        XCTAssertNil(TrashArrival(selfMovedPath: "/tmp/x/Foo.app", name: "Foo", bundleID: ""))
    }
}

// MARK: - 监听器（/tmp 夹具）

@MainActor
final class TrashWatcherFixtureTests: XCTestCase {
    private var fixture: ResidualFixture!
    private var trashPath: String = ""

    override func setUpWithError() throws {
        fixture = try ResidualFixture(caseName: name)
        let trash = fixture.root.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        trashPath = trash.path
    }

    override func tearDownWithError() throws {
        fixture?.cleanup()
        fixture = nil
    }

    /// 往假废纸篓里"移入"一个应用：先在别处造好 bundle 再挪进来，
    /// 这样条目是"新出现"的，和真实拖入的顺序一致。
    @discardableResult
    private func moveIntoTrash(name: String, bundleID: String) throws -> String {
        let source = try fixture.makeApp(name: name, bundleID: bundleID)
        let destination = "\(trashPath)/\(name).app"
        try FileManager.default.moveItem(atPath: source, toPath: destination)
        return destination
    }

    private func watcher() -> TrashWatcher { TrashWatcher(trashDirectory: trashPath) }

    /// 事件合并窗口之后再轮一下条件，避免把测试绑死在固定睡眠时长上。
    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(3)) async {
        let deadline = ContinuousClock().now.advanced(by: timeout)
        while ContinuousClock().now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func testStartWatchesAndKeepsSilentOnExistingApps() async {
        _ = try? moveIntoTrash(name: "Already", bundleID: "com.example.Already")
        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()

        XCTAssertEqual(watcher.status, .watching)
        // 首帧只建基线，这一步"没有事件"是真的没有事件，不是读不到。
        await waitUntil({ watcher.arrivals.isEmpty == false }, timeout: .milliseconds(800))
        XCTAssertTrue(watcher.arrivals.isEmpty)
    }

    /// 离页再回页（同一个 watcher 实例 stop → start）时，上一轮的提示不能靠"等下一个事件"
    /// 才失效：用户可能已经把那个 app 还原、或者连废纸篓一起清空了。
    func testRestartPrunesArrivalsThatAreNoLongerInTrash() async throws {
        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()

        let destination = try moveIntoTrash(name: "Stale", bundleID: "com.example.Stale")
        await waitUntil({ watcher.arrivals.count == 1 })
        XCTAssertEqual(watcher.arrivals.first?.entry, "Stale.app")

        watcher.stop()
        try FileManager.default.removeItem(atPath: destination)

        watcher.start()
        XCTAssertTrue(watcher.arrivals.isEmpty, "重新监听后，已经不在了的那条提示必须当场消失")
        XCTAssertEqual(watcher.status, .watching)
    }

    func testNewAppBecomesArrivalAndRestoringItClearsTheNotice() async {
        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()
        XCTAssertTrue(watcher.arrivals.isEmpty)

        _ = try? moveIntoTrash(name: "Fresh", bundleID: "com.example.Fresh")
        watcher.handleEvents(.write)
        await waitUntil({ watcher.arrivals.count == 1 })
        XCTAssertEqual(watcher.arrivals.map(\.name), ["Fresh"])
        XCTAssertEqual(watcher.arrivals.first?.bundleID, "com.example.Fresh")

        // 用户把它从废纸篓还原：提示必须跟着消失，否则等于给一个活应用提供删残留入口。
        try? FileManager.default.removeItem(atPath: "\(trashPath)/Fresh.app")
        watcher.handleEvents(.write)
        await waitUntil({ watcher.arrivals.isEmpty })
        XCTAssertTrue(watcher.arrivals.isEmpty)
    }

    /// 显示名取本地化过的 `CFBundleDisplayName`，不是磁盘上的目录名。
    func testArrivalUsesDisplayName() async throws {
        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()

        _ = try? moveIntoTrash(name: "Fresh", bundleID: "com.example.Fresh")
        try fixture.writePlist("\(trashPath)/Fresh.app/Contents/Info.plist", [
            "CFBundleIdentifier": "com.example.Fresh",
            "CFBundleDisplayName": "Fresh 中文名",
        ])
        watcher.handleEvents(.write)
        await waitUntil({ watcher.arrivals.isEmpty == false })
        XCTAssertEqual(watcher.arrivals.first?.name, "Fresh 中文名")
    }

    /// 没有 Info.plist 的 `Foo.app`（访达替身、损坏 bundle）不报，
    /// 系统自带包名也不报。
    func testUnreadableAndSystemOwnedEntriesAreNotReported() async throws {
        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()

        try FileManager.default.createDirectory(atPath: "\(trashPath)/Alias.app/Contents",
                                                withIntermediateDirectories: true)
        _ = try? moveIntoTrash(name: "Safari", bundleID: "com.apple.Safari")
        try fixture.writeFile("\(trashPath)/readme.txt")
        watcher.handleEvents(.write)
        await waitUntil({ watcher.arrivals.isEmpty == false }, timeout: .milliseconds(800))
        XCTAssertTrue(watcher.arrivals.isEmpty)
    }

    /// 目录读不动要说成"读不到"，不能冒充"废纸篓是空的"。
    func testUnreadableDirectoryReportsReasonAndNeedsPermission() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: trashPath)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: trashPath)
        }

        let watcher = watcher()
        watcher.start()
        defer { watcher.stop() }

        guard case .unreadable(let reason, let needsFullDiskAccess) = watcher.status else {
            return XCTFail("权限被拒时必须是 unreadable，实际是 \(watcher.status)")
        }
        XCTAssertTrue(needsFullDiskAccess, "EACCES 属于权限被拒")
        XCTAssertTrue(reason.contains("废纸篓"), reason)
        XCTAssertTrue(reason.contains("not permitted") || reason.contains("denied") || reason.contains("错误码"),
                      "要把真实错误码带出来：\(reason)")
    }

    /// 目录还不存在（全新用户没删过东西）不是权限问题，不能给授权按钮。
    func testMissingDirectoryIsNotReportedAsPermissionProblem() {
        let watcher = TrashWatcher(trashDirectory: "\(trashPath)/does-not-exist")
        watcher.start()
        defer { watcher.stop() }
        guard case .unreadable(let reason, let needsFullDiskAccess) = watcher.status else {
            return XCTFail("目录不存在时必须是 unreadable，实际是 \(watcher.status)")
        }
        XCTAssertFalse(needsFullDiskAccess)
        XCTAssertTrue(reason.contains("不存在"), reason)
    }

    /// 事件合并：连着两次改动只报一次同一个应用。
    func testCoalescedEventsReportOneArrival() async {
        let watcher = watcher()
        defer { watcher.stop() }
        watcher.start()

        _ = try? moveIntoTrash(name: "Burst", bundleID: "com.example.Burst")
        watcher.handleEvents(.write)
        watcher.handleEvents(.write)
        watcher.handleEvents(.write)
        await waitUntil({ watcher.arrivals.isEmpty == false })
        // 再多等一会儿，确认第二次列举没有把它当成"新出现"重复追加。
        try? await Task.sleep(for: TrashWatcher.coalescingInterval)
        watcher.handleEvents(.write)
        try? await Task.sleep(for: TrashWatcher.coalescingInterval)
        XCTAssertEqual(watcher.arrivals.count, 1)
    }
}

// MARK: - 提示卡到删除列表的链路

@MainActor
final class TrashResidualNoticeFlowTests: XCTestCase {
    private var fixture: ResidualFixture!
    private var trashPath: String = ""

    override func setUpWithError() throws {
        fixture = try ResidualFixture(caseName: name)
        let trash = fixture.root.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        trashPath = trash.path
    }

    override func tearDownWithError() throws {
        fixture?.cleanup()
        fixture = nil
    }

    /// 这条链路最重要的不变量：本体已经在废纸篓里，删除列表绝不能再包含它。
    /// `UninstallSelection.deletionPaths` 会主动把 app 本体拼进去，所以这里用
    /// `report.deletionRoots` —— 这个测试就是钉住这个区别的。
    func testDeletionRootsNeverContainTheTrashedBundle() async throws {
        let appPath = try fixture.makeApp(name: "Foo", bundleID: "com.example.Foo")
        try FileManager.default.moveItem(atPath: appPath, toPath: "\(trashPath)/Foo.app")
        let bundleInTrash = "\(trashPath)/Foo.app"
        _ = try fixture.folderWithFile(try fixture.libraryFolder("Caches/com.example.Foo"))
        try fixture.writePlist(try fixture.libraryFolder("Preferences") + "/com.example.Foo.plist", ["a": "b"])

        guard let arrival = TrashArrival(trashDirectory: trashPath, entry: "Foo.app") else {
            return XCTFail("夹具里的 bundle 应当能解析出包名")
        }
        XCTAssertEqual(arrival.path, bundleInTrash)

        let model = UninstallerModel()
        model.selectTrashArrival(arrival)
        await model.scanTrashResiduals(home: fixture.homePath)

        XCTAssertTrue(model.hasScannedTrashResiduals)
        XCTAssertFalse(model.trashResidualItems.isEmpty, "夹具造了缓存与偏好，不该零命中")
        XCTAssertTrue(model.selectedTrashResidualIDs.isSuperset(of:
            UninstallSelection.defaultSelectedIDs(model.trashResidualItems)))

        let roots = model.trashResidualReport?.deletionRoots(for: model.selectedTrashResidualIDs) ?? []
        XCTAssertTrue(roots.isEmpty == false)
        XCTAssertTrue(roots.contains(bundleInTrash) == false, "删除列表里不能出现已在废纸篓的本体")
        XCTAssertTrue(roots.allSatisfy { $0.hasPrefix(fixture.homePath) },
                      "残留只能来自注入的那个假 home：\(roots)")

        // 换目标 = 旧勾选作废，不能把上一个应用的勾选结果贴到新目标上。
        model.selectTrashArrival(nil)
        XCTAssertTrue(model.selectedTrashResidualIDs.isEmpty)
        XCTAssertNil(model.trashResidualReport)
        XCTAssertFalse(model.hasScannedTrashResiduals)
    }

    /// 没扫过的时候合计必须是"尚未扫描"的语义，不能是 0 项冒充干净。
    func testUnscannedStateKeepsCountsHonest() throws {
        let appPath = try fixture.makeApp(name: "Bar", bundleID: "com.example.Bar")
        guard let arrival = TrashArrival(trashDirectory: URL(fileURLWithPath: appPath).deletingLastPathComponent().path,
                                        entry: "Bar.app") else {
            return XCTFail("夹具里的 bundle 应当能解析出包名")
        }
        let model = UninstallerModel()
        model.selectTrashArrival(arrival)
        XCTAssertEqual(model.trashResidualItems, [])
        XCTAssertEqual(model.selectedTrashResidualCount, 0)
        XCTAssertFalse(model.hasScannedTrashResiduals, "还没扫过，界面就不能说「没有残留」")
    }
}
