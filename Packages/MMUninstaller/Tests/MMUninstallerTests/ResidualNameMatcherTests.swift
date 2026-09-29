import Foundation
import XCTest
@testable import MMUninstaller

/// 归一化名称匹配：`"My App"` / `"my-app"` / `"MyApp"` 命中同一个 bundle。
final class ResidualNameMatcherTests: XCTestCase {

    func testNormalizeUnifiesSeparatorsAndCase() {
        XCTAssertEqual(ResidualNameMatcher.normalize("My App"), "my-app")
        XCTAssertEqual(ResidualNameMatcher.normalize("my-app"), "my-app")
        XCTAssertEqual(ResidualNameMatcher.normalize("My.App"), "my-app")
        XCTAssertEqual(ResidualNameMatcher.normalize("My_App"), "my-app")
        XCTAssertEqual(ResidualNameMatcher.normalize("MyApp"), "myapp")
        XCTAssertEqual(ResidualNameMatcher.compress(ResidualNameMatcher.normalize("My App")),
                       ResidualNameMatcher.compress(ResidualNameMatcher.normalize("MyApp")))
    }

    func testThreeSpellingsHitTheSameBundle() {
        let matcher = ResidualNameMatcher(appName: "My App", bundleID: "com.example.MyApp")
        for spelling in ["My App", "my-app", "MyApp", "MY_APP", "My.App"] {
            let url = URL(fileURLWithPath: "/tmp/Library/Application Support/\(spelling)")
            XCTAssertNotNil(matcher.reason(for: url, bundleID: "com.example.MyApp", allowContains: false),
                            "\(spelling) 应在严格档命中同一个包")
        }
    }

    /// 反向 DNS 名的最后一段不是扩展名。`deletingPathExtension()` 会把
    /// `com.example.MyApp` 削成 `com.example`，于是"包名完全对应"这条最硬的证据永远不成立。
    func testReverseDNSNameKeepsItsLastSegment() {
        let matcher = ResidualNameMatcher(appName: "My App", bundleID: "com.example.MyApp")
        let cache = URL(fileURLWithPath: "/tmp/Library/Caches/com.example.MyApp")
        XCTAssertEqual(matcher.reason(for: cache, bundleID: "com.example.MyApp", allowContains: false),
                       "包名完全对应")
        // 真扩展名仍然要剥掉，否则 .app / .plist 一律对不上。
        let app = URL(fileURLWithPath: "/Applications/My App.app")
        XCTAssertNotNil(matcher.reason(for: app, bundleID: "com.example.MyApp", allowContains: false))
    }

    /// 一个半截包名不能靠子串命中别人的容器。
    func testGroupContainerIdentifierNeedsBoundaryNotSubstring() {
        XCTAssertTrue(ContainerScanner.identifiersMatch("group.com.example.MyApp",
                                                        bundleID: "com.example.MyApp"))
        XCTAssertTrue(ContainerScanner.identifiersMatch("group.com.example.MyApp.data",
                                                        bundleID: "com.example.MyApp"))
        XCTAssertFalse(ContainerScanner.identifiersMatch("group.com.example.OtherApp",
                                                         bundleID: "com.example.MyApp"))
        // 旧写法是 normalize 后 contains，"com.examp" 这种半截名会命中别人。
        XCTAssertFalse(ContainerScanner.identifiersMatch("group.com.example.myappsuite",
                                                         bundleID: "com.example.MyApp"))
    }

    func testUnrelatedNameDoesNotMatch() {
        let matcher = ResidualNameMatcher(appName: "My App", bundleID: "com.example.MyApp")
        let url = URL(fileURLWithPath: "/tmp/Library/Application Support/Other Thing")
        XCTAssertNil(matcher.reason(for: url, bundleID: "com.example.MyApp", allowContains: false))
    }

    /// 严格档拒绝"包含"关系，增强档接受 —— 敏感度不是装饰。
    func testContainsRuleIsGatedBySensitivity() {
        let matcher = ResidualNameMatcher(appName: "My App", bundleID: "com.example.MyApp")
        let url = URL(fileURLWithPath: "/tmp/Library/Caches/Example My App Extra")
        XCTAssertNil(matcher.reason(for: url, bundleID: "com.example.MyApp", allowContains: false))
        XCTAssertNotNil(matcher.reason(for: url, bundleID: "com.example.MyApp", allowContains: true))
    }

    func testBundleIDPrefixAndDerivedIdentifiers() {
        let matcher = ResidualNameMatcher(appName: "My App", bundleID: "com.example.MyApp")
        XCTAssertNotNil(matcher.reason(for: URL(fileURLWithPath: "/t/com.example.MyApp.plist"),
                                       bundleID: "com.example.MyApp", allowContains: false))
        XCTAssertNotNil(matcher.reason(for: URL(fileURLWithPath: "/t/com.example.MyApp.Helper.plist"),
                                       bundleID: "com.example.MyApp", allowContains: false))
        // 同前缀但不是同一个包：不能因为字符串前缀相同就误收别人的数据。
        XCTAssertNil(matcher.reason(for: URL(fileURLWithPath: "/t/com.example.MyAppSuite.plist"),
                                    bundleID: "com.example.MyApp", allowContains: false))
    }

    /// plist 文件名不含包名时，内容里的标识才是证据（用 PropertyListSerialization 读）。
    func testPlistContentIdentifierIsEvidence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMMatcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let own = directory.appendingPathComponent("random-byhost-name.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["ByHostIdentifier": "com.example.MyApp"], format: .binary, options: 0)
        try data.write(to: own)

        let matcher = ResidualNameMatcher(appName: "My App", bundleID: "com.example.MyApp")
        let reason = matcher.reason(for: own, bundleID: "com.example.MyApp", allowContains: false)
        XCTAssertNotNil(reason, "内容指向本包名的偏好文件应被命中")
        XCTAssertTrue(reason!.contains("偏好文件"))
    }

    /// 空包名时不能退化成"什么都像"，名称证据仍然要求严格对应。
    func testEmptyBundleIDStillRequiresExactName() {
        let matcher = ResidualNameMatcher(appName: "My App", bundleID: "")
        XCTAssertNotNil(matcher.reason(for: URL(fileURLWithPath: "/t/My App"), bundleID: "", allowContains: false))
        XCTAssertNil(matcher.reason(for: URL(fileURLWithPath: "/t/Example My App Extra"),
                                    bundleID: "", allowContains: false))
    }
}
