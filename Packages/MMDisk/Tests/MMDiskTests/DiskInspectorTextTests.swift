import XCTest
import Foundation
import MMUI
@testable import MMDisk

/// 详情四宫格「子项」那一格的三种态。
/// 这条测的是**标签与数值口径对不对得上**：以前这一格叫「文件数」，喂的却是直接子项数，
/// 而触达深度上限的目录 `children` 是空的（字节靠 deepSize 兜底、名字根本没枚举过），
/// 于是显示成 0——那等于指着一个几 GB 的目录说"里面没有文件"。
final class DiskInspectorTextTests: XCTestCase {

    private func node(isDirectory: Bool, children: [DiskTreeNode] = [], measured: Bool = true) -> DiskTreeNode {
        DiskTreeNode(id: "/root/x", name: "x", path: "/root/x", size: 1_000,
                     isDirectory: isDirectory, children: children, descendantsMeasured: measured)
    }

    func testFileHasNoChildrenCell() {
        XCTAssertEqual(DiskInspectorText.childCount(of: node(isDirectory: false), enumerated: 0), "—")
    }

    func testEnumeratedDirectoryReportsItsDirectChildCount() {
        let kids = [node(isDirectory: false), node(isDirectory: false), node(isDirectory: false)]
        let dir = node(isDirectory: true, children: kids)
        XCTAssertEqual(DiskInspectorText.childCount(of: dir, enumerated: kids.count), MMFormat.count(3))
    }

    /// 量过、真的是空的目录，就该显示 0——这一档和"没量过"必须分得开。
    func testMeasuredEmptyDirectoryShowsZero() {
        let dir = node(isDirectory: true, children: [], measured: true)
        XCTAssertEqual(DiskInspectorText.childCount(of: dir, enumerated: 0), MMFormat.count(0))
    }

    func testUnmeasuredDirectoryNeverShowsZero() {
        let capped = node(isDirectory: true, children: [], measured: false)
        let text = DiskInspectorText.childCount(of: capped, enumerated: 0)
        XCTAssertFalse(text.contains("0"), "未枚举的目录不能显示成 0：那是把「没量到」说成「没有」")
        XCTAssertEqual(text, "未枚举")
    }
}
