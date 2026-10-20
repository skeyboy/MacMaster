import XCTest
import Foundation
import MMCore
@testable import MMUninstaller

/// P33b B 档「归属复核」的正反判据。
///
/// 钉住的是这一族：归属证据只有「名称包含应用名」，而**别人对它有更强的主张**。两条线索各管一族：
///   · 这一项本身被另一个已装应用以硬证据主张（`Caches/com.example.steamgame` 归 SteamGame）；
///   · 它的某个上层目录被另一个已安装应用主张（`JetBrains/IntelliJIdea2026.2/ts-go-fork-embedded`）。
/// 复核只改默认勾选（safe → caution）并把主人写进行下方那句提醒，**不减少召回**——
/// 条目还在清单里、还能手动勾选，所以每一档都有一条"必须仍然是候选"的断言。
///
/// 夹具形状取自 P33a 审计：§3 的本机实测是祖先那一族（`~/Library/Caches/JetBrains/
/// IntelliJIdea2026.2/ts-go-fork-embedded` 默认勾选，而真主人主张的是它的父目录），
/// §4 的夹具形态是同层那一族（`Caches/com.example.steamgame` 被归到 Steam 名下、524 KB、默认勾选，
/// 它的上层只有 `Caches`、谁都不主张）——只做祖先那一层的话，后一族一个字都不会说，
/// 所以两条线索各自有正反判据钉住。
final class ResidualOwnershipReviewTests: XCTestCase {
    private var fixture: ResidualFixture!

    override func setUpWithError() throws {
        fixture = try ResidualFixture(caseName: name)
    }

    override func tearDown() {
        fixture?.cleanup()
        fixture = nil
    }

    /// 被扫描的那个应用：`Fork`。应用名压缩后正好 4 个字符，是包含匹配的最短允许长度，
    /// 所以"上层目录里别的产品名带着 fork 这个词"这种撞名形态能稳定复现。
    private let scannedApp = "Fork"
    private let scannedID = "com.example.fork"
    private static let ideFoo = InstalledAppIdentity(name: "IDEFoo", bundleID: "com.example.idefoo")
    private static let assetsFoo = InstalledAppIdentity(name: "AssetsFork", bundleID: "com.example.assetsfork")

    private func scan(_ sensitivity: ResidualSensitivity,
                      foreign: [InstalledAppIdentity],
                      appName: String? = nil,
                      bundleID: String? = nil) throws -> ResidualScanReport {
        let target = appName ?? scannedApp
        let id = bundleID ?? scannedID
        let appPath = try fixture.makeApp(name: target, bundleID: id)
        let options = ResidualScanOptions(home: fixture.homePath, sensitivity: sensitivity,
                                          foreignApps: foreign)
        return ResidualScanner.scan(appName: target, bundleID: id, appPath: appPath,
                                    options: options, measure: ResidualFixture.constantMeasure)
    }

    private struct MissingItem: Error { let suffix: String }

    private func item(_ report: ResidualScanReport, suffix: String) throws -> ResidualItem {
        if let found = report.items.first(where: { $0.path.hasSuffix(suffix) }) { return found }
        XCTFail("清单里没有 \(suffix)：\(report.items.map(\.displayPath))")
        throw MissingItem(suffix: suffix)
    }

    // MARK: 正判据

    /// 包含匹配 + 上层目录归别人：降为谨慎、不默认勾选、提醒里点名主人，证据串本身不动。
    func testContainmentUnderForeignAncestorBecomesCaution() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/IDEFoo/AssetsFork")
        let report = try scan(.enhanced, foreign: [Self.ideFoo])
        let hit = try item(report, suffix: "Caches/IDEFoo/AssetsFork")

        XCTAssertEqual(hit.risk, .caution)
        XCTAssertFalse(hit.risk.isDefaultSelected)
        XCTAssertEqual(report.defaultSelectableCount, 0)
        XCTAssertEqual(report.defaultSelectableSize, 0)
        // 证据仍是"名称包含应用名"那一句：降级不重写证据，主人的名字进行下方那句提醒。
        XCTAssertTrue(hit.reason.hasPrefix("名称包含应用名"), hit.reason)
        let caveat = try XCTUnwrap(hit.caveat)
        XCTAssertTrue(caveat.contains("上层目录归 IDEFoo"), caveat)
        XCTAssertTrue(caveat.contains("~/Library/Caches/IDEFoo"), caveat)
        XCTAssertTrue(caveat.contains("可能不是 \(scannedApp) 的数据"), caveat)
    }

    /// 降级这件事不能建立在"中文句子长得像"上：把语言钉成英文跑同一族夹具，
    /// `risk`、默认勾选数与提醒的有无必须一个都不变。这一条是 P58 接两语时补的判据——
    /// 复核的输入是 `evidenceKind`，不是证据文本，所以它翻档以后照样降。
    func testReviewDecisionDoesNotDependOnTheWording() throws {
        let key = "app.language"   // `Localization.storageKey`，那边是 private
        let saved = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(Localization.Language.english.rawValue, forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/IDEFoo/AssetsFork")
        let report = try scan(.enhanced, foreign: [Self.ideFoo])
        let hit = try item(report, suffix: "Caches/IDEFoo/AssetsFork")

        XCTAssertEqual(hit.risk, .caution)
        XCTAssertFalse(hit.risk.isDefaultSelected)
        XCTAssertEqual(report.defaultSelectableCount, 0)
        XCTAssertEqual(report.defaultSelectableSize, 0)
        // 证据取自表，不是硬编码：英文档必须以英文表里那一条开头。全等不行——
        // 下探厂商目录的那一路会在同一句后面补「位于哪一层里」（`ui.evidence.inside`）。
        XCTAssertTrue(hit.reason.hasPrefix(L("ui.evidence.name_contains")), hit.reason)
        let caveat = try XCTUnwrap(hit.caveat)
        XCTAssertTrue(caveat.contains("IDEFoo"), caveat)
        XCTAssertTrue(caveat.contains("~/Library/Caches/IDEFoo"), caveat)
    }

    /// 复核对档位不偏心：深度档同样降。
    func testReviewAppliesAtDeepTier() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/IDEFoo/AssetsFork")
        let report = try scan(.deep, foreign: [Self.ideFoo])
        XCTAssertEqual(try item(report, suffix: "AssetsFork").risk, .caution)
    }

    /// 只走到**第一个**有主人的祖先：两层各有主人时，提醒写的是最近那一层。
    func testNearestOwnedAncestorWins() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/IDEFoo/SharedKit/ForkAssets")
        let report = try scan(.deep, foreign: [
            InstalledAppIdentity(name: "SharedKit", bundleID: "com.example.sharedkit"), Self.ideFoo,
        ])
        let caveat = try XCTUnwrap(try item(report, suffix: "ForkAssets").caveat)
        XCTAssertTrue(caveat.contains("上层目录归 SharedKit"), caveat)
        // 更外层的 IDEFoo 会作为**路径的一段**出现在提醒里，但它不该是那句"归谁"的主人。
        XCTAssertFalse(caveat.contains("上层目录归 IDEFoo"), caveat)
        XCTAssertFalse(caveat.contains("这一项本身归"), caveat)
    }

    /// 同层那一族（P33a 审计 §4 的夹具形态）：弱证据项的名字正是另一个已装应用的包名，
    /// 而它的上层只有 `Caches`——祖先那条线索在这族上永远不成立，所以这条判据必须独立成立。
    /// 这一条就是 `Caches/com.example.steamgame` 被归到 Steam 名下、524 KB、默认勾选那一幕的形状。
    func testSameLevelBundleIdClaimBecomesCaution() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/com.example.steamgame")
        let report = try scan(.enhanced,
                              foreign: [InstalledAppIdentity(name: "SteamGame",
                                                             bundleID: "com.example.steamgame")],
                              appName: "Steam", bundleID: "com.valvesoftware.Steam")
        let hit = try item(report, suffix: "Caches/com.example.steamgame")

        XCTAssertTrue(hit.reason.hasPrefix("名称包含应用名"), hit.reason)
        XCTAssertEqual(hit.risk, .caution)
        XCTAssertFalse(hit.risk.isDefaultSelected)
        let caveat = try XCTUnwrap(hit.caveat)
        XCTAssertTrue(caveat.contains("这一项本身归 SteamGame"), caveat)
        // 别人的证据串原样带出，用户能看到"凭什么归它"。
        XCTAssertTrue(caveat.contains("包名完全对应"), caveat)
        XCTAssertFalse(caveat.contains("上层目录归"), caveat)
    }

    /// 两条线索同时成立时，写的是**离这一项更近**的那条：同层硬证据不用再绕到祖先。
    func testSameLevelClaimWinsOverAncestor() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/IDEFoo/AssetsFork")
        let report = try scan(.enhanced, foreign: [Self.assetsFoo, Self.ideFoo])
        let caveat = try XCTUnwrap(try item(report, suffix: "IDEFoo/AssetsFork").caveat)
        XCTAssertTrue(caveat.contains("这一项本身归 AssetsFork（名称与包名对应）"), caveat)
        XCTAssertFalse(caveat.contains("上层目录归 IDEFoo"), caveat)
    }

    /// 同层那一族也钉"仍要留在清单里"：降级只改勾选，不删行。
    func testSameLevelClaimKeepsTheRowInList() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/com.example.steamgame")
        let report = try scan(.enhanced,
                              foreign: [InstalledAppIdentity(name: "SteamGame",
                                                             bundleID: "com.example.steamgame")],
                              appName: "Steam", bundleID: "com.valvesoftware.Steam")
        XCTAssertEqual(report.items.count, 1)
        XCTAssertTrue(report.items[0].path.hasSuffix("Caches/com.example.steamgame"))
    }

    // MARK: 反判据

    /// 上层目录没人主张（一路只有 `Caches`、`Library`）时不许降：
    /// 否则这条判据会把所有弱证据项一起抹掉，"默认勾选"就再无包含匹配命中的项可言。
    func testContainmentWithoutOwnedAncestorStaysSafe() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/SupportFork")
        let report = try scan(.enhanced, foreign: [Self.ideFoo])
        let hit = try item(report, suffix: "Caches/SupportFork")
        XCTAssertEqual(hit.risk, .safe)
        XCTAssertNil(hit.caveat)
    }

    /// 别的应用对这一项**也只有弱证据**时不许降：`ForkExtra` 对 `ForkExtras` 是包含匹配，
    /// 不构成主张——弱对弱只是两方一起猜，把它当证据就会把整族弱证据项一起抹掉。
    func testSameLevelWeakClaimIsNotAnOwner() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/ForkExtras")
        let report = try scan(.enhanced, foreign: [
            InstalledAppIdentity(name: "ForkExtra", bundleID: "com.example.forkextra"), Self.ideFoo,
        ])
        let hit = try item(report, suffix: "Caches/ForkExtras")
        XCTAssertEqual(hit.risk, .safe)
        XCTAssertNil(hit.caveat)
    }

    /// 包名级证据即使住在别人的目录里也不降：这条判据只管"证据到不了归属"那一族。
    func testHardEvidenceUnderForeignAncestorStaysSafe() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/IDEFoo/com.example.fork")
        let report = try scan(.enhanced, foreign: [Self.ideFoo])
        let hit = try item(report, suffix: "IDEFoo/com.example.fork")
        XCTAssertTrue(hit.reason.hasPrefix("包名完全对应"), hit.reason)
        XCTAssertEqual(hit.risk, .safe)
        XCTAssertNil(hit.caveat)
    }

    /// 本来就不默认勾选的类别（应用数据）不重复降级，也不加这句提醒：
    /// 这条判据管的是"默认勾选会拿走别人的东西"，谨慎档没有这个问题。
    func testAlreadyCautionCategoryGetsNoOwnershipCaveat() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Application Support/IDEFoo/AssetsFork")
        let report = try scan(.enhanced, foreign: [Self.ideFoo])
        let hit = try item(report, suffix: "AssetsFork")
        XCTAssertEqual(hit.risk, .caution)
        XCTAssertNil(hit.caveat)
    }

    /// 空名单 = 不复核，行为与 P33b 之前逐字相同（旧调用点与既有单测靠这一条不改写期望值）。
    func testEmptyForeignListKeepsOldBehavior() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/IDEFoo/AssetsFork")
        let report = try scan(.enhanced, foreign: [])
        let hit = try item(report, suffix: "AssetsFork")
        XCTAssertEqual(hit.risk, .safe)
        XCTAssertTrue(hit.risk.isDefaultSelected)
        XCTAssertNil(hit.caveat)
    }

    /// 严格档按构造拿不到包含匹配，所以复核在这一档无事可做——这一条是判据前提的否证，
    /// 不是装饰：`enumerate` 那道档位闸门（`allowContains`）要是被放开，这条会立刻变红。
    func testStrictTierHasNoContainmentHit() throws {
        try fixture.folderWithFile("\(fixture.homePath)/Library/Caches/IDEFoo/AssetsFork")
        let report = try scan(.strict, foreign: [Self.ideFoo])
        XCTAssertEqual(report.items.filter { $0.reason.hasPrefix("名称包含应用名") }.count, 0)
    }

    // MARK: 剔除自己

    /// 整张已装清单原样传进来，引擎负责把"待扫描的那一个"剔掉——按包名与归一化名称两条线索分别剔。
    ///
    /// 判据钉在这个函数上而不是端到端跑：自己一主张某一层，`enumerate` 就收下那一层并 `continue`，
    /// 下探根本到不了它的子项，所以"清单里有自己"这一条在扫描结果上无法与"没有自己"区分。
    func testReviewListDropsSelfByBothClues() {
        let options = ResidualScanOptions(home: "/tmp/mm-p33b-home", foreignApps: [
            InstalledAppIdentity(name: "Fork Suite", bundleID: "com.example.fork"),   // 同包名
            InstalledAppIdentity(name: "fork", bundleID: "com.other.something"),      // 同名（显示名写法）
            Self.ideFoo,
        ])
        let review = ResidualScanner.ownershipReview(for: options, appName: scannedApp, bundleID: scannedID)
        XCTAssertEqual(review?.foreign.map { $0.name }, ["IDEFoo"])
        XCTAssertEqual(review?.appName, scannedApp)
    }

    /// 名单空、或名单里只有自己：不给复核对象（等价于旧行为）。
    func testReviewIsNilWhenNothingForeign() {
        let empty = ResidualScanOptions(home: "/tmp/mm-p33b-home")
        XCTAssertNil(ResidualScanner.ownershipReview(for: empty, appName: scannedApp, bundleID: scannedID))

        let onlySelf = ResidualScanOptions(home: "/tmp/mm-p33b-home",
                                          foreignApps: [InstalledAppIdentity(name: scannedApp,
                                                                             bundleID: scannedID)])
        XCTAssertNil(ResidualScanner.ownershipReview(for: onlySelf, appName: scannedApp, bundleID: scannedID))
    }
}
