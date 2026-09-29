import XCTest
import SwiftUI
@testable import MMUI

/// 全树过滤落到布局层的两条承诺：
/// 两级视觉（匹配保色、含命中祖先退色）必须真的分得开；
/// 深层 childCap 截断出的尾部必须并进"其余"，面积不能凭空蒸发——
/// 过滤布局按命中体积重排，丢一块就是撒一个能对上的谎。
final class TreemapFilterTierTests: XCTestCase {

    func testMatchTierOpacityIsTwoLevelAndKeepsColor() {
        // 保色 = 和不过滤时完全一样，不引入第三种"命中色"
        XCTAssertEqual(TreemapView.fillOpacity(for: .matched, depth: 0, isHovered: false),
                       TreemapView.fillOpacity(for: nil, depth: 0, isHovered: false))
        XCTAssertEqual(TreemapView.fillOpacity(for: .matched, depth: 1, isHovered: false),
                       TreemapView.fillOpacity(for: nil, depth: 1, isHovered: false))

        // 退色必须明显低于保色，同级里一眼能分两档
        XCTAssertLessThan(TreemapView.fillOpacity(for: .containsMatch, depth: 0, isHovered: false),
                          TreemapView.fillOpacity(for: .matched, depth: 0, isHovered: false))
        XCTAssertLessThanOrEqual(TreemapView.fillOpacity(for: .containsMatch, depth: 1, isHovered: false),
                                 TreemapView.fillOpacity(for: .containsMatch, depth: 0, isHovered: false))

        // hover 回到全亮：临时退色的块不该读不出内容
        XCTAssertEqual(TreemapView.fillOpacity(for: .containsMatch, depth: 2, isHovered: true), 1)
    }

    func testNestedTailMergesIntoOthersAndKeepsArea() {
        // 30 个子块 > depth 1 的 childCap(24)：尾部 6 块必须进"其余"，不能被静默丢掉
        let value: Double = 10_000
        let children = (0..<30).map {
            TreemapItem(id: "p/c\($0)", name: "c\($0)", value: value, isDirectory: true)
        }
        let parent = TreemapItem(id: "p", name: "p", value: Double(children.count) * value,
                                 children: children, isDirectory: true)
        let rects = TreemapLayout.compute(
            items: [parent], in: CGRect(x: 0, y: 0, width: 900, height: 600),
            options: TreemapLayoutOptions()
        )
        let depth1 = rects.filter { $0.depth == 1 }
        XCTAssertTrue(depth1.contains { $0.isOthers }, "超出 childCap 的尾部必须出现'其余'块")
        let laidValue = depth1.reduce(0) { $0 + $1.item.value }
        XCTAssertEqual(laidValue, Double(children.count) * value, accuracy: 1,
                       "面积必须守恒：子块总值要等于父块总值")
    }
}
