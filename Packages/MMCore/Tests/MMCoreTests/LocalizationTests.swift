//
//  LocalizationTests.swift — 多语言表自身的合同（P56）
//
//  `Localization.swift` 这张表在 P56 之前是死的：全站零调用点，所以没人知道它缺不缺键、
//  两语对不对等。接进消费者之后，这三件事变成会伤到用户的：
//  1. 少一条英文 → `localized` 回落中文，切了英文的界面里混着中文句子；
//  2. 写错一个 key → `L(_:)` 把 key 原样印到屏幕上（那是最难看的一种 bug）；
//  3. 占位符写 `%d` 而调用方传 Swift `Int` → 崩溃，而且只在切到那条文案时崩。
//  三条都能在这里钉死，所以钉死。
//
//  不测的：某一句中文写得好不好看。那是文案，不是合同。
//

import XCTest
@testable import MMCore

final class LocalizationTests: XCTestCase {

    /// `ui` 是 P57 给共享层（MMUI）和壳层留的那一档：前缀小写下划线，
    /// 正因为写成 `ui.action.reveal_folder` 而不是 `ui.action.revealFolder`，
    /// 下面那条键校验正则才抓得到——camelCase 会整批漏网。
    private static let prefixes = ["nav", "sidebar", "module", "storage", "memory",
                                   "risk", "category", "dashboard", "format", "panel", "ui"]

    // MARK: - 两语对等

    func testBothTablesHoldExactlyTheSameKeys() {
        let zh = Set(Localization.chinese.keys)
        let en = Set(Localization.english.keys)
        XCTAssertEqual(zh.subtracting(en), [], "中文有、英文没有：切英文时这一句会回落中文")
        XCTAssertEqual(en.subtracting(zh), [], "英文有、中文没有：这条键永远不会被中文档取到")
    }

    func testNoEmptyValues() {
        for (key, value) in Localization.chinese where value.trimmingCharacters(in: .whitespaces).isEmpty {
            XCTFail("中文表 \(key) 是空串")
        }
        for (key, value) in Localization.english where value.trimmingCharacters(in: .whitespaces).isEmpty {
            XCTFail("英文表 \(key) 是空串")
        }
    }

    /// 参数个数必须一致：调用方一次传 N 个，两边的格式串都得吃得下同样多个。
    func testPlaceholderCountMatchesAcrossLanguages() {
        for key in Localization.chinese.keys {
            let zhCount = Self.placeholderCount(Localization.chinese[key]!)
            let enCount = Self.placeholderCount(Localization.english[key]!)
            XCTAssertEqual(zhCount, enCount, "\(key)：中文 \(zhCount) 个占位符、英文 \(enCount) 个")
        }
    }

    /// 占位符只允许 `%@` 与 `%n$@`。这一条防的是 `%d` + Swift `Int`：
    /// 编到整数寄存器、按对象解引用，现场是崩溃或一坨指针，而它只在切语言那天才走到。
    func testPlaceholdersUseOnlyObjectForm() {
        for (language, table) in [("中文", Localization.chinese), ("英文", Localization.english)] {
            for (key, value) in table {
                for token in Self.placeholderTokens(value) where token.hasSuffix("@") == false {
                    XCTFail("\(language)表 \(key) 用了 \(token)：请改成 %@ 并由调用方传字符串")
                }
            }
        }
    }

    /// 英文表里混进汉字 = 这一句没翻。切了英文的页面上会出现半中半英。
    func testEnglishTableIsActuallyEnglish() {
        for (key, value) in Localization.english {
            XCTAssertFalse(value.hasHan, "\(key) 的英文文案里还有汉字：\(value)")
        }
    }

    // MARK: - 取文案那三条路

    /// 切语言会写 UserDefaults（见 `Localization` 那段注释：这是刻意的，钩子只在本进程
    /// 生效一次的设想会让每一屏都漏）。所以每一处翻转都得还回去，统一走这里。
    private func withLanguage(_ language: Localization.Language, _ body: () -> Void) {
        let localization = Localization.shared
        let saved = localization.currentLanguage
        localization.currentLanguage = language
        defer { localization.currentLanguage = saved }
        body()
    }

    func testKnownKeyResolvesInBothLanguages() {
        withLanguage(.chinese) {
            XCTAssertEqual(Localization.shared.localized("dashboard.card.recent"), "最近操作")
        }
        withLanguage(.english) {
            XCTAssertEqual(Localization.shared.localized("dashboard.card.recent"), "Recent Activity")
        }
    }

    /// 表里没这个 key 时 `L(_:)` 会把 key 原样交给界面——所以调用方给的回落值必须传到位。
    func testMissingKeyFallsBackToCallerWordingNotTheKey() {
        withLanguage(.chinese) {
            XCTAssertEqual(Localization.shared.localized("dashboard.definitely.not.a.key", or: "废纸篓"), "废纸篓")
            XCTAssertEqual(Localization.shared.localized("nav.dashboard", or: "不该出现"), "概览")
        }
    }

    func testFormattedSubstitutesEveryPositionalArgument() {
        withLanguage(.chinese) {
            XCTAssertEqual(Localization.shared.formatted("dashboard.recent.subtitleWithFailures", "3 分钟前", "12", "2"),
                           "3 分钟前 · 12 项 · 2 项失败")
        }
        withLanguage(.english) {
            XCTAssertEqual(Localization.shared.formatted("dashboard.recent.subtitleWithFailures", "3 min ago", "12", "2"),
                           "3 min ago · 12 items · 2 failed")
        }
    }

    /// 默认档必须是中文：满仓的既有测试断言的是中文原话，`MMFormat` 也在其中。
    /// 这一条红了意味着任何没设过语言的机器上，那些断言会集体变红。
    func testChineseIsTheDefaultWhenNothingIsStored() {
        let key = "app.language"   // `Localization.storageKey`，那边是 private
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(Localization.shared.currentLanguage, .chinese)
    }

    // MARK: - MM_LANGUAGE 启动钩子

    func testLaunchHookAcceptsBothChineseSpellings() {
        for raw in ["zh", "ZH", " zh-hans ", "zh-HANS"] {
            XCTAssertEqual(MMLaunchHook.resolveLanguage(raw: raw).selected, .chinese, raw)
            XCTAssertNil(MMLaunchHook.resolveLanguage(raw: raw).rejected, raw)
        }
    }

    func testLaunchHookAcceptsEnglish() {
        XCTAssertEqual(MMLaunchHook.resolveLanguage(raw: "en").selected, .english)
        XCTAssertEqual(MMLaunchHook.resolveLanguage(raw: " EN ").selected, .english)
    }

    /// 空值是"没给"，不是"非法"：不给就沿用当前档位，也不留痕。
    func testAbsentValueKeepsCurrentLanguageWithoutComplaining() {
        for raw in [nil, "", "   "] {
            let resolution = MMLaunchHook.resolveLanguage(raw: raw)
            XCTAssertNil(resolution.selected, "\(String(describing: raw))")
            XCTAssertNil(resolution.rejected, "\(String(describing: raw))")
        }
    }

    /// 带地区的写法（`zh-CN`）不吃是刻意的：系统里 `Locale.current` 的取值无穷多，
    /// 全吃就等于没人核对过拼写。非法值要交回调用方留痕，不能静默按中文跑。
    func testUnsupportedSpellingsAreRejectedNotSilentlyAccepted() {
        for raw in ["zh-CN", "zh-Hans-CN", "fr", "english", "1"] {
            let resolution = MMLaunchHook.resolveLanguage(raw: raw)
            XCTAssertNil(resolution.selected, raw)
            XCTAssertEqual(resolution.rejected, raw)
        }
    }

    // MARK: - 双语取证的留痕

    /// 留痕必须**说出用的是哪一档**：双语照片的机械判据是照片旁那一行日志，
    /// 而 `MM_LANGUAGE` 会写回 UserDefaults，所以"这一张忘了带变量"和"这一张是中文档"
    /// 在画面上长得一模一样。逐字断言 = 文案合同（改了措辞要连着改取证脚本）。
    func testAppliedNoteNamesTheLanguageAndTheKey() {
        XCTAssertEqual(Localization.appliedNote(.english),
                       "MM_LANGUAGE=en 已生效：界面按这一档取文案（已写入 UserDefaults 的 app.language）")
        XCTAssertEqual(Localization.appliedNote(.chinese),
                       "MM_LANGUAGE=zh-Hans 已生效：界面按这一档取文案（已写入 UserDefaults 的 app.language）")
    }

    // MARK: - 消费者写错 key

    /// 这一条防的是最难看的那类 bug：`L("dashbaord.card.recent")` 少一个字母，
    /// 屏幕上就多一行 `dashbaord.card.recent`。文案改了、文件改名了都会立刻在这里响。
    func testEveryKeyReferencedByTheShellExistsInBothTables() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MMCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // MMCore
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // 仓库根
        let consumers = ["Sources/MacMaster/MainWindow.swift",
                         "Sources/MacMaster/DashboardModel.swift",
                         "Packages/MMOptimizer/Sources/MMOptimizer/DashboardMetrics.swift",
                         "Packages/MMUI/Sources/MMUI/MMDesign.swift",
                         // P57：共享层另两面 + 壳层另两处。设置页那一族不在这里——
                         // 它整页还没接，把它的字面量纳进来只会让这条测试先响一轮无关的。
                         "Packages/MMUI/Sources/MMUI/TreemapView.swift",
                         "Sources/MacMaster/LaunchBehavior.swift",
                         "Sources/MacMaster/MacMasterApp.swift",
                         // P58：卸载页整页接进两语，这一族的八个文件全部纳入键校验。
                         // 证据那一路（`ResidualNameMatcher` / `ResidualScanner`）也在这儿：
                         // 命中证据的文案是数据层吐的，键写错不会有编译错误，只会把键印到屏幕上。
                         "Packages/MMUninstaller/Sources/MMUninstaller/AppFolderWatcher.swift",
                         "Packages/MMUninstaller/Sources/MMUninstaller/LaunchServiceScanner.swift",
                         "Packages/MMUninstaller/Sources/MMUninstaller/MMUninstaller.swift",
                         "Packages/MMUninstaller/Sources/MMUninstaller/ResidualCollector.swift",
                         "Packages/MMUninstaller/Sources/MMUninstaller/ResidualNameMatcher.swift",
                         "Packages/MMUninstaller/Sources/MMUninstaller/ResidualScanner.swift",
                         "Packages/MMUninstaller/Sources/MMUninstaller/SteamLauncherProbe.swift",
                         "Packages/MMUninstaller/Sources/MMUninstaller/TrashWatcher.swift"]
        var checked = 0
        for relative in consumers {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            for key in Self.referencedKeys(in: text) {
                XCTAssertTrue(Localization.chinese[key] != nil || Localization.english[key] != nil,
                              "\(relative) 引用了表里没有的键：\(key)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 40, "一条都没扫到说明正则过期了，这条测试已经失去意义")
    }

    // MARK: - helpers

    /// `%@`、`%1$@`、以及要被抓出来的 `%d`/`%s`/`%%`。
    private static func placeholderTokens(_ format: String) -> [String] {
        let pattern = "%[0-9]*\\$?[^%]"
        return matches(in: format, pattern: pattern)
    }

    private static func placeholderCount(_ format: String) -> Int {
        placeholderTokens(format).filter { $0 != "%%" }.count
    }

    /// 扫源码里的字符串字面量，只留"像我们这套键"的那些：`a.b.c` 且首段在白名单里。
    /// 带插值的动态键（`"module.\(id)"`、`"category.\(id)"`）不吃——它们靠 `L(_:or:)` 回落，
    /// 键集是数据层的 id，不在这里穷举。
    private static func referencedKeys(in text: String) -> Set<String> {
        Set(matches(in: text, pattern: "\"([a-z][a-z0-9_]*(?:\\.[a-z0-9_]+)+)\"")
            .compactMap { literal -> String? in
                let key = String(literal.dropFirst().dropLast())
                guard prefixes.contains(key.split(separator: ".").first.map(String.init) ?? "") else { return nil }
                return key
            })
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

private extension String {
    /// 中日韩统一表意文字的主区段——英文表里出现它就只能是没翻的那句。
    var hasHan: Bool {
        unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
}
