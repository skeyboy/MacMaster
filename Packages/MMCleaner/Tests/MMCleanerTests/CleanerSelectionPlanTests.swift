import MMCore
import MMFileScanner
import XCTest
@testable import MMCleaner

final class CleanerSelectionPlanTests: XCTestCase {
    private func category(_ id: String, risk: MMRisk, items: [CacheSubItem]) -> CacheCategory {
        var category = CacheCategory(id: id, name: id, subtitle: id, iconName: "folder",
                                     risk: risk, scope: .appCache, paths: [])
        category.subItems = items
        return category
    }

    func testPreviewAndExecutionShareOnlyEligibleUniqueRoots() {
        let parent = CacheSubItem(name: "parent", path: "/tmp/cache", size: 100, fileCount: 2)
        let child = CacheSubItem(name: "child", path: "/tmp/cache/child", size: 20, fileCount: 1)
        let excluded = CacheSubItem(name: "excluded", path: "/tmp/excluded", size: 40, fileCount: 1)
        let unreadable = CacheSubItem(name: "unreadable", path: "/tmp/unreadable", size: nil,
                                      fileCount: 0, isAccessible: false)
        let categories = [
            category("first", risk: .safe, items: [child, excluded, unreadable]),
            category("second", risk: .safe, items: [parent, parent]),
            category("protected", risk: .readOnly, items: [
                CacheSubItem(name: "protected", path: "/tmp/protected", size: 900, fileCount: 1),
            ]),
        ]

        let plan = CleanerSelectionPlan(categories: categories,
                                        selectedIDs: ["first", "second", "protected"],
                                        isExcluded: { $0 == excluded.path })

        XCTAssertEqual(plan.paths, [parent.path])
        XCTAssertEqual(plan.groups.map(\.id), ["second"])
        XCTAssertEqual(plan.groups[0].paths, plan.paths)
        XCTAssertEqual(plan.size, 100)
    }

    func testUnknownSizeIsNotReportedAsZeroOrExactTotal() {
        let measured = CacheSubItem(name: "measured", path: "/tmp/measured", size: 25, fileCount: 1)
        let unknown = CacheSubItem(name: "unknown", path: "/tmp/unknown", size: nil, fileCount: 1)
        let plan = CleanerSelectionPlan(categories: [category("cache", risk: .safe,
                                                              items: [measured, unknown])],
                                        selectedIDs: ["cache"], isExcluded: { _ in false })

        XCTAssertEqual(plan.paths.count, 2)
        XCTAssertNil(plan.size)
        XCTAssertEqual(plan.knownSize, 25)
        XCTAssertEqual(plan.unmeasuredCount, 1)
        XCTAssertTrue(plan.sizeSummary.contains("1 项未测"))
    }
}
