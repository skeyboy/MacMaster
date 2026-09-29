import XCTest
import Foundation
@testable import MMDisk

/// 「值得看一眼」的三条纪律（只取最顶层、低于门槛不列、命中即停）
/// 决定了这份清单的字节数能不能相加。规则一旦漂了，
/// 面板上写的"共 X"就成了凭空捏造的总数。
final class DiskInsightsTests: XCTestCase {
    private let mib: UInt64 = 1024 * 1024
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func dir(_ name: String, size: UInt64, reclaim: ReclaimReason? = nil,
                     idleDays: TimeInterval? = nil, children: [DiskTreeNode] = []) -> DiskTreeNode {
        DiskTreeNode(id: "/" + name, name: name, path: "/" + name, size: size,
                     isDirectory: true, children: children, reclaim: reclaim,
                     modificationDate: idleDays.map { now.addingTimeInterval(-$0 * 86_400) })
    }

    private func file(_ name: String, size: UInt64) -> DiskTreeNode {
        DiskTreeNode(id: "/" + name, name: name, path: "/" + name, size: size,
                     isDirectory: false, children: [])
    }

    func testReclaimableDirectoryIsListedOnceWithoutItsChildren() {
        let tree = [dir("Caches", size: 900 * mib, reclaim: .cache, children: [
            dir("Web", size: 400 * mib, reclaim: .inherited),
            dir("Shaders", size: 400 * mib, reclaim: .inherited),
        ])]
        let findings = DiskInsights.worthALook(root: tree, now: now)
        XCTAssertEqual(findings.map(\.path), ["/Caches"])
        XCTAssertEqual(findings.first?.kind, .reclaimable)
    }

    func testBelowThresholdReclaimableDirectoryIsNotDescended() {
        // 32 MiB 的缓存目录本身不值得占一行，它下面的条目也不该冒出来充数。
        let tree = [dir("Caches", size: 32 * mib, reclaim: .cache, children: [
            dir("Big", size: 30 * mib, reclaim: .inherited),
        ])]
        XCTAssertTrue(DiskInsights.worthALook(root: tree, now: now).isEmpty)
    }

    func testStaleNeedsAMeasuredDate() {
        let old = dir("Projects", size: 2 * 1024 * mib, idleDays: 400)
        let recent = dir("Downloads", size: 2 * 1024 * mib, idleDays: 3)
        let unknown = dir("Vault", size: 2 * 1024 * mib)

        let findings = DiskInsights.worthALook(root: [old, recent, unknown], now: now)
        XCTAssertEqual(findings.map(\.path), ["/Projects"])
        XCTAssertEqual(findings.first?.kind, .stale)
        XCTAssertEqual(findings.first?.reason, "已 1 年没有增删过内容")
    }

    func testStaleIgnoresSmallDirectories() {
        let tree = [dir("OldNotes", size: 8 * mib, idleDays: 900)]
        XCTAssertTrue(DiskInsights.worthALook(root: tree, now: now).isEmpty)
    }

    func testLargeFileThresholdIsPerFileNotPerDirectory() {
        let huge = file("disk.dmg", size: 2 * 1024 * mib)
        let mid = file("archive.zip", size: 512 * mib)
        let findings = DiskInsights.worthALook(root: [huge, mid], now: now)
        XCTAssertEqual(findings.map(\.path), ["/disk.dmg"])
        XCTAssertEqual(findings.first?.kind, .largeFile)
    }

    func testPanelIsCappedAtSixLargest() {
        let tree = (0..<10).map { index in
            dir("Cache\(index)", size: UInt64(index + 1) * 100 * mib, reclaim: .cache)
        }
        let findings = DiskInsights.worthALook(root: tree, now: now)
        XCTAssertEqual(findings.count, DiskInsights.panelLimit)
        XCTAssertEqual(findings.map(\.size), findings.map(\.size).sorted(by: >))
        XCTAssertEqual(findings.first?.path, "/Cache9")
    }

    func testFindingsNeverNestSoTheirTotalIsTrustworthy() {
        let tree = [dir("Library", size: 4 * 1024 * mib, idleDays: 500, children: [
            dir("Caches", size: 900 * mib, reclaim: .cache),
            file("vm.img", size: 3 * 1024 * mib),
        ])]
        let findings = DiskInsights.worthALook(root: tree, now: now)
        XCTAssertFalse(findings.isEmpty)
        for a in findings {
            for b in findings where a.id != b.id {
                XCTAssertFalse(a.path.hasPrefix(b.path + "/"), "\(a.path) 嵌在 \(b.path) 里，总数会被重复计")
                XCTAssertFalse(b.path.hasPrefix(a.path + "/"), "\(b.path) 嵌在 \(a.path) 里，总数会被重复计")
            }
        }
    }

    func testStaleParentWinsOverLargeChildBecauseItIsSeenFirst() {
        // 命中即停：父目录已经作为"久未触碰"列出，里面的大文件就不再单列，
        // 否则同一批字节会在清单里出现两次。
        let tree = [dir("Old", size: 5 * 1024 * mib, idleDays: 800, children: [
            file("vm.img", size: 4 * 1024 * mib),
        ])]
        let findings = DiskInsights.worthALook(root: tree, now: now)
        XCTAssertEqual(findings.map(\.path), ["/Old"])
    }
}
