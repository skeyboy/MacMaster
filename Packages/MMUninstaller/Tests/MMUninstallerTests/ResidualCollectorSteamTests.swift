import XCTest
import Foundation
@testable import MMUninstaller

/// 反向那一条（审计 §5.4，优先级最高）：卸载 **Steam 本体**时，
/// `~/Library/Application Support/Steam` 会作为一条谨慎残留出现，而真机上那一个目录里
/// 装着全部已装游戏。这里钉的是"提醒只挂在它该挂的那一行上"：
/// 只加一次、只加在 `Application Support`、目录里没有 `steamapps` 就一个字不加。
///
/// 提醒走 `ResidualItem.caveat` 这个**独立字段**，不拼进 `reason`：照片
/// `docs/verification/p32b-steam/11a-narrow-window-truncation-before-fix.png` 现读，窗口硬最小
/// 宽度 1000 时这一行的副标题在画面上只剩 `~/Library/Application` 与 `已装游戏通常在其下` 两段，
/// 中间那一段（连 `steamapps` 这个词本身）被省略号吃掉，而光路径就有 35 个字符——
/// 拼进副标题等于没写。
/// 这里也不重复钉文案字面（那句话由 `SteamLauncherProbeTests` 钉），只钉"挂在哪儿、挂几次"。
final class ResidualCollectorSteamTests: XCTestCase {
    private var root: URL!
    private var home: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMSteamCaveat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        home = root.appendingPathComponent("home", isDirectory: true).path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 造一个 `~/Library/Application Support/<name>`，子项由参数给。
    @discardableResult
    private func makeSupportFolder(_ name: String, children: [String]) throws -> String {
        let path = "\(home!)/Library/Application Support/\(name)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        for child in children {
            let url = URL(fileURLWithPath: path).appendingPathComponent(child)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        return path
    }

    private func collector() -> ResidualCollector {
        ResidualCollector(home: home ?? "") { _ in 10 }
    }

    func testCaveatRidesTheApplicationSupportRow() throws {
        let steam = try makeSupportFolder("Steam", children: ["config", "steamapps"])
        var collector = collector()
        collector.add(path: steam, category: .applicationSupport, evidence: ResidualEvidence(.nameExact))
        let item = try XCTUnwrap(collector.items().first)
        XCTAssertEqual(item.reason, ResidualEvidence(.nameExact).text)
        XCTAssertEqual(item.caveat, SteamGameLibraryCaveat.note(children: ["config", "steamapps"]))
    }

    /// 别的厂商总目录里没有 `steamapps`，就一个字不加：这不是"凡是 Application Support 都提醒"。
    func testNoCaveatWithoutSteamApps() throws {
        let other = try makeSupportFolder("Notion", children: ["Cache", "Local Storage"])
        var collector = collector()
        collector.add(path: other, category: .applicationSupport, evidence: ResidualEvidence(.nameExact))
        let item = try XCTUnwrap(collector.items().first)
        XCTAssertEqual(item.reason, ResidualEvidence(.nameExact).text)
        XCTAssertNil(item.caveat)
    }

    /// 只认 `Application Support` 这一类：缓存目录里也可能有同名子项，那句提醒在那儿没有意义。
    func testOtherCategoriesGetNoCaveat() throws {
        let cache = try makeSupportFolder("SteamCache", children: ["steamapps"])
        var collector = collector()
        collector.add(path: cache, category: .cache, evidence: ResidualEvidence(.identifierExact))
        let item = try XCTUnwrap(collector.items().first)
        XCTAssertEqual(item.reason, ResidualEvidence(.identifierExact).text)
        XCTAssertNil(item.caveat)
    }

    /// 三条扫描路都往同一个收口投候选：同一个路径命中两次也不许把提醒挂两遍，
    /// 证据也仍然只留第一次那一句。
    func testCaveatAppearsOncePerPath() throws {
        let steam = try makeSupportFolder("Steam", children: ["steamapps"])
        var collector = collector()
        collector.add(path: steam, category: .applicationSupport, evidence: ResidualEvidence(.nameExact))
        collector.add(path: steam, category: .applicationSupport, evidence: ResidualEvidence(.identifierExact))
        let items = collector.items()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.reason, ResidualEvidence(.nameExact).text)
        XCTAssertNotNil(items.first?.caveat)
    }

    /// 目录读不到（已经不存在、或没权限枚举）时不得因为异常而丢掉这一行。
    func testMissingDirectoryKeepsOriginalReason() throws {
        var collector = collector()
        collector.add(path: "\(home!)/Library/Application Support/Gone",
                      category: .applicationSupport, evidence: ResidualEvidence(.nameExact))
        let item = try XCTUnwrap(collector.items().first)
        XCTAssertEqual(item.reason, ResidualEvidence(.nameExact).text)
        XCTAssertNil(item.caveat)
    }
}
