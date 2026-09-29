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

    func testHomeIsBlockedEvenWhenScanningFromRoot() {
        let home = "/Users/lee"
        let plan = DiskRemoval.plan(marks: [mark(home)], root: "/", home: home)
        XCTAssertEqual(plan.blocked.map(\.reason), [.isHome])
    }

    func testSystemTreeIsBlockedButUserLibraryIsNot() {
        let system = DiskRemoval.plan(marks: [mark("/System/Library/CoreServices")], root: "/")
        XCTAssertEqual(system.blocked.map(\.reason), [.systemTree])
        // 用户资源库里的第三方缓存是该清理的地方，不能被系统树规则一起打死。
        let userLibrary = DiskRemoval.plan(marks: [mark("/Users/lee/Library/Caches")], root: "/Users/lee")
        XCTAssertEqual(userLibrary.targets.map(\.path), ["/Users/lee/Library/Caches"])
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
