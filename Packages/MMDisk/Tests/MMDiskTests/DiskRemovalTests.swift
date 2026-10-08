import XCTest
import Foundation
@testable import MMDisk

/// 删除前的统一裁决。这里守的是"程序会不会自己删掉不该删的东西"，
/// 所以每条规则都要能被单独钉住，而不是等真删错了再回头找。
final class DiskRemovalTests: XCTestCase {
    private var root: String!
    private var fileManager: FileManager { .default }

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("MacMasterRemovalTests-\(UUID().uuidString)", isDirectory: true).path
        try fileManager.createDirectory(atPath: root!, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? fileManager.removeItem(atPath: root) }
    }

    private func mark(_ path: String, name: String = "x", size: UInt64 = 100) -> DiskRemoval.Mark {
        DiskRemoval.Mark(path: path, name: name, size: size)
    }

    func testEmptyMarksProduceEmptyPlan() {
        let plan = DiskRemoval.plan(marks: [], root: root!)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.total, 0)
    }

    func testTargetInsideScanRootIsAccepted() {
        let path = root! + "/build"
        try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        let plan = DiskRemoval.plan(marks: [mark(path, size: 500)], root: root!)
        XCTAssertEqual(plan.targets.map(\.path), [path])
        XCTAssertEqual(plan.total, 500)
        XCTAssertTrue(plan.blocked.isEmpty)
    }

    func testPathsOutsideScanRootAreBlocked() {
        let plan = DiskRemoval.plan(marks: [mark("/Users/someone/else/Documents")], root: root!)
        XCTAssertEqual(plan.blocked.map(\.reason), [.outsideRoot])
        XCTAssertTrue(plan.targets.isEmpty)
    }

    /// 字符串前缀不等于父目录：`/tmp/lee` 是 `/tmp/leestat` 的前缀，
    /// 但它俩是隔壁两间屋子。
    func testSiblingWithSharedPrefixIsNotInsideRoot() {
        let plan = DiskRemoval.plan(marks: [mark(root! + "stat/notes")], root: root!)
        XCTAssertEqual(plan.blocked.map(\.reason), [.outsideRoot])
    }

    func testScanRootItselfIsBlocked() {
        let plan = DiskRemoval.plan(marks: [mark(root!, name: "本次扫描的目录")], root: root!)
        XCTAssertEqual(plan.blocked.map(\.reason), [.isScanRoot])
    }

    /// 这一条不需要真有一个主目录：`.isHome` 是纯字符串比对，发生在"还在不在磁盘上"之前。
    /// 所以主目录用编出来的名字，测试在任何机器、任何用户下都同样成立。
    func testHomeIsBlockedEvenWhenScanningFromRoot() {
        let home = "/Users/probe"
        let plan = DiskRemoval.plan(marks: [mark(home)], root: "/", home: home)
        XCTAssertEqual(plan.blocked.map(\.reason), [.isHome])
    }

    /// 系统树那条规则只看**从卷根往下数的第一层**：`/Library/Caches` 是系统的，
    /// `~/Library/Caches` 是第三方缓存、正是该清理的地方，两者字面都像 "Library/Caches"。
    ///
    /// 这一条原来写死 `/Users/lee/Library/Caches` 并断言它进 `targets`：换一台机器
    /// （CI 上是 `/Users/runner`）那条路不存在，`plan` 落到 `.vanished` 分支，测试当场红——
    /// 也就是说它测的是"作者这台机装过什么"，不是规则本身（P28 在 macos-latest 上现读到）。
    /// 现在改成用每台 mac 都有的 `NSHomeDirectory()`，并且只咬住"系统树这一条没打死它"：
    /// 再往后的判据（闸口、卷根、已消失）各有各的测试，不在这里顺带验。
    func testSystemTreeIsBlockedButUserLibraryIsNot() {
        let system = DiskRemoval.plan(marks: [mark("/System/Library/CoreServices")], root: "/")
        XCTAssertEqual(system.blocked.map(\.reason), [.systemTree])

        let rootLibrary = DiskRemoval.plan(marks: [mark("/Library/Caches")], root: "/")
        XCTAssertEqual(rootLibrary.blocked.map(\.reason), [.systemTree],
                       "卷根第一层的 Library 要算系统树，否则清理页一刀就挥到系统缓存上")

        let userLibrary = DiskRemoval.plan(marks: [mark(NSHomeDirectory() + "/Library/Caches")],
                                           root: NSHomeDirectory())
        XCTAssertFalse(userLibrary.blocked.contains { $0.reason == .systemTree },
                       "用户资源库不能被系统树规则一起打死：\(userLibrary.blocked.map(\.reason))")
    }

    /// 执行那一层的闸口（`DeletionGuard`）本来就会拒绝的路径，不能列进"要删的清单"。
    /// 废纸篓和永久删除共用这一份裁决：写在面板上的清单必须和真会发生的事一致，
    /// 否则用户看到"3 项待删"、按下只成 2 项，还多一条事后才冒出来的失败。
    /// 探针路径本机不存在：闸门万一失效，被动的也是我编出来的名字。
    func testGuardedPathIsBlockedUpFrontWithItsReason() {
        let probe = NSHomeDirectory() + "/Library/Keychains/探针-\(UUID().uuidString).keychain-db"
        let plan = DiskRemoval.plan(marks: [mark(probe, size: 300)], root: "/")
        XCTAssertTrue(plan.targets.isEmpty)
        let blocked = plan.blocked.first
        XCTAssertEqual(blocked?.reason, .guarded)
        XCTAssertFalse(blocked?.detail.isEmpty ?? true,
                       "闸口给的整句原因要能显示出来，光一个标签说明不了为什么")
    }

    /// 顺序也要钉住：闸口排在"已消失"之前。探针同时满足两条时，面板该说的是
    /// "这条路本来就不给删"，而不是"它不在了"——后者会把用户支去重新扫描。
    func testGuardedIsReportedBeforeVanished() {
        let plan = DiskRemoval.plan(
            marks: [mark(NSHomeDirectory() + "/.gnupg/private-keys-v1.d/探针-\(UUID().uuidString).key")],
            root: "/"
        )
        XCTAssertEqual(plan.blocked.map(\.reason), [.guarded])
    }

    func testMarkingAParentAbsorbsItsChild() {
        let parent = root! + "/Projects"
        let child = parent + "/node_modules"
        try? fileManager.createDirectory(atPath: child, withIntermediateDirectories: true)
        let plan = DiskRemoval.plan(marks: [
            mark(parent, size: 900),
            mark(child, size: 400),
        ], root: root!)
        XCTAssertEqual(plan.targets.map(\.path), [parent])
        // 子项的 400 已经算在父项的 900 里，再相加就是凭空多出来的空间。
        XCTAssertEqual(plan.total, 900)
        XCTAssertEqual(plan.absorbed, 1)
    }

    func testOnlySuccessfulMovedRootsClearMarks() {
        let moved = Set([root! + "/Projects"])
        XCTAssertTrue(DiskRemoval.wasMoved(root! + "/Projects", under: moved))
        XCTAssertTrue(DiskRemoval.wasMoved(root! + "/Projects/build", under: moved))
        XCTAssertFalse(DiskRemoval.wasMoved(root! + "/Projects-old", under: moved))
        XCTAssertFalse(DiskRemoval.wasMoved(root! + "/Failed", under: moved))
    }

    func testUnrelatedMarksAreNotAbsorbed() {
        let a = root! + "/a"
        let b = root! + "/b"
        try? fileManager.createDirectory(atPath: a, withIntermediateDirectories: true)
        try? fileManager.createDirectory(atPath: b, withIntermediateDirectories: true)
        let plan = DiskRemoval.plan(marks: [mark(a, size: 10), mark(b, size: 20)], root: root!)
        XCTAssertEqual(plan.total, 30)
        XCTAssertEqual(plan.absorbed, 0)
    }

    func testPathsThatVanishedAfterScanningAreBlocked() {
        let plan = DiskRemoval.plan(marks: [mark(root! + "/gone-today")], root: root!)
        XCTAssertEqual(plan.blocked.map(\.reason), [.vanished])
        XCTAssertTrue(plan.targets.isEmpty)
    }

    func testBlockedMarksNeverInflateTheTotal() {
        let real = root! + "/real"
        try? fileManager.createDirectory(atPath: real, withIntermediateDirectories: true)
        let plan = DiskRemoval.plan(marks: [
            mark(real, size: 700),
            mark("/System/Library/Firmware", size: 9_000),
            mark(root! + "/vanished", size: 5_000),
        ], root: root!)
        XCTAssertEqual(plan.targets.count, 1)
        XCTAssertEqual(plan.total, 700)
        XCTAssertEqual(plan.blocked.count, 2)
    }

    func testAfterRemovingAddsFreedBytes() {
        XCTAssertEqual(
            DiskRemoval.afterRemoving(free: 10, capacity: 100, bytes: 5), 15
        )
    }

    /// 投影数字不许超过卷容量：可用 60 / 总 50 这种数一出现，整块面板就没人信了。
    func testAfterRemovingSaturatesAtCapacity() {
        XCTAssertEqual(
            DiskRemoval.afterRemoving(free: 40, capacity: 50, bytes: 100), 50
        )
    }

    func testAfterRemovingSurvivesByteOverflow() {
        let huge = UInt64.max - 10
        let projected = DiskRemoval.afterRemoving(free: 100, capacity: 500, bytes: huge)
        XCTAssertEqual(projected, 500)
    }

    /// 挂载点整块不能删。没有第二块卷可测时如实跳过，不拿假路径糊弄过去。
    func testMountedVolumeRootIsBlocked() throws {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []
        let extra = volumes.map(\.path).first { $0 != "/" && !$0.isEmpty }
        try XCTSkipIf(extra == nil, "本机没有第二块挂载卷")
        let plan = DiskRemoval.plan(marks: [mark(extra!, name: "外接卷")], root: "/")
        XCTAssertEqual(plan.blocked.map(\.reason), [.isVolumeRoot])
    }
}
