import XCTest
import SwiftUI
@testable import MMUI

/// 键盘选块的方向判定。几何由布局给出，这里只验"往哪走算隔壁"，
/// 所以直接手搓矩形，不依赖 TreemapLayout 的输出。
final class TreemapKeyboardTests: XCTestCase {
    private func cell(_ name: String, _ rect: CGRect, depth: Int = 0, isOthers: Bool = false) -> TreemapRect {
        TreemapRect(
            item: TreemapItem(id: name, name: name, value: 1, isDirectory: true),
            rect: rect, depth: depth, isOthers: isOthers
        )
    }

    func testMovesToNearestAlignedNeighbour() {
        // A 是大块，B 紧贴其右侧；C 更靠右但中心偏移更大。
        let rects = [
            cell("A", CGRect(x: 0, y: 0, width: 400, height: 300)),
            cell("B", CGRect(x: 400, y: 0, width: 100, height: 120)),
            cell("C", CGRect(x: 520, y: 0, width: 60, height: 60)),
        ]
        XCTAssertEqual(TreemapView.stepped(from: rects[0], toward: .right, in: rects)?.id, "B")
        XCTAssertEqual(TreemapView.stepped(from: rects[1], toward: .left, in: rects)?.id, "A")
    }

    func testPrefersAlignmentOverRawDistance() {
        // D 的中心更近但横向偏移大；E 远一点却正对着上方。
        let rects = [
            cell("S", CGRect(x: 200, y: 300, width: 100, height: 100)),
            cell("D", CGRect(x: 0, y: 200, width: 60, height: 60)),
            cell("E", CGRect(x: 220, y: 0, width: 60, height: 200)),
        ]
        XCTAssertEqual(TreemapView.stepped(from: rects[0], toward: .up, in: rects)?.id, "E")
    }

    func testStaysWithinSameDepth() {
        // 子块中心恰好落在父块右侧的候选区里，但深度不同，不该被选中。
        let rects = [
            cell("A", CGRect(x: 0, y: 0, width: 300, height: 300), depth: 0),
            cell("B", CGRect(x: 300, y: 0, width: 300, height: 300), depth: 0),
            cell("B-child", CGRect(x: 310, y: 10, width: 280, height: 280), depth: 1),
        ]
        XCTAssertEqual(TreemapView.stepped(from: rects[0], toward: .right, in: rects)?.id, "B")
    }

    func testOthersTileIsNeverATarget() {
        // "其余 N 项"是虚拟块，键盘把光标停上去会让用户以为能下钻。
        let rects = [
            cell("A", CGRect(x: 0, y: 0, width: 300, height: 300)),
            cell("tail", CGRect(x: 300, y: 0, width: 300, height: 300), isOthers: true),
        ]
        XCTAssertNil(TreemapView.stepped(from: rects[0], toward: .right, in: rects))
    }

    func testNoCandidateInDirectionReturnsNilSoKeyIsIgnored() {
        let rects = [cell("A", CGRect(x: 0, y: 0, width: 100, height: 100))]
        XCTAssertNil(TreemapView.stepped(from: rects[0], toward: .right, in: rects))
    }

    func testEmptySelectionStartsAtLargestTile() {
        let rects = [cell("A", CGRect(x: 0, y: 0, width: 100, height: 100))]
        XCTAssertEqual(TreemapView.stepped(from: nil, toward: .right, in: rects)?.id, "A")
    }
}
