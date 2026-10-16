import Foundation
import MMCore
import XCTest
@testable import MMUninstaller

/// P52b：本体那一层的两态判定（`UninstallCandidate.bodyDeletable`）与它拦住的三个入口。
///
/// 为什么是两态而不是第三档（所以这个名字不叫 `risk`）、为什么 `.caution` 明确不接到本体上：
/// `docs/analysis/uninstaller-app-body-risk.md` §3、§4 建议 1、§4 建议 4。
///
/// 这一族在改动之前**没有任何测试钉过**：`isSystemOwned` 在 `Tests/` 里零命中，
/// 也就是"系统应用今天能被删"这条从载入一路到删除执行没人验收过（同一份文档 §4 那条）。
@MainActor
final class UninstallBodyReadOnlyTests: XCTestCase {

    private func candidate(bundleID: String, path: String = "/Applications/Foo.app",
                           residuals: [ResidualItem] = []) -> UninstallCandidate {
        UninstallCandidate(id: path, name: "Foo", bundleName: "Foo", path: path,
                           bundleID: bundleID, version: "1.0", build: "1",
                           minSystemVersion: "14.0", executable: "Foo", developer: "", teamID: "",
                           modificationDate: nil, residuals: residuals,
                           isSystemOwned: AppScanner.isSystemOwned(bundleID: bundleID))
    }

    private func item(_ path: String) -> ResidualItem {
        ResidualItem(id: path, path: path, displayPath: path,
                    name: (path as NSString).lastPathComponent,
                    category: .cache, risk: .safe, reason: "测试注入", size: 10)
    }

    // MARK: 判定

    func testOnlySystemOwnedBodiesLoseTheDeletionEntry() {
        XCTAssertTrue(candidate(bundleID: "com.example.Foo").bodyDeletable)
        XCTAssertFalse(candidate(bundleID: "com.apple.Notes").bodyDeletable)
        // 判据是前缀，大小写同一档（`AppScanner.isSystemOwned` 里先 lowercased）。
        XCTAssertFalse(candidate(bundleID: "COM.APPLE.Notes").bodyDeletable)
    }

    // MARK: 删除集合

    /// 否证：本体只读时，那串交给 `FileTrashService` 的路径里不该出现 app 本体 ——
    /// 即使残留全被勾上，也不该顺着"一并移除"把 Apple 的应用一起带走。
    func testReadOnlyBodyIsNeverADeletionRoot() {
        let items = [item("/tmp/x/com.example.Foo/Caches"), item("/tmp/x/com.example.Foo/Prefs")]
        let selected = Set(items.map(\.id))
        let paths = UninstallSelection.deletionPaths(appPath: "/System/Applications/Notes.app",
                                                     bodyDeletable: false,
                                                     items: items, selectedIDs: selected)
        XCTAssertEqual(Set(paths), selected, "只剩勾选的残留根")
        XCTAssertFalse(paths.contains("/System/Applications/Notes.app"))
    }

    /// 默认值不动旧口径：不点这一格就是本体 + 残留，本体排在最前。
    func testDefaultStillPutsTheBodyInFront() {
        let items = [item("/tmp/x/com.example.Foo/Caches")]
        XCTAssertEqual(UninstallSelection.deletionPaths(appPath: "/tmp/App.app", items: items,
                                                        selectedIDs: Set(items.map(\.id))),
                       ["/tmp/App.app", "/tmp/x/com.example.Foo/Caches"])
    }

    // MARK: 两个卸载入口

    /// 这一跑不该动盘：本体路径指向一个不存在的目录，真走到 `move()` 就会留下
    /// `lastResult` 与一条失败。这里要的是**什么都不留下**。
    func testBothUninstallEntriesRefuseAReadOnlyBody() async {
        let missing = "/private/tmp/p52-body-readonly-\(UUID().uuidString)/Notes.app"
        let model = UninstallerModel()
        model.apps = [candidate(bundleID: "com.apple.Notes", path: missing)]
        model.select(model.apps[0].id)

        await model.uninstallAppOnly()
        await model.uninstallAppWithSelection()

        XCTAssertNil(model.lastResult, "本体只读时不该走到删除执行")
        XCTAssertTrue(model.failures.isEmpty)
    }

    // MARK: 第三层（执行处复验）的现状

    /// 这一条钉的是**建议 1 之前为什么非做不可**：正向闸只按位置判，而 `/Applications` 是卸载页
    /// 允许根里固定三条的第一条，所以 Apple 的应用**在闸内**。不是在主张闸该放行它 ——
    /// 闸答不了"这是谁的应用"（`docs/analysis/uninstaller-app-body-risk.md` §2.3），
    /// 拦得住它的只有上面那一层归属判定。哪天 `/Applications` 从根里被挪走，这一条会先响。
    func testThePositiveGateJudgesPositionNotOwnership() {
        let roots = AppScanner.applicationDirectories(home: "/Users/u", volumePaths: [],
                                                     directoryExists: { _ in true })
        XCTAssertEqual(roots, ["/Applications", "/Applications/Utilities", "/Users/u/Applications"])
        XCTAssertTrue(DeletionGuard.isInside("/Applications/Notes.app", roots: roots))
        XCTAssertFalse(DeletionGuard.isInside("/System/Applications/Notes.app", roots: roots))
    }
}
