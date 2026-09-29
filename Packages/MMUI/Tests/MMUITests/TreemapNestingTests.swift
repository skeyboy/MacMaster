import XCTest
import SwiftUI
import AppKit
@testable import MMUI

/// 嵌套渲染是这张图的全部信息量所在：只画顶层等于把"哪里占地方"
/// 这个问题原样退回给用户。这两条测试分别把"布局丢层级"和
/// "数据丢层级"钉死。
final class TreemapNestingTests: XCTestCase {
    private func branch(depth: Int, breadth: Int) -> TreemapItem {
        TreemapItem(
            id: "b\(depth)", name: "branch\(depth)", value: 1_000_000,
            children: depth < 2 ? (0..<breadth).map { _ in branch(depth: depth + 1, breadth: breadth) } : [],
            isDirectory: true
        )
    }

    func testLayoutEmitsChildRectsAtEveryDepth() {
        let rects = TreemapLayout.compute(
            items: [branch(depth: 0, breadth: 6)],
            in: CGRect(x: 0, y: 0, width: 900, height: 600),
            options: TreemapLayoutOptions()
        )
        let depths = Set(rects.map(\.depth))
        XCTAssertEqual(depths, [0, 1, 2], "三层都要有块：\(depths)")
        XCTAssertGreaterThanOrEqual(rects.filter { $0.depth == 1 }.count, 6)
    }

    /// 深度只靠明度区分，所以 shade 必须真的改变颜色；
    /// 一旦它原样返回，整张图就会"看起来没有层级"——子块和父块同色。
    func testShadeActuallyLightensWithDepth() {
        let base = TreemapPalette.hex(0xAF52DE)
        let one = TreemapPalette.shade(base, depth: 1)
        let two = TreemapPalette.shade(base, depth: 2)
        XCTAssertNotEqual(one, base)
        XCTAssertNotEqual(two, one)
        XCTAssertEqual(TreemapPalette.shade(base, depth: 0), base)

        func luminance(_ color: Color) -> Double {
            let rgb = NSColor(color).usingColorSpace(.sRGB)!
            return 0.2126 * Double(rgb.redComponent) + 0.7152 * Double(rgb.greenComponent)
                + 0.0722 * Double(rgb.blueComponent)
        }
        XCTAssertGreaterThan(luminance(one), luminance(base))
        XCTAssertGreaterThan(luminance(two), luminance(one))
    }

    /// 子块必须落在父块内部。曾经的缺陷是标题带下沿写成了 `body.maxY`，
    /// 整棵子树被推到画布外面裁掉——块数看着正常，屏幕上却一张单层图。
    func testChildRectsStayInsideTheirParent() {
        let canvas = CGRect(x: 0, y: 0, width: 900, height: 600)
        let options = TreemapLayoutOptions()
        let rects = TreemapLayout.compute(
            items: [nestedBranch(prefix: "root", depth: 0)], in: canvas, options: options
        )
        let parents = rects.filter { $0.header != nil }
        XCTAssertFalse(parents.isEmpty)
        var checked = 0
        for parent in parents {
            let children = rects.filter {
                $0.depth == parent.depth + 1 && $0.item.id.hasPrefix(parent.item.id + "/")
            }
            XCTAssertFalse(children.isEmpty, "\(parent.item.name) 有标题带却没有子块")
            for child in children {
                XCTAssertTrue(parent.rect.contains(child.rect),
                              "子块 \(child.item.name) 掉出了 \(parent.item.name)：\(child.rect)")
                XCTAssertGreaterThanOrEqual(child.rect.minY, parent.header!.maxY,
                                            "子块压到了标题带上：\(child.item.name)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 10)
        for rect in rects {
            XCTAssertTrue(canvas.insetBy(dx: -1, dy: -1).contains(rect.rect),
                          "块掉出了画布：\(rect.item.name) \(rect.rect)")
        }
    }

    /// id 用路径式命名，测试里才能把子块认领回正确的父块。
    private func nestedBranch(prefix: String, depth: Int) -> TreemapItem {
        let children: [TreemapItem] = depth < 2
            ? (0..<5).map { nestedBranch(prefix: "\(prefix)/c\($0)", depth: depth + 1) }
            : []
        return TreemapItem(id: prefix, name: prefix, value: 1_000_000,
                           children: children, isDirectory: true)
    }

    func testChildKeepsItsOwnReclaimFlagWhenNested() {
        let leaf = TreemapItem(id: "leaf", name: "DerivedData", value: 500_000,
                               isDirectory: true, reclaimable: true)
        let parent = TreemapItem(id: "p", name: "Xcode", value: 1_000_000,
                                 children: [leaf], isDirectory: true)
        let rects = TreemapLayout.compute(
            items: [parent], in: CGRect(x: 0, y: 0, width: 900, height: 600),
            options: TreemapLayoutOptions()
        )
        XCTAssertTrue(rects.contains { $0.item.reclaimable && $0.depth == 1 })
        XCTAssertFalse(rects.first { $0.depth == 0 }!.item.reclaimable)
    }
}
