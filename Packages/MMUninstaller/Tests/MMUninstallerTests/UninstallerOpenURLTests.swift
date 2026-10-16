import XCTest
import Foundation
import MMCore
@testable import MMUninstaller

/// 入站 URL 这一片：`macmaster://uninstall?path=…` 能点名谁、点不到谁。
///
/// 解析器是纯函数，直接喂 URL 字符串；点名那一步用 `ResidualFixture` 造真目录，
/// 因为它要钉的是"只认清单里已有的条目"，而清单必须是真枚举出来的。
/// 壳层那一条接线（`.onOpenURL` → `AppState.handleOpen`）不在这个包能测的范围里，
/// 由 `Scripts/p46-url-capture.sh` 的带窗口实拍收口。
@MainActor
final class UninstallerOpenURLTests: XCTestCase {

    private func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            XCTFail("这条测试用的 URL 拼不出来：\(string)")
            return URL(fileURLWithPath: "/")
        }
        return url
    }

    // MARK: 解析

    /// 两种取值形态都归成一条路径：字面路径与 `file://` 整份 URL
    ///（后者是别的 app 转发我们时拼出来的形状，照参考侧 `SelectionReceiver.swift:16`）。
    func testPlainAndFileURLFormsBothBecomePaths() {
        XCTAssertEqual(UninstallerOpenURL.bundlePaths(from: url("macmaster://uninstall?path=/Applications/Foo.app")),
                       ["/Applications/Foo.app"])
        XCTAssertEqual(UninstallerOpenURL.bundlePaths(from: url("macmaster://uninstall?path=file:///Applications/Foo.app")),
                       ["/Applications/Foo.app"])
    }

    /// 访达多选就是同一个名字重复出现：保序（第一个是用户右键的那一个）、去重。
    func testRepeatedPathsKeepOrderAndCollapseDuplicates() {
        XCTAssertEqual(UninstallerOpenURL.bundlePaths(
            from: url("macmaster://uninstall?path=/Applications/B.app&path=/Applications/A.app&path=/Applications/B.app")),
                       ["/Applications/B.app", "/Applications/A.app"])
    }

    /// 认错门的 URL 一个字都不认：scheme 不同（参考项目自己的 scheme）、host 不是已知的动作、
    /// 以及压根不是 URL 的普通 https 链接。
    func testWrongSchemeOrHostNamesNothing() {
        for string in ["uninstally://uninstall?path=/Applications/Foo.app",
                       "macmaster://open?path=/Applications/Foo.app",
                       "macmaster://?path=/Applications/Foo.app",
                       "https://example.com/uninstall?path=/Applications/Foo.app"] {
            XCTAssertEqual(UninstallerOpenURL.bundlePaths(from: url(string)), [], string)
        }
    }

    /// 相对路径一律不收：要先猜"基于哪儿解析"，猜错的后果是选中另一个应用，比不选更糟。
    /// 空值、只有空白、别的参数名同理。
    func testNonAbsoluteOrBlankValuesAreDropped() {
        XCTAssertEqual(UninstallerOpenURL.bundlePaths(
            from: url("macmaster://uninstall?path=Foo.app&path=../Foo.app&path=&path=%20%20&name=Foo&path=/Applications/Ok.app")),
                       ["/Applications/Ok.app"])
    }

    /// 编码这一条把实测结论钉住：`URLComponents.queryItems` 已经把 `%20`、`%2B` 解开，
    /// 且**不会**把字面 `+` 按 form 编码变成空格（先用量尺测过再写的断言）。
    func testEncodingOfSpaceAndPlusSurvive() {
        XCTAssertEqual(UninstallerOpenURL.bundlePaths(
            from: url("macmaster://uninstall?path=/Applications/My%20App.app&path=/Applications/C%2B%2B.app&path=/Applications/Plus+.app")),
                       ["/Applications/My App.app", "/Applications/C++.app", "/Applications/Plus+.app"])
    }

    // MARK: 点名

    private func loadedModel(with fixture: ResidualFixture) async throws -> UninstallerModel {
        let model = UninstallerModel()
        model.optionsFactory = { ResidualScanOptions(home: fixture.homePath, systemRoot: fixture.systemPath) }
        model.appDirectoriesFactory = { _ in [fixture.homePath + "/Applications"] }
        model.provenancePrefixesFactory = { _ in [] }
        model.provenanceReceiptsRootFactory = { _ in nil }
        await model.reloadListing()
        return model
    }

    func testInboundSelectsOnlyWhatTheListingAlreadyHas() async throws {
        let fixture = try ResidualFixture(caseName: "openURLFocus")
        defer { fixture.cleanup() }
        let appPath = try fixture.makeApp(name: "Foo", bundleID: "com.example.Foo")
        try fixture.makeApp(name: "Bar", bundleID: "com.example.Bar")
        let model = try await loadedModel(with: fixture)

        let hit = model.focusInbound(paths: UninstallerOpenURL.bundlePaths(
            from: url("macmaster://uninstall?path=\(appPath)")))
        XCTAssertEqual(hit, appPath)
        XCTAssertEqual(model.selectedApp?.path, appPath)
    }

    /// 清单里没有的点名不改选任何东西：用户正在看的那一行不能被一句陌生 URL 踢掉。
    func testUnlistedNameKeepsTheCurrentSelection() async throws {
        let fixture = try ResidualFixture(caseName: "openURLMiss")
        defer { fixture.cleanup() }
        let appPath = try fixture.makeApp(name: "Foo", bundleID: "com.example.Foo")
        let model = try await loadedModel(with: fixture)
        model.select(appPath)

        XCTAssertNil(model.focusInbound(paths: ["/System/Applications/Notes.app"]))
        XCTAssertEqual(model.selectedApp?.path, appPath)
    }

    /// 大小写不同按同一个 bundle 处理：精确匹配优先，退一步才忽略大小写。
    func testDifferentCaseStillHitsTheSameBundle() async throws {
        let fixture = try ResidualFixture(caseName: "openURLCase")
        defer { fixture.cleanup() }
        let appPath = try fixture.makeApp(name: "Foo", bundleID: "com.example.Foo")
        let model = try await loadedModel(with: fixture)

        let lowered = appPath.replacingOccurrences(of: "Foo.app", with: "foo.app")
        XCTAssertNotEqual(lowered, appPath, "夹具名要能造出大小写差")
        XCTAssertEqual(model.focusInbound(paths: [lowered]), appPath)
    }

    /// 队列必须在视图建立之前就存得住：冷启动时 URL 先到、卸载页的 `.task` 后跑，
    /// 只订阅变更会把它吞掉。消费式取走，第二次拿是空——旧点名不能再来抢选中项。
    func testQueueIsStickyUntilConsumedOnce() {
        let request = UninstallerScanRequest()
        XCTAssertEqual(request.consume(), [])
        request.enqueue([])
        XCTAssertEqual(request.consume(), [], "空 enqueue 不该留下任何东西")

        request.enqueue(["/Applications/A.app", "/Applications/B.app"])
        request.enqueue(["/Applications/C.app"])
        XCTAssertEqual(request.consume(), ["/Applications/A.app", "/Applications/B.app", "/Applications/C.app"])
        XCTAssertEqual(request.consume(), [])
    }

    // MARK: 否证：一条 URL 送不进删除

    /// 这一条是这片的安全边界，两重都要钉：
    /// ① 点不中（`/System/Library` 从来不在清单里，选不中就没有"当前选中项"，
    ///    而删除入参只从当前选中项的残留列表拼）；
    /// ② 就算它点得中（同名的 `/System/Library` 位置在授权根之外），正向闸也会单独拒它 ——
    ///    所以"接收端"和"删除"之间不是靠一句约定，是靠两道各自成立的闸。
    func testSystemPathFromAUrlCannotBecomeADeletionInput() async throws {
        let fixture = try ResidualFixture(caseName: "openURLDenial")
        defer { fixture.cleanup() }
        try fixture.makeApp(name: "Foo", bundleID: "com.example.Foo")
        let model = try await loadedModel(with: fixture)

        let hostile = "/System/Library/CoreServices/Finder.app"
        let paths = UninstallerOpenURL.bundlePaths(from: url("macmaster://uninstall?path=\(hostile)"))
        XCTAssertEqual(paths, [hostile], "解析器只管翻译，拒它是后面两道闸的事")
        XCTAssertNil(model.focusInbound(paths: paths))
        XCTAssertNil(model.selectedAppID)

        let roots = model.deletionRoots(for: model.optionsFactory())
        XCTAssertNotNil(DeletionGuard.allowedRootRejection(for: hostile, roots: roots),
                        "卸载页没扫过系统域，正向闸必须单独把它拒掉")
    }
}
