import Foundation
import MMCore
import XCTest
@testable import MMUninstaller

/// 求和口径：默认可选总大小绝不能重复计数。
/// 两条保证 —— 同一绝对路径只算一次（即使被两个类别各命中一次），
/// 父目录与它自己的子项同时入选时也只算父目录。
final class ResidualSelectionTests: XCTestCase {
    private var fixture: ResidualFixture!

    override func setUpWithError() throws {
        fixture = try ResidualFixture(caseName: name)
    }

    override func tearDownWithError() throws {
        fixture?.cleanup()
        fixture = nil
    }

    private func item(_ id: String, path: String? = nil, category: ResidualCategory,
                      risk: MMRisk, size: UInt64) -> ResidualItem {
        let stored = path ?? id
        return ResidualItem(id: id, path: stored, displayPath: stored,
                            name: (stored as NSString).lastPathComponent,
                            category: category, risk: risk, reason: "测试注入", size: size)
    }

    // MARK: 同一绝对路径 × 两个类别

    /// 同一路径以两个类别各命中一次时，总大小与删除根都只有一份。
    func testSamePathInTwoCategoriesIsCountedOnce() {
        let items = [item("/tmp/x/com.example.MyApp", category: .cache, risk: .safe, size: 10),
                     item("/tmp/x/com.example.MyApp", category: .httpStorage, risk: .safe, size: 10)]
        let report = ResidualScanReport(items: items, inaccessiblePaths: [])

        XCTAssertEqual(report.defaultSelectableSize, 10, "同一绝对路径不能被两个类别各算一次")
        XCTAssertEqual(report.defaultSelectableCount, 1)
        XCTAssertEqual(report.defaultDeletionRoots, ["/tmp/x/com.example.MyApp"])

        let selected = UninstallSelection.selectedSize(items: items,
                                                       selectedIDs: Set(items.map(\.id)))
        XCTAssertEqual(selected, 10)
        XCTAssertEqual(UninstallSelection.deletionPaths(appPath: "/tmp/App.app", items: items,
                                                        selectedIDs: Set(items.map(\.id))).count, 2,
                       "删除根 = app 本体 + 一个残留")
    }

    /// 真实扫描里同样只能有一条：Caches 与 HTTPStorages 都是 strict 清单条目，
    /// 用符号链接把两者指向同一份磁盘内容，主键（规范路径）必须把它们塌成一项。
    func testScannerDeduplicatesSymlinkedSameInode() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let real = try fixture.folderWithFile(try fixture.libraryFolder("HTTPStorages") + "/com.example.MyApp")
        let caches = try fixture.libraryFolder("Caches")
        let link = caches + "/com.example.MyApp"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        let hit = report.items.filter { $0.name == "com.example.MyApp"
            && ($0.category == .cache || $0.category == .httpStorage) }
        XCTAssertEqual(Set(hit.map(\.id)).count, 1, "符号链接与真实路径是同一个绝对路径")
        XCTAssertEqual(hit.count, 1, "同一绝对路径不能以两个类别各算一次：\(hit.map { "\($0.category):\($0.path)" })")
        XCTAssertEqual(report.defaultSelectableSize, 10, "每项固定 10 字节，只该算一份")
    }

    // MARK: 父子嵌套

    /// 父目录已入选时，其子项不再重复累加字节数。
    func testNestedSelectionCountsParentOnly() {
        let parent = item("/tmp/Data", category: .applicationSupport, risk: .caution, size: 100)
        let child = item("/tmp/Data/Library/Caches", category: .containerCache, risk: .safe, size: 30)
        let both = Set([parent.id, child.id])

        XCTAssertEqual(UninstallSelection.selectedSize(items: [parent, child], selectedIDs: both), 100,
                       "父目录大小本身含子项，累加会虚报")
        XCTAssertEqual(UninstallSelection.deletionPaths(appPath: "/tmp/App.app", items: [parent, child],
                                                        selectedIDs: both),
                       ["/tmp/App.app", "/tmp/Data"], "删除根只保留最浅一层")
    }

    /// 真实容器场景：整容器谨慎（默认不勾选）+ 容器内缓存安全 → 默认可选总大小只有缓存。
    func testDefaultSizeExcludesWholeContainer() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let container = try fixture.makeContainer(dirName: "BOX42", identifier: "com.example.MyApp")
        let innerCache = container + "/Data/Library/Caches"
        let userCache = try fixture.folderWithFile(try fixture.libraryFolder("Caches") + "/com.example.MyApp")

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        XCTAssertEqual(report.items.first { $0.path == container }?.risk, .caution)
        XCTAssertEqual(report.items.first { $0.path == innerCache }?.risk, .safe)

        XCTAssertEqual(report.defaultSelectableSize, 20, "两份缓存各 10 字节，整容器不计入")
        XCTAssertEqual(Set(report.defaultDeletionRoots).sorted(),
                       [innerCache, userCache].sorted(),
                       "默认删除根必须是缓存而不是容器")
        XCTAssertEqual(report.defaultSelectableCount, 2)
    }

    // MARK: 风险档与勾选

    /// 默认勾选只来自 safe；只读项既不默认勾选也不可选。
    func testDefaultSelectionComesOnlyFromSafe() {
        let items = [item("/tmp/a", category: .cache, risk: .safe, size: 1),
                     item("/tmp/b", category: .preference, risk: .caution, size: 1),
                     item("/tmp/c", category: .launchService, risk: .readOnly, size: 1)]
        XCTAssertEqual(UninstallSelection.defaultSelectedIDs(items), ["/tmp/a"])
        XCTAssertEqual(UninstallSelection.selectableIDs(items), ["/tmp/a", "/tmp/b"])
        XCTAssertEqual(UninstallSelection.unselectedDeletableCount(items, selectedIDs: ["/tmp/a"]), 1)

        let paths = UninstallSelection.deletionPaths(appPath: "/tmp/App.app", items: items,
                                                     selectedIDs: ["/tmp/a", "/tmp/c"])
        XCTAssertEqual(paths, ["/tmp/App.app", "/tmp/a"], "只读项即使在状态里被勾选也不能进删除列表")
    }

    /// 未勾选时删除列表只有 app 本体。
    func testDeletionPathsWithoutSelection() {
        let items = [item("/tmp/a", category: .cache, risk: .safe, size: 1)]
        XCTAssertEqual(UninstallSelection.deletionPaths(appPath: "/tmp/App.app", items: items, selectedIDs: []),
                       ["/tmp/App.app"])
        XCTAssertEqual(UninstallSelection.selectedSize(items: items, selectedIDs: []), 0)
    }

    func testOnlySuccessfullyMovedRootsClearResidualRows() {
        let moved = Set(["/tmp/app/Container"])
        XCTAssertTrue(UninstallSelection.wasMoved("/tmp/app/Container/Data/Caches", under: moved))
        XCTAssertTrue(UninstallSelection.wasMoved("/tmp/app/Container", under: moved))
        XCTAssertFalse(UninstallSelection.wasMoved("/tmp/app/Container2", under: moved))
        XCTAssertFalse(UninstallSelection.wasMoved("/tmp/app/Failed", under: moved))
    }

    /// 去重主键必须对"存在"和"已不存在"两种路径给出同一个写法。
    /// `URL.resolvingSymlinksInPath()` 只在目标存在时把 `/private/var` 折成 `/var`，
    /// 于是残留引擎最核心的一个场景（app 已删、启动项还指着它的可执行文件）会静默失配。
    func testPhysicalPathIsStableForMissingLeaf() throws {
        let fixture = try ResidualFixture(caseName: "physicalPath")
        defer { fixture.cleanup() }
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let missingExecutable = "\(app)/Contents/Resources/NotThere"

        let resolvedApp = ResidualCollector.physicalPath(app)
        let resolvedMissing = ResidualCollector.physicalPath(missingExecutable)
        XCTAssertTrue(resolvedMissing.hasPrefix(resolvedApp + "/"),
                      "同一个 app 与其内部尚未存在的路径必须同一口径：\(resolvedApp) vs \(resolvedMissing)")
        // 已存在的路径要拿到物理写法，夹具与扫描器的字符串比较才对得上。
        XCTAssertEqual(resolvedApp, app, "夹具用物理路径建立，physicalPath 不应再改变它")
    }

    /// 祖先一个都解析不出来的路径（相对写法、空串）必须走词法回退，不能把进程 trap 掉。
    /// 这条不是理论：上一版按"components[0] 一定是前导空段"切分，
    /// 相对路径整体错位一格，`a/b/c` 变成了 `//b/c`，而空区间下标会直接崩掉 App。
    func testPhysicalPathHandlesRelativeAndDegenerateInput() {
        XCTAssertEqual(ResidualCollector.physicalPath(""), "")
        XCTAssertEqual(ResidualCollector.physicalPath("/"), "/")
        for relative in ["nowhere", "a/b/c"] {
            let resolved = ResidualCollector.physicalPath(relative)
            XCTAssertTrue(resolved.hasPrefix("/"), "\(relative) 应补成绝对路径：\(resolved)")
            XCTAssertTrue(resolved.hasSuffix("/" + relative),
                          "\(relative) 的尾段必须原样保留，实际：\(resolved)")
        }
    }

    /// `/var` 与 `/private/var` 是同一个目录的两种写法，两者必须收敛到同一个物理路径；
    /// 目标不存在时也要跟着它已存在的祖先走，否则前缀比较静默失配。
    func testPhysicalPathConvergesBothSpellingsOfVar() {
        XCTAssertEqual(ResidualCollector.physicalPath("/var"), ResidualCollector.physicalPath("/private/var"))
        XCTAssertTrue(ResidualCollector.physicalPath("/var/nowhere/deep")
                          .hasPrefix(ResidualCollector.physicalPath("/var") + "/"),
                      "不存在的尾段要接在已解析的祖先之后")
    }
}
