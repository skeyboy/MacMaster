import XCTest
import Foundation
@testable import MMDisk

/// 标记跨重扫存续的全部裁决都在这两个纯函数里：谁活下来、谁的数字作废。
/// 活下来的必须带新体积（否则面板上两个数来自两个时间点），
/// 作废的必须点名（否则"已标记 N 项 · X"悄悄变小，没人看得出少了什么）。
final class DiskMarksTests: XCTestCase {

    private func node(_ path: String, size: UInt64, children: [DiskTreeNode] = []) -> DiskTreeNode {
        DiskTreeNode(id: path, name: (path as NSString).lastPathComponent, path: path,
                     size: size, isDirectory: true, children: children)
    }

    private func marked(_ path: String, size: UInt64) -> (String, DiskTreeNode) {
        (path, node(path, size: size))
    }

    private func previous(_ entries: [(String, DiskTreeNode)]) -> [String: DiskTreeNode] {
        Dictionary(uniqueKeysWithValues: entries)
    }

    // MARK: - 整根重扫

    func testReattachKeepsMarksAndReplacesTheirSizeWithTheNewScan() {
        let old = previous([marked("/u/dev/a", size: 100), marked("/u/dev/b", size: 200)])
        let fresh = [node("/u/dev/a", size: 40), node("/u/dev/b", size: 900)]

        let out = DiskMarks.reattach(old, rootPath: "/u/dev", into: fresh)

        XCTAssertEqual(out.dropped, [])
        XCTAssertEqual(out.marks.count, 2)
        // 路径活着 ≠ 数字还活着：两个都必须以新扫描那份为准
        XCTAssertEqual(out.marks["/u/dev/a"]?.size, 40)
        XCTAssertEqual(out.marks["/u/dev/b"]?.size, 900)
    }

    func testReattachFindsMarkedNodesDeeperThanTheTopLevel() {
        let tree = [node("/u/dev/a", size: 500, children: [
            node("/u/dev/a/sub", size: 500, children: [node("/u/dev/a/sub/deep", size: 480)])
        ])]
        let out = DiskMarks.reattach(previous([marked("/u/dev/a/sub/deep", size: 1)]),
                                     rootPath: "/u/dev", into: tree)

        XCTAssertEqual(out.dropped, [])
        XCTAssertEqual(out.marks["/u/dev/a/sub/deep"]?.size, 480)
    }

    func testReattachDropsMarksTheNewScanDoesNotContainAndNamesThem() {
        let old = previous([marked("/u/dev/gone", size: 100), marked("/u/dev/left", size: 200)])
        let out = DiskMarks.reattach(old, rootPath: "/u/dev", into: [node("/u/dev/left", size: 200)])

        XCTAssertEqual(out.dropped, ["/u/dev/gone"])
        XCTAssertEqual(Array(out.marks.keys), ["/u/dev/left"])
    }

    /// 扫描根不在它自己的 children 里，可它显然没消失——不能因为它就报"丢了一个标记"。
    func testReattachKeepsAMarkOnTheScannedRootItself() {
        let out = DiskMarks.reattach(previous([marked("/u/dev", size: 1_000)]),
                                     rootPath: "/u/dev",
                                     into: [node("/u/dev/a", size: 900)])
        XCTAssertEqual(out.dropped, [])
        XCTAssertEqual(out.marks["/u/dev"]?.size, 1_000)
    }

    /// 换了扫描根：旧根底下的标记在新树里当然找不到，丢弃而不是留一个过期数字。
    func testReattachDropsMarksOutsideTheNewRoot() {
        let old = previous([marked("/tmp/a/cache", size: 30), marked("/tmp/b/cache", size: 70)])
        let out = DiskMarks.reattach(old, rootPath: "/tmp/b", into: [node("/tmp/b/cache", size: 77)])

        XCTAssertEqual(out.dropped, ["/tmp/a/cache"])
        XCTAssertEqual(out.marks["/tmp/b/cache"]?.size, 77)
    }

    // MARK: - 单层重新枚举

    /// 「重新扫描」按钮只重扫当前这一层：这一层底下要判生死，
    /// 这一层没覆盖到的兄弟目录不能顺手丢掉。
    func testRefreshDropsOnlyWithinTheEnumeratedLevelAndKeepsSiblings() {
        let old = previous([
            marked("/u/dev/a/gone", size: 100),
            marked("/u/dev/a/keep", size: 200),
            marked("/u/dev/b/elsewhere", size: 300),
        ])
        let items = [node("/u/dev/a/keep", size: 260)]

        let out = DiskMarks.refresh(old, with: items, under: "/u/dev/a")

        XCTAssertEqual(out.dropped, ["/u/dev/a/gone"])
        XCTAssertEqual(out.marks["/u/dev/a/keep"]?.size, 260)
        // scope 外的那条一个字节都没重新量过，原样留着
        XCTAssertEqual(out.marks["/u/dev/b/elsewhere"]?.size, 300)
    }

    func testRefreshKeepsAMarkOnTheEnumeratedDirectoryItself() {
        let out = DiskMarks.refresh(previous([marked("/u/dev/a", size: 1_000)]),
                                    with: [node("/u/dev/a/x", size: 900)],
                                    under: "/u/dev/a")
        XCTAssertEqual(out.dropped, [])
        XCTAssertEqual(out.marks["/u/dev/a"]?.size, 1_000)
    }

    func testIsUnderComparesWholePathComponents() {
        XCTAssertTrue(DiskMarks.isUnder("/u/dev/a/b", "/u/dev/a"))
        XCTAssertTrue(DiskMarks.isUnder("/u/dev/a", "/u/dev/a"))
        XCTAssertFalse(DiskMarks.isUnder("/u/dev/ab", "/u/dev/a"), "同前缀的兄弟目录不算在 scope 底下")
        XCTAssertFalse(DiskMarks.isUnder("/u/dev", "/u/dev/a"))
        XCTAssertFalse(DiskMarks.isUnder("/u/dev/a", ""))
    }

    func testReattachOnAnEmptyMarkSetIsCheapAndSilent() {
        let out = DiskMarks.reattach([:], rootPath: "/u/dev", into: [node("/u/dev/a", size: 1)])
        XCTAssertTrue(out.marks.isEmpty)
        XCTAssertTrue(out.dropped.isEmpty)
    }
}
