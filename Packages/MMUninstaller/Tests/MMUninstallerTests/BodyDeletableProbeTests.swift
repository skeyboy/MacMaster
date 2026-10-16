import XCTest
import Foundation
import Darwin
@testable import MMUninstaller

/// P52b 的前置量（`docs/analysis/uninstaller-app-body-risk.md` §4 建议 1 那条「待量的前置」、§6 第四条）。
///
/// `ResidualCollector.isDeletableByCurrentUser` 的注释理由是「移到废纸篓要的是父目录的写权限」。
/// 这一条对**文件**够用早就成立，对**目录型 bundle**（本体就是一个目录）够不够，本轮量出来钉在这里。
///
/// 读数口径要说清：这一跑测的是**机制**，夹具在 `NSTemporaryDirectory()` 下，
/// 所以 `access(W_OK)` 说的是真的。真机 `/Applications`、`/System/Applications` 那一档不在这里，
/// 代理受限 shell 只能写工作区与 /tmp，它读出来的 `W_OK` 不是 MacMaster 运行时的判据（§6 第二条）。
final class BodyDeletableProbeTests: XCTestCase {

    private func setImmutable(_ path: String, _ on: Bool) throws {
        // Foundation 的 `FileAttributeKey` 没有 flags 这一档，只能走 `chflags`。
        XCTAssertEqual(chflags(path, on ? UInt32(UF_IMMUTABLE) : 0), 0, "chflags(\(path)) 失败")
    }

    /// 本体（目录型 bundle）在父目录可写时判为可删 —— 哪怕 bundle 内部的 `Contents` 是只读的：
    /// `trashItem` 移的是顶层那一项，走的是 rename，子树权限不参与。
    func testWritableParentMakesTheBundleDeletableEvenIfItsInteriorIsLocked() throws {
        let fixture = try ResidualFixture(caseName: "bodyDeletable")
        defer { fixture.cleanup() }
        let app = try fixture.makeApp(name: "Foo", bundleID: "com.example.Foo")
        try fixture.makeReadOnly(app + "/Contents")

        XCTAssertTrue(ResidualCollector.isDeletableByCurrentUser(app), "父目录可写，本体该判可删")
        XCTAssertFalse(ResidualCollector.isDeletableByCurrentUser(app + "/Contents/Info.plist"),
                       "同一把尺量 bundle 内部的项：它的父目录刚被锁成只读")
    }

    /// 父目录不可写 = 本体删不掉，这一条对目录与文件同形（`/System/Applications` 那种只读卷就是这个形状）。
    func testLockedParentDowngradesBothBundlesAndFilesTheSameWay() throws {
        let fixture = try ResidualFixture(caseName: "bodyDeletable")
        defer { fixture.cleanup() }
        let app = try fixture.makeApp(name: "Foo", bundleID: "com.example.Foo")
        let file = try fixture.libraryFolder("Caches") + "/com.example.Foo.plist"
        try fixture.writeFile(file)
        let appParent = (app as NSString).deletingLastPathComponent
        try fixture.makeReadOnly(appParent)
        try fixture.makeReadOnly((file as NSString).deletingLastPathComponent)

        XCTAssertFalse(ResidualCollector.isDeletableByCurrentUser(app))
        XCTAssertFalse(ResidualCollector.isDeletableByCurrentUser(file))
    }

    /// `UF_IMMUTABLE` 挂在 bundle 目录本身上时也要判不可删：
    /// 这就是那句注释里"uchg 会让 trashItem 直接失败"在目录形态上的同一件事。
    func testImmutableFlagOnTheBundleItselfBlocksDeletion() throws {
        let fixture = try ResidualFixture(caseName: "bodyDeletable")
        defer {
            // 不清掉 uchg 就删不掉整棵夹具，cleanup 会留下临时目录。
            try? setImmutable(fixture.homePath + "/Applications/Bar.app", false)
            fixture.cleanup()
        }
        let app = try fixture.makeApp(name: "Bar", bundleID: "com.example.Bar")

        XCTAssertTrue(ResidualCollector.isDeletableByCurrentUser(app))
        try setImmutable(app, true)
        XCTAssertFalse(ResidualCollector.isDeletableByCurrentUser(app), "uchg 挂在本体目录上时该判只读")
        try setImmutable(app, false)
        XCTAssertTrue(ResidualCollector.isDeletableByCurrentUser(app), "清掉标志要能回到可删，否则上一条断言测的是残留状态")
    }

    /// 本体路径的父目录是应用目录本身；`deletingLastPathComponent` 走到根时不该误判成可删。
    func testPathWithoutAParentIsNotDeletable() {
        XCTAssertFalse(ResidualCollector.isDeletableByCurrentUser("/"))
    }
}
