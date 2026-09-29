import XCTest
import Foundation
import MMUI
@testable import MMDisk

/// 全树名称过滤（disktree #7 口径）的回归测试。
/// 全部用内存里手搭的树 + 临时目录夹具，绝不碰真实用户文件。
final class DiskTreeFilterTests: XCTestCase {

    private func file(_ name: String, _ size: UInt64, at path: String? = nil) -> DiskTreeNode {
        let p = path ?? "/root/\(name)"
        return DiskTreeNode(id: p, name: name, path: p, size: size, isDirectory: false, children: [])
    }

    private func dir(_ name: String, _ size: UInt64, children: [DiskTreeNode],
                     measured: Bool = true, at path: String? = nil) -> DiskTreeNode {
        let p = path ?? "/root/\(name)"
        return DiskTreeNode(id: p, name: name, path: p, size: size, isDirectory: true,
                            children: children, descendantsMeasured: measured)
    }

    /// 与 DiskAnalyzerView.treemapItem(for filtered:depth:) 保持一致的映射。
    private func mapHit(_ hit: DiskTreeFilter.Node) -> TreemapItem {
        let kids = (hit.children ?? []).map { mapHit($0) }
        return TreemapItem(id: hit.node.id, name: hit.node.name,
                           value: Double(hit.matchedBytes), children: kids,
                           isDirectory: hit.node.isDirectory,
                           matchTier: hit.tier == .matched ? .matched : .containsMatch)
    }

    // MARK: - 后代命中：祖先以命中体积出现

    func testDescendantHitSurfacesAncestorWithMatchedBytes() {
        let logs = dir("Library", 1_000, children: [
            file("app.log", 600), file("app.bin", 400),
        ])
        let result = try! XCTUnwrap(DiskTreeFilter.apply([logs], filter: "app.log"))

        let ancestor = try! XCTUnwrap(result.nodes.first)
        XCTAssertEqual(ancestor.tier, .containsMatch)
        // 命中体积 = 600，不是目录自身的 1000——面积按命中重排的关键
        XCTAssertEqual(ancestor.matchedBytes, 600)
        XCTAssertLessThan(ancestor.matchedBytes, ancestor.node.size)
        XCTAssertEqual(ancestor.children?.count, 1)
        XCTAssertEqual(ancestor.children?.first?.tier, .matched)
        XCTAssertEqual(result.matchedBytesTotal, 600)
    }

    func testLayoutReordersByMatchedBytesNotRawSize() {
        // bigRaw 只命中一小口；smallRaw 几乎全是命中。原始布局 big 在前，
        // 过滤布局必须按命中体积反过来。
        let bigRaw = dir("big", 9_000, children: [file("needlex", 100), file("rest", 8_900)])
        let smallRaw = dir("small", 1_000, children: [file("needleY", 900)])
        let rect = CGRect(x: 0, y: 0, width: 800, height: 400)

        let raw = TreemapLayout.compute(items: [bigRaw, smallRaw].map {
            TreemapItem(id: $0.id, name: $0.name, value: Double($0.size), isDirectory: true)
        }, in: rect, options: TreemapLayoutOptions())
        let bigRawTile = try! XCTUnwrap(raw.first { $0.item.id == bigRaw.id })
        let smallRawTile = try! XCTUnwrap(raw.first { $0.item.id == smallRaw.id })
        XCTAssertGreaterThan(bigRawTile.rect.width, smallRawTile.rect.width)

        let filtered = try! XCTUnwrap(DiskTreeFilter.apply([bigRaw, smallRaw], filter: "needle"))
        let laid = TreemapLayout.compute(items: filtered.nodes.map(mapHit), in: rect,
                                         options: TreemapLayoutOptions())
        let bigTile = try! XCTUnwrap(laid.first { $0.item.id == bigRaw.id })
        let smallTile = try! XCTUnwrap(laid.first { $0.item.id == smallRaw.id })
        // 100 对 900：命中体积口径下 small 必须反超大块头 big
        XCTAssertGreaterThan(smallTile.rect.width, bigTile.rect.width)
        XCTAssertEqual(bigTile.item.matchTier, .containsMatch)
        XCTAssertEqual(smallTile.item.matchTier, .containsMatch)
    }

    // MARK: - 无命中目录被排除

    func testNoMatchDirectoryIsExcludedFromResult() {
        let tree = [dir("alpha", 500, children: [file("a.txt", 500)]),
                    dir("beta", 300, children: [file("b.txt", 300)])]
        let result = try! XCTUnwrap(DiskTreeFilter.apply(tree, filter: "zzz"))
        XCTAssertTrue(result.nodes.isEmpty)
        // 全部量过了：没有命中就是没有命中，不该有"判不了"混进来
        XCTAssertEqual(result.indeterminateCount, 0)
        XCTAssertEqual(result.indeterminateBytes, 0)
    }

    func testSelfMatchedDirectoryCountsWholeSubtree() {
        let cache = dir("Caches", 500, children: [file("blob", 500)])
        let result = try! XCTUnwrap(DiskTreeFilter.apply([cache], filter: "caches"))
        let hit = try! XCTUnwrap(result.nodes.first)
        XCTAssertEqual(hit.tier, .matched)
        XCTAssertEqual(hit.matchedBytes, 500)
        // nil = 子树原样展示，不再按名字剪枝
        XCTAssertNil(hit.children)
    }

    func testMatchIsCaseInsensitive() {
        let tree = [file("README", 10)]
        let result = try! XCTUnwrap(DiskTreeFilter.apply(tree, filter: "readme"))
        XCTAssertEqual(result.nodes.count, 1)
    }

    // MARK: - 未测量 ≠ 零命中

    func testUnmeasuredSubtreeIsTalliedNotDropped() {
        // deep：深度兜底产生的目录，字节量到了但名字没枚举过
        let deep = dir("deep", 300, children: [], measured: false)
        let emptyMeasured = dir("empty", 0, children: [])
        let result = try! XCTUnwrap(DiskTreeFilter.apply([deep, emptyMeasured], filter: "needle"))

        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertEqual(result.indeterminateCount, 1, "只有没扫到底的那个目录算'判不了'")
        XCTAssertEqual(result.indeterminateBytes, 300)
    }

    func testUnmeasuredUnderHitAncestorStaysVisibleInTally() {
        // 父目录既有命中分支、又含一个没扫到底的孩子：
        // 布局按已知命中画，判不了的部分如实计数，两头都不撒谎。
        let parent = dir("mixed", 1_000, children: [
            file("needle.txt", 400), dir("truncated", 600, children: [], measured: false),
        ])
        let result = try! XCTUnwrap(DiskTreeFilter.apply([parent], filter: "needle"))
        let hit = try! XCTUnwrap(result.nodes.first)
        XCTAssertEqual(hit.tier, .containsMatch)
        XCTAssertEqual(hit.matchedBytes, 400)
        XCTAssertEqual(result.indeterminateCount, 1)
        XCTAssertEqual(result.indeterminateBytes, 600)
    }

    func testSelfMatchedUnmeasuredDirectoryCountsFullSize() {
        // 名字本身就命中：里面有什么已无关紧要，整个目录都是答案
        let deep = dir("needlebox", 700, children: [], measured: false)
        let result = try! XCTUnwrap(DiskTreeFilter.apply([deep], filter: "needle"))
        let hit = try! XCTUnwrap(result.nodes.first)
        XCTAssertEqual(hit.tier, .matched)
        XCTAssertEqual(hit.matchedBytes, 700)
        XCTAssertEqual(result.indeterminateCount, 0)
    }

    // MARK: - 清除过滤回到原始布局

    func testEmptyFilterReturnsNilSoLayoutIsUnchanged() {
        let tree = [dir("alpha", 500, children: [file("a.txt", 500)])]
        // nil = 视图直接走原始 currentItems 路径；过滤数据没有被缓存在任何地方，
        // "清掉过滤还留着痕迹"在结构上不成立。
        XCTAssertNil(DiskTreeFilter.apply(tree, filter: ""))
        // 纯函数：apply 不改动输入，原始映射随时可以原样重建
        let first = DiskTreeFilter.apply(tree, filter: "a.txt")
        XCTAssertEqual(first?.nodes.first?.matchedBytes, 500)
        XCTAssertEqual(tree.first?.size, 500)
        XCTAssertEqual(tree.first?.children.count, 1)
    }

    // MARK: - 扫描 → 过滤 → 布局 全链路（临时目录夹具）

    func testRealScanThroughFilterPipeline() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskTreeFilterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("b"),
                                                withIntermediateDirectories: true)
        let payload = Data(repeating: 0x41, count: 8_192)
        try payload.write(to: root.appendingPathComponent("a/needle.dat"))
        try payload.write(to: root.appendingPathComponent("b/junk.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        let output = await DiskScanner.performScan(rootPath: root.path)
        let aTop = try! XCTUnwrap(output.topItems.first { $0.name == "a" })
        let result = try! XCTUnwrap(DiskTreeFilter.apply(output.topItems, filter: "needle"))

        XCTAssertEqual(result.nodes.count, 1, "b 没有命中，必须整支排除")
        let hit = try! XCTUnwrap(result.nodes.first)
        XCTAssertEqual(hit.node.id, aTop.id)
        XCTAssertEqual(hit.tier, .containsMatch)
        // 命中体积 = needle.dat 的占用 = a 目录的全部占用；按命中重排后 ≤ 目录大小
        XCTAssertEqual(hit.matchedBytes, aTop.size)
        XCTAssertEqual(result.indeterminateCount, 0, "浅夹具全量扫过，不该有判不了")

        let laid = TreemapLayout.compute(items: result.nodes.map(mapHit),
                                         in: CGRect(x: 0, y: 0, width: 400, height: 200))
        XCTAssertFalse(laid.filter { $0.item.id == hit.node.id }.isEmpty)
    }
}
