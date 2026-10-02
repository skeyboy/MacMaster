import XCTest
import Foundation
@testable import MMUninstaller

/// 呈现层的测试只盯一件事：**措辞不能越过证据**。
/// 文案合同是 `docs/design-system/screens/mmuninstaller/03d-uninstaller-provenance.html`
/// 第三块那张表，这里钉住的是最容易在改文案时悄悄失守的几条线。
final class AppProvenancePresentationTests: XCTestCase {

    private func candidate(_ provenance: AppProvenance, name: String = "Highball",
                           path: String = "/Applications/Highball.app") -> UninstallCandidate {
        UninstallCandidate(id: path, name: name, bundleName: name, path: path,
                           bundleID: "com.example.\(name)", version: "1.0", build: "1",
                           minSystemVersion: "14.0", executable: name, developer: "", teamID: "",
                           modificationDate: nil, provenance: provenance)
    }

    private func cask(token: String = "highball", version: String? = "0.9.39", tap: String? = "homebrew/cask") -> CaskEvidence {
        CaskEvidence(token: token, version: version, installedAt: nil, tap: tap,
                     installedOnRequest: nil,
                     receiptPath: "/opt/homebrew/Caskroom/\(token)/.metadata/INSTALL_RECEIPT.json",
                     zapEntryCount: 0, declaredAppNames: ["highball.app"])
    }

    // MARK: 没有凭据就不许说成有

    func testUnknownNeverSaysManualInstall() {
        let app = candidate(.unknown)
        XCTAssertEqual(app.sourceValue, "无法判定")
        XCTAssertNil(app.sourceBadge)
        XCTAssertNil(app.sourceChip)
        XCTAssertNil(app.sourceReceipt)
        XCTAssertNil(app.sourceCommand)
        XCTAssertNil(app.sourceWarning)
        XCTAssertTrue(app.sourceBasis.contains("不等于「手动安装」"))
    }

    func testAmbiguousNamesBothTokensInsteadOfPickingOne() {
        let app = candidate(AppProvenance(source: .unknown, ambiguousCaskTokens: ["firefox", "firefox-beta"]))
        XCTAssertEqual(app.sourceValue, "无法判定（两个 cask 都声明了这个名字：firefox、firefox-beta）")
        XCTAssertTrue(app.sourceBasis.contains("不替用户挑第一个"))
    }

    /// 两份账本抢同一个 bundle 时，事实比"名字撞上"强得多，文案不能退成同一句。
    func testAmbiguityFromDeviceIdentitySaysSo() {
        let app = candidate(AppProvenance(source: .unknown, ambiguousCaskTokens: ["firefox", "firefox-beta"],
                                          ambiguousByDeviceIdentity: true))
        XCTAssertEqual(app.sourceValue, "无法判定（firefox、firefox-beta 两份账本把同一个 .app 摆到了这里）")
        XCTAssertTrue(app.sourceBasis.contains("设备号 + inode 相同"))
        XCTAssertFalse(app.sourceBasis.contains("不替用户挑第一个"))
    }

    // MARK: 只有强证据才配得上命令

    func testCommandOnlyForDeviceVerifiedCask() {
        let strong = candidate(AppProvenance(source: .homebrewCask, cask: cask()))
        XCTAssertEqual(strong.sourceCommand, "brew uninstall --cask highball")
        let nameOnly = candidate(AppProvenance(source: .homebrewCaskNameOnly, cask: cask(token: "codeedit")))
        XCTAssertNil(nameOnly.sourceCommand, "名字对上就推荐一条会改动系统状态的命令，是本页最贵的一种错")
    }

    func testNameOnlySaysSoInItsOwnHeadline() {
        let app = candidate(AppProvenance(source: .homebrewCaskNameOnly, cask: cask(token: "codeedit")))
        XCTAssertEqual(app.sourceValue, "可能是 Homebrew cask · codeedit（只有名字对上）")
        XCTAssertEqual(app.sourceChip?.text, "疑似 brew")
        XCTAssertNotNil(app.sourceWarning)
    }

    func testStrongCaskReadsAsVerified() {
        let app = candidate(AppProvenance(source: .homebrewCask, cask: cask()))
        XCTAssertEqual(app.sourceValue, "Homebrew cask · highball 0.9.39（tap homebrew/cask）")
        XCTAssertEqual(app.sourceChip?.text, "brew")
        XCTAssertEqual(app.sourceBadge?.text, "Homebrew cask · highball")
        XCTAssertTrue(app.sourceWarning?.contains("MacMaster 不会代你运行 brew") ?? false)
        XCTAssertTrue(app.sourceWarning?.contains("/Applications/Highball.app") ?? false)
    }

    func testMissingOptionalEvidenceDegradesCopyInsteadOfPrintingNil() {
        let app = candidate(AppProvenance(source: .homebrewCask, cask: cask(version: nil, tap: nil)))
        XCTAssertEqual(app.sourceValue, "Homebrew cask · highball")
    }

    // MARK: 列表那一格只留给会改变动作的来源

    func testAppStoreAndPackageSourcesStayOutOfTheList() {
        let mas = candidate(AppProvenance(source: .appStore))
        XCTAssertNil(mas.sourceChip)
        XCTAssertEqual(mas.sourceBadge?.text, "App Store")
        XCTAssertEqual(mas.sourceValue, "Mac App Store")
        XCTAssertNil(mas.sourceWarning, "App Store 装的应用被删不会让任何账本失真，不该拿警告色吓人")

        let pkg = candidate(AppProvenance(source: .installerPackage, packageIdentifier: "cn.i4tools.mac"))
        XCTAssertNil(pkg.sourceChip)
        XCTAssertEqual(pkg.sourceValue, "安装包 · cn.i4tools.mac")
        XCTAssertNil(pkg.sourceReceipt)
    }
}
