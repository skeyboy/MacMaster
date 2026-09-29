import Foundation
import XCTest
@testable import MMUninstaller

/// 1.1 敏感度三档的命中差异。
final class ResidualSensitivityTests: XCTestCase {
    private var fixture: ResidualFixture!

    override func setUpWithError() throws {
        fixture = try ResidualFixture(caseName: name)
    }

    override func tearDownWithError() throws {
        fixture?.cleanup()
        fixture = nil
    }

    /// strict 只收直接命中的标准目录；厂商子目录、WebKit、Cookies 一律不进。
    func testStrictOnlyExactMatches() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let cache = try fixture.folderWithFile(try fixture.libraryFolder("Caches/com.example.MyApp"))
        let support = try fixture.folderWithFile(try fixture.libraryFolder("Application Support/My App"))
        let preference = try fixture.libraryFolder("Preferences")
        try fixture.writePlist(preference + "/com.example.MyApp.plist", ["theme": "dark"])
        // 只在更宽档位才应出现的三类：
        let vendor = try fixture.folderWithFile(try fixture.libraryFolder("Application Support/Example/My App Extra"))
        let webKit = try fixture.folderWithFile(try fixture.libraryFolder("WebKit/com.example.MyApp"))
        let cookie = try fixture.libraryFolder("Cookies")
        try fixture.writeFile(cookie + "/com.example.MyApp.binaryCookies")

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        let hits = Set(report.items.map(\.path))

        XCTAssertTrue(hits.contains(cache), "strict 应命中包名同名的缓存目录")
        XCTAssertTrue(hits.contains(support), "strict 应命中名称完全对应的应用数据")
        XCTAssertTrue(hits.contains(preference + "/com.example.MyApp.plist"))
        XCTAssertTrue(hits.contains(vendor) == false, "厂商子目录里的包含匹配不该在 strict 出现")
        XCTAssertTrue(hits.contains(webKit) == false, "WebKit 属于 enhanced 起")
        XCTAssertTrue(report.items.contains { $0.path.hasSuffix("binaryCookies") } == false, "Cookies 属于 deep")
    }

    /// enhanced 打开包含匹配 + 下探一层 + WebKit。
    func testEnhancedAddsVendorAndWebKit() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let vendor = try fixture.folderWithFile(try fixture.libraryFolder("Application Support/Example/My App Extra"))
        let webKit = try fixture.folderWithFile(try fixture.libraryFolder("WebKit/com.example.MyApp"))
        let cookie = try fixture.libraryFolder("Cookies")
        try fixture.writeFile(cookie + "/com.example.MyApp.binaryCookies")

        let report = scan(fixture, appPath: app, sensitivity: .enhanced)
        let hits = Set(report.items.map(\.path))
        XCTAssertTrue(hits.contains(vendor), "enhanced 应下探厂商目录并收下包含应用名的目录")
        XCTAssertTrue(hits.contains(webKit), "enhanced 应纳入 WebKit")
        XCTAssertTrue(report.items.contains { $0.path.hasSuffix("binaryCookies") } == false, "Cookies 仍属于 deep")
    }

    /// deep 再纳入 Cookies 与多一层递归。
    func testDeepAddsCookies() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let cookie = try fixture.libraryFolder("Cookies")
        try fixture.writeFile(cookie + "/com.example.MyApp.binaryCookies")
        let scripts = try fixture.folderWithFile(try fixture.libraryFolder("Application Scripts/com.example.MyApp"))
        let deepVendor = try fixture.folderWithFile(
            try fixture.libraryFolder("Application Support/Example/Nested/My App Data"))

        let report = scan(fixture, appPath: app, sensitivity: .deep)
        let hits = Set(report.items.map(\.path))
        XCTAssertTrue(hits.contains(cookie + "/com.example.MyApp.binaryCookies"), "deep 应纳入 Cookies")
        XCTAssertTrue(hits.contains(scripts), "deep 应纳入 Application Scripts")
        XCTAssertTrue(hits.contains(deepVendor), "deep 多一层递归")
    }

    /// 三档命中集合必须单调递增，且档与档之间确实不同 —— 否则"敏感度"是个假选项。
    func testSensitivityMonotonicAndDistinct() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        try fixture.folderWithFile(try fixture.libraryFolder("Caches/com.example.MyApp"))
        try fixture.folderWithFile(try fixture.libraryFolder("Application Support/Example/My App Extra"))
        try fixture.folderWithFile(try fixture.libraryFolder("WebKit/com.example.MyApp"))
        let cookies = try fixture.libraryFolder("Cookies")
        try fixture.writeFile(cookies + "/com.example.MyApp.binaryCookies")

        let strict = Set(scan(fixture, appPath: app, sensitivity: .strict).items.map(\.path))
        let enhanced = Set(scan(fixture, appPath: app, sensitivity: .enhanced).items.map(\.path))
        let deep = Set(scan(fixture, appPath: app, sensitivity: .deep).items.map(\.path))

        XCTAssertTrue(strict.isSubset(of: enhanced), "增强档不该丢严格档已命中的项")
        XCTAssertTrue(enhanced.isSubset(of: deep), "深度档不该丢增强档已命中的项")
        XCTAssertTrue(strict.count < enhanced.count, "增强档应比严格档多命中")
        XCTAssertTrue(enhanced.count < deep.count, "深度档应比增强档多命中")
    }

    /// 红线：越线路径不得进默认清单。即使目录里放着同名残留也不该被扫到。
    func testRedlinePathsAreNeverScanned() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        // 假系统域里的 /Library/Extensions 与假 /usr/local，都不在清单内。
        let extensions = try fixture.folderWithFile("\(fixture.systemPath)/Library/Extensions/com.example.MyApp.kext")
        let usrLocal = try fixture.folderWithFile("\(fixture.systemPath)/usr/local/bin/com.example.MyApp")
        let receipts = try fixture.folderWithFile("\(fixture.systemPath)/private/var/db/receipts")
        try fixture.writeFile(receipts + "/com.example.MyApp.plist")

        for level in ResidualSensitivity.allCases {
            let report = scan(fixture, appPath: app, sensitivity: level, includeSystem: true)
            let hits = report.items.map(\.path)
            XCTAssertTrue(hits.contains(extensions) == false, "\(level.label) 档不应扫 Extensions")
            XCTAssertTrue(hits.contains(usrLocal) == false, "\(level.label) 档不应扫 /usr/local")
            XCTAssertTrue(hits.contains(receipts) == false, "\(level.label) 档不应扫 receipts")
            XCTAssertTrue(hits.contains { $0.contains("/var/db/receipts") } == false)
        }
        // 系统域的合法条目（Preferences）确实在扫，证明上面三条是"被排除"而不是"没扫系统域"。
        let preference = try fixture.libraryFolder("Preferences", under: fixture.systemRoot)
        try fixture.writePlist(preference + "/com.example.MyApp.plist", ["a": 1])
        let hits = scan(fixture, appPath: app, sensitivity: .strict, includeSystem: true).items.map(\.path)
        XCTAssertTrue(hits.contains(preference + "/com.example.MyApp.plist"))
    }

    /// 命中项必须带上可读的证据与类别，UI 才有的展示。
    func testItemsCarryEvidenceAndCategory() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        try fixture.folderWithFile(try fixture.libraryFolder("Caches/com.example.MyApp"))
        let report = scan(fixture, appPath: app, sensitivity: .strict)
        XCTAssertFalse(report.items.isEmpty)
        for item in report.items {
            XCTAssertFalse(item.reason.isEmpty, "\(item.path) 没有命中证据")
            XCTAssertTrue(item.displayPath.hasPrefix("~/Library"), "展示路径应相对 home 缩写：\(item.displayPath)")
        }
        XCTAssertTrue(report.items.allSatisfy { $0.category == .cache } || report.items.contains { $0.category == .cache })
    }
}
