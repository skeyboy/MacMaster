import XCTest
import Foundation
@testable import MMUninstaller

/// 措辞合同：这一族的边界是"只说我们量到的那一个脚本"。
/// 基准在设计稿 `docs/design-system/screens/mmuninstaller/03g-uninstaller-steam-launcher.html`，
/// 而**不许说什么**由 `docs/analysis/uninstaller-steam-launcher.md` §5.3 定：
/// 我们只读那一份启动脚本，没按游戏逐个认，所以既不能说某款游戏有多大，也不能说这里没有游戏。
/// 另一头的边界由照片 `docs/verification/p32b-steam/06-steam-self-caveat.png` 定：
/// 同一屏的残留行会给出游戏容器的体积与"内含 steamapps"，所以依据里也不能反过来说
/// "这一页说不出游戏在哪"——那是一句被自己画面证伪的话。
final class SteamLauncherPresentationTests: XCTestCase {

    private func candidate(_ launcher: SteamLauncherInfo?) -> UninstallCandidate {
        UninstallCandidate(id: "/Applications/SteamGame.app", name: "SteamGame",
                           bundleName: "SteamGame", path: "/Applications/SteamGame.app",
                           bundleID: "com.example.SteamGame", version: "1.0", build: "1",
                           minSystemVersion: "14.0", executable: "SteamGame", developer: "", teamID: "",
                           modificationDate: nil, steamLauncher: launcher)
    }

    private func launcher(_ appID: String = "220", verb: SteamLaunchVerb = .run,
                          name: String = "SteamGame",
                          source: LauncherScriptSnapshot.Source = .bundleExecutable) -> SteamLauncherInfo {
        SteamLauncherInfo(appID: appID, verb: verb, scriptName: name, scriptSource: source)
    }

    // MARK: 不成立就一个字不说

    func testNothingAppearsWhenNotRecognised() {
        let app = candidate(nil)
        XCTAssertNil(app.steamLauncherChip)
        XCTAssertNil(app.steamLauncherBadge)
        XCTAssertNil(app.steamLauncherValue)
        XCTAssertNil(app.steamLauncherBasis)
    }

    // MARK: 成立时说的话

    func testValueNamesScriptAndAppID() {
        let app = candidate(launcher())
        XCTAssertEqual(app.steamLauncherValue, "Steam 生成的启动脚本 · SteamGame（appid 220）")
        XCTAssertEqual(app.steamLauncherChip?.text, "启动器")
        XCTAssertEqual(app.steamLauncherBadge?.text, "Steam 启动器")
    }

    /// 判定依据里必须能认出凭据本身：脚本名、动词、appid。
    func testBasisQuotesTheEvidence() throws {
        let app = candidate(launcher("440", verb: .launch, name: SteamLauncherProbe.fixedScriptName,
                                     source: .fixedName))
        let basis = try XCTUnwrap(app.steamLauncherBasis)
        XCTAssertTrue(basis.contains("Contents/MacOS/run.sh"))
        XCTAssertTrue(basis.contains("open steam://launch/440"))
        XCTAssertTrue(basis.contains(String(SteamLauncherProbe.maxScriptBytes)))
    }

    /// §5.3 的那条线：只能说"大小量的是启动器"，不能替游戏目录说话。
    func testBasisStaysInsideTheEvidence() throws {
        let basis = try XCTUnwrap(candidate(launcher()).steamLauncherBasis)
        XCTAssertTrue(basis.contains("量的就是启动器本身"))
        XCTAssertTrue(basis.contains("没有按游戏逐个认"))
        for forbidden in ["GB", "MB", "没有你的游戏", "游戏在", "不含游戏", "说不出它们在哪"] {
            XCTAssertFalse(basis.contains(forbidden), "「\(forbidden)」越过了证据：我们只读了那一份脚本")
        }
    }

    /// 与「来源」正交：brew 装的启动器两句同时成立，谁也不覆盖谁。
    func testCoexistsWithProvenance() {
        let app = UninstallCandidate(id: "/Applications/SteamGame.app", name: "SteamGame",
                                     bundleName: "SteamGame", path: "/Applications/SteamGame.app",
                                     bundleID: "com.example.SteamGame", version: "1.0", build: "1",
                                     minSystemVersion: "14.0", executable: "SteamGame",
                                     developer: "", teamID: "", modificationDate: nil,
                                     provenance: AppProvenance(source: .homebrewCask,
                                                               cask: CaskEvidence(token: "steam-game",
                                                                                  version: nil,
                                                                                  installedAt: nil,
                                                                                  tap: nil,
                                                                                  installedOnRequest: nil,
                                                                                  receiptPath: "/opt/homebrew/Caskroom/steam-game/.metadata/INSTALL_RECEIPT.json",
                                                                                  zapEntryCount: 0,
                                                                                  declaredAppNames: ["steam-game.app"])),
                                     steamLauncher: launcher())
        XCTAssertEqual(app.sourceChip?.text, "brew")
        XCTAssertEqual(app.steamLauncherChip?.text, "启动器")
        XCTAssertNotNil(app.sourceBadge)
        XCTAssertNotNil(app.steamLauncherBadge)
    }
}
