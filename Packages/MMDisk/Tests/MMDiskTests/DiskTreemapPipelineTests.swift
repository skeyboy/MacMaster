import XCTest
import Foundation
import MMUI
@testable import MMDisk

/// 用真实目录把"扫描结果 → TreemapItem → 布局"这条链跑通。
/// 之前只有单层块被画出来，而界面不会为这件事报任何错，
/// 所以这条链必须有一个端到端的回归测试。
final class DiskTreemapPipelineTests: XCTestCase {
    private let maxDepth = 3

    /// 与 DiskView.treemapItem(for:depth:) 保持一致的映射。
    private func map(_ node: DiskTreeNode, depth: Int) -> TreemapItem {
        var children: [TreemapItem] = []
        if node.isDirectory, depth + 1 < maxDepth {
            children = node.children
                .filter { $0.size > 0 }
                .sorted { $0.size > $1.size }
                .prefix(96 >> (2 * (depth + 1)))
                .map { map($0, depth: depth + 1) }
        }
        return TreemapItem(id: node.id, name: node.name, value: Double(node.size),
                           children: children, isDirectory: node.isDirectory)
    }

    func testRealTreeProducesNestedRects() async throws {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer").path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw XCTSkip("无 Developer 目录")
        }
        let output = await DiskScanner.performScan(rootPath: path)
        let items = output.topItems.map { map($0, depth: 0) }
        XCTAssertTrue(items.contains { !$0.children.isEmpty }, "映射阶段就丢了子层")

        let rects = TreemapLayout.compute(
            items: items, in: CGRect(x: 0, y: 0, width: 900, height: 600),
            options: TreemapLayoutOptions()
        )
        let nested = rects.filter { $0.depth > 0 }
        XCTAssertFalse(nested.isEmpty, "布局阶段没有产出任何子层块")
        XCTAssertNotNil(rects.first { $0.header != nil })
    }
}
