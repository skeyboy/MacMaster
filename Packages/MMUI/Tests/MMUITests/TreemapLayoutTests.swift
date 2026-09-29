import XCTest
import Foundation
import SwiftUI
@testable import MMUI

/// treemap 布局的回归测试。这里最贵的一条是"必须终止"：
/// 布局跑在主线程上，一次零进展的循环就是把界面钉死在 100% CPU。
final class TreemapLayoutTests: XCTestCase {

    private func makeItems(_ count: Int, value: (Int) -> Double) -> [TreemapItem] {
        (0..<count).map { TreemapItem(id: "\($0)", name: "n\($0)", value: value($0)) }
    }

    /// 在后台跑布局并限时等待；超时即视为死循环。
    private func computeWithTimeout(_ items: [TreemapItem], in rect: CGRect,
                                    options: TreemapLayoutOptions = TreemapLayoutOptions(),
                                    seconds: TimeInterval = 2) -> [TreemapRect]? {
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.value = TreemapLayout.compute(items: items, in: rect, options: options)
            done.signal()
        }
        guard done.wait(timeout: .now() + seconds) == .success else { return nil }
        return box.value
    }

    func testZeroValueItemsDoNotStallLayout() {
        // 全零 + 混合零都曾是死循环触发条件（矩形被吃干后 row 永远凑不出来）
        let allZero = makeItems(50) { _ in 0 }
        XCTAssertNotNil(computeWithTimeout(allZero, in: CGRect(x: 0, y: 0, width: 800, height: 600)))

        let mixed = makeItems(50) { $0 < 45 ? Double(50 - $0) * 1000 : 0 }
        let rects = computeWithTimeout(mixed, in: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertNotNil(rects)
        XCTAssertTrue((rects ?? []).allSatisfy { $0.rect.width >= 0 && $0.rect.height >= 0 })
    }

    func testLongTailKeepsTileCountBoundedAndAreaConserved() {
        // 1000 项指数衰减：面积必须守恒（尾部并进"其余"块），瓦片数必须在预算内
        let items = makeItems(1000) { pow(0.995, Double($0)) * 1_000_000 }
        let rect = CGRect(x: 0, y: 0, width: 900, height: 600)
        var options = TreemapLayoutOptions()
        options.maxDepth = 1

        guard let rects = computeWithTimeout(items, in: rect, options: options) else {
            return XCTFail("布局未在限时内返回")
        }
        XCTAssertLessThanOrEqual(rects.count, options.maxTiles)

        let topLevel = rects.filter { $0.depth == 0 }
        let covered = topLevel.reduce(0) { $0 + $1.rect.width * $1.rect.height }
        let available = (rect.insetBy(dx: options.outerPadding, dy: options.outerPadding)
            .width * rect.insetBy(dx: options.outerPadding, dy: options.outerPadding).height)
        // 允许内缩造成的固定损失，但长尾一旦被丢掉，缺口会远超这个容差
        XCTAssertGreaterThan(covered, available * 0.7)
        XCTAssertTrue(topLevel.contains { $0.isOthers }, "超出子块上限的尾部必须合并成一块")
    }

    func testChildCapShrinksWithDepth() {
        let options = TreemapLayoutOptions()
        XCTAssertEqual(options.childCap(at: 0), options.maxChildren)
        XCTAssertLessThan(options.childCap(at: 1), options.childCap(at: 0))
        XCTAssertLessThanOrEqual(options.childCap(at: 2), options.childCap(at: 1))
        XCTAssertGreaterThanOrEqual(options.childCap(at: 5), 4)
    }

    func testNestingStopsAtMaxDepth() {
        func branch(depth: Int) -> TreemapItem {
            TreemapItem(
                id: "d\(depth)", name: "branch\(depth)", value: 1_000_000,
                children: depth < 6 ? [branch(depth: depth + 1)] : []
            )
        }
        var options = TreemapLayoutOptions()
        options.maxDepth = 3
        let rects = computeWithTimeout([branch(depth: 0)],
                                       in: CGRect(x: 0, y: 0, width: 800, height: 600),
                                       options: options)
        guard let rects else { return XCTFail("布局未在限时内返回") }
        XCTAssertLessThanOrEqual(rects.map(\.depth).max() ?? 0, options.maxDepth - 1)
    }

    func testHeaderBandOnlyAppearsOnSubdividedBlocks() {
        let leaf = TreemapItem(id: "leaf", name: "leaf", value: 500_000)
        let parent = TreemapItem(id: "p", name: "parent", value: 1_000_000, children: [leaf])
        let rects = computeWithTimeout([parent], in: CGRect(x: 0, y: 0, width: 800, height: 600))
        guard let rects else { return XCTFail("布局未在限时内返回") }
        for rect in rects where rect.header == nil {
            XCTAssertTrue(rect.item.children.isEmpty || rect.depth + 1 >= TreemapLayoutOptions().maxDepth
                          || rect.rect.width < TreemapLayoutOptions().minHeaderWidth,
                          "不细分的块不该留出标题带：\(rect)")
        }
        XCTAssertNotNil(rects.first { $0.depth == 0 && $0.header != nil })
    }
}

private final class ResultBox {
    var value: [TreemapRect]?
}
