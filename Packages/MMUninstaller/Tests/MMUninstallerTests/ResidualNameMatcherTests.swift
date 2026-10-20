import Foundation
import XCTest
import MMCore
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
            XCTAssertNotNil(matcher.evidence(for: url, bundleID: "com.example.MyApp", allowContains: false),
                            "\(spelling) 应在严格档命中同一个包")
        }
    }

    /// 反向 DNS 名的最后一段不是扩展名。`deletingPathExtension()` 会把
    /// `com.example.MyApp` 削成 `com.example`，于是"包名完全对应"这条最硬的证据永远不成立。
    func testReverseDNSNameKeepsItsLastSegment() {
        let matcher = ResidualNameMatcher(appName: "My App", bundleID: "com.example.MyApp")
        let cache = URL(fileURLWithPath: "/tmp/Library/Caches/com.example.MyApp")
        XCTAssertEqual(matcher.evidence(for: cache, bundleID: "com.example.MyApp", allowContains: false)?.kind,
                       .identifierExact)
        // 真扩展名仍然要剥掉，否则 .app / .plist 一律对不上。
        let app = URL(fileURLWithPath: "/Applications/My App.app")
        XCTAssertNotNil(matcher.evidence(for: app, bundleID: "com.example.MyApp", allowContains: false))
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
        XCTAssertNil(matcher.evidence(for: url, bundleID: "com.example.MyApp", allowContains: false))
    }

    /// 严格档拒绝"包含"关系，增强档接受 —— 敏感度不是装饰。
    func testContainsRuleIsGatedBySensitivity() {
        let matcher = ResidualNameMatcher(appName: "My App", bundleID: "com.example.MyApp")
        let url = URL(fileURLWithPath: "/tmp/Library/Caches/Example My App Extra")
        XCTAssertNil(matcher.evidence(for: url, bundleID: "com.example.MyApp", allowContains: false))
        XCTAssertNotNil(matcher.evidence(for: url, bundleID: "com.example.MyApp", allowContains: true))
    }

    func testBundleIDPrefixAndDerivedIdentifiers() {
        let matcher = ResidualNameMatcher(appName: "My App", bundleID: "com.example.MyApp")
        XCTAssertNotNil(matcher.evidence(for: URL(fileURLWithPath: "/t/com.example.MyApp.plist"),
                                         bundleID: "com.example.MyApp", allowContains: false))
        XCTAssertNotNil(matcher.evidence(for: URL(fileURLWithPath: "/t/com.example.MyApp.Helper.plist"),
                                         bundleID: "com.example.MyApp", allowContains: false))
        // 同前缀但不是同一个包：不能因为字符串前缀相同就误收别人的数据。
        XCTAssertNil(matcher.evidence(for: URL(fileURLWithPath: "/t/com.example.MyAppSuite.plist"),
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
        let evidence = matcher.evidence(for: own, bundleID: "com.example.MyApp", allowContains: false)
        XCTAssertNotNil(evidence, "内容指向本包名的偏好文件应被命中")
        XCTAssertEqual(evidence?.kind, .plistOwner)
    }

    /// 空包名时不能退化成"什么都像"，名称证据仍然要求严格对应。
    func testEmptyBundleIDStillRequiresExactName() {
        let matcher = ResidualNameMatcher(appName: "My App", bundleID: "")
        XCTAssertNotNil(matcher.evidence(for: URL(fileURLWithPath: "/t/My App"), bundleID: "", allowContains: false))
        XCTAssertNil(matcher.evidence(for: URL(fileURLWithPath: "/t/Example My App Extra"),
                                     bundleID: "", allowContains: false))
    }

    /// `kind` 管「是什么证据」，这一条管「那句话确实取得到中文原话」——03b 的文案合同。
    /// 当场把语言钉成中文：`MM_LANGUAGE` 会写回 UserDefaults（见 `Localization`），
    /// 不钉的话这一条会因为上一张双语照片留下的档位而假绿或假红。
    func testEvidenceTextKeepsTheChineseWording() {
        let key = "app.language"   // `Localization.storageKey`，那边是 private
        let saved = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(Localization.Language.chinese.rawValue, forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        XCTAssertEqual(ResidualEvidenceKind.identifierExact.text([]), "包名完全对应")
        XCTAssertEqual(ResidualEvidenceKind.plistOwner.text(["com.example.MyApp"]),
                       "偏好文件，内容标识 com.example.MyApp")
        // 带参的那一句会再被「位于哪一层里」包一层：这里同时钉住两处取值——
        // 数组被当成单个参数时，`%@` 印的是 NSArray 字面量，而多占位符的第二格是 `(null)`。
        XCTAssertEqual(ResidualEvidence(.plistOwner, "com.example.MyApp").found(inside: "IDEFoo").text,
                       "偏好文件，内容标识 com.example.MyApp（位于 IDEFoo 内）")
    }
}
