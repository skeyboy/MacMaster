import XCTest
import Foundation
@testable import MMUninstaller

/// 呈现层的测试只盯两件事：**措辞不能越过证据**，以及**不许暗示我们会代用户退出应用**。
/// 文案合同是 `docs/design-system/screens/mmuninstaller/03f-uninstaller-running.html`
/// 那三块（列表行、详情「运行状态」、确认面板提醒）。
final class RunningAppStatePresentationTests: XCTestCase {

    private func candidate(name: String = "Foo", path: String = "/Applications/Foo.app",
                           bundleID: String = "com.example.Foo") -> UninstallCandidate {
        UninstallCandidate(id: path, name: name, bundleName: name, path: path,
                           bundleID: bundleID, version: "1.0", build: "1",
                           minSystemVersion: "14.0", executable: name, developer: "", teamID: "",
                           modificationDate: nil, provenance: .unknown)
    }

    private func match(_ pid: Int32, _ evidence: AppRunningEvidence, _ path: String?,
                       _ name: String? = "Foo") -> RunningAppMatch {
        RunningAppMatch(pid: pid, evidence: evidence, bundlePath: path, displayName: name)
    }

    // MARK: 没有正证据就不许说有

    func testNotRunningIsPhrasedAsNotSeen() {
        let app = candidate()
        let state = AppRunningState.notRunning
        XCTAssertEqual(app.runningValue(state), "未检测到运行中的进程")
        XCTAssertNil(app.runningChip(state))
        XCTAssertNil(app.runningWarning(state), "确认面板那一格只留给真的对上了的进程")
        XCTAssertTrue(app.runningBasis(state).contains("只读"))
    }

    /// 「没在运行」是一种主张。这一档只能说"看不看得出"。
    func testUndeterminedNeverSaysNotRunning() {
        let app = candidate()
        let state = AppRunningState.undetermined(unattributableCount: 3)
        XCTAssertTrue(app.runningValue(state).contains("无法判定"))
        XCTAssertFalse(app.runningValue(state).contains("未检测到"))
        XCTAssertTrue(app.runningBasis(state).contains("我没看到"))
        XCTAssertNil(app.runningChip(state))
        XCTAssertNil(app.runningWarning(state))
    }

    // MARK: 说到了进程就必须说清后果与边界

    func testRunningAlwaysSaysItDoesNotQuitTheApp() {
        let app = candidate()
        let states = [
            AppRunningState.running(matches: [match(42, .sameBundle, "/Applications/Foo.app")]),
            AppRunningState.running(matches: [match(42, .bundleIdentifierOnly, "/tmp/Copy.app"),
                                               match(43, .sameBundle, "/Applications/Foo.app")]),
        ]
        for state in states {
            guard let warning = app.runningWarning(state) else {
                XCTFail("对上进程就必须给提醒：\(state)")
                continue
            }
            XCTAssertTrue(warning.contains("不会让它退出"))
            XCTAssertTrue(warning.contains("不会代你退出或结束进程"),
                          "本模块没有结束进程的能力，文案不能有一种即将有的味道")
            XCTAssertFalse(warning.contains("已退出"))
            XCTAssertFalse(warning.contains("将结束"))
        }
    }

    /// 只有包名对上、位置报出来是另一个路径时，那件事必须写在提醒里：
    /// 用户要退的可能是别处那一份，而这里要删的是磁盘上这一份。
    /// 但话只能说到"写法不同"：判定只比字符串，`/tmp` 与 `/private/tmp` 这种
    /// 同一个文件的两种写法会被算进这一档（P31a 实拍抓到过），
    /// 所以"不是同一个文件"这一句是假话，测试把它钉成否证。
    func testIdentifierOnlyNamesTheOtherLocation() {
        let app = candidate()
        let state = AppRunningState.running(matches: [match(7, .bundleIdentifierOnly, "/private/var/folders/xx/Foo.app")])
        let warning = app.runningWarning(state) ?? ""
        XCTAssertTrue(warning.contains("对上的只是包名"))
        XCTAssertTrue(warning.contains("/private/var/folders/xx/Foo.app"))
        XCTAssertTrue(warning.contains("写法不同"))
        XCTAssertFalse(warning.contains("不是同一个文件"), "路径字符串不等推不出「不是同一个文件」")
        XCTAssertTrue(app.runningBasis(state).contains("与这里这一份的写法不同"))
    }

    func testPositionReportedByProcessMayBeMissing() {
        let app = candidate()
        let state = AppRunningState.running(matches: [match(7, .bundleIdentifierOnly, nil)])
        XCTAssertTrue((app.runningWarning(state) ?? "").contains("（报不出位置）"))
    }

    func testValueListsEveryPidInOrder() {
        let app = candidate()
        let state = AppRunningState.running(matches: [match(100, .sameBundle, "/Applications/Foo.app"),
                                                      match(200, .bundleIdentifierOnly, "/tmp/Copy.app")])
        XCTAssertEqual(app.runningValue(state), "正在运行 · 2 个进程（100、200）")
        XCTAssertTrue(app.runningBasis(state).contains("进程 100 报出的位置就是 /Applications/Foo.app"))
        XCTAssertTrue(app.runningBasis(state).contains("进程 200 只有包名对上"))
    }

    func testSinglePidValueSaysProcessNotCount() {
        let app = candidate()
        let state = AppRunningState.running(matches: [match(42, .sameBundle, "/Applications/Foo.app")])
        XCTAssertEqual(app.runningValue(state), "正在运行 · 进程 42")
    }

    /// 「两档都算『正在运行』」那句回答的是"包名对上、位置对不上的那一份算不算在跑"，
    /// 所以只有两档同时出现时它才是真话。真机照片上微信是「2 个进程（1094、1276）」、
    /// 两条都按位置对上（1276 是包内的 wxplayer：包名报不出、位置报得出），
    /// 那一屏里没有任何"两档"可数——这句当时是画面上唯一一句假话（P31a 实拍交叉核对抓到）。
    func testBothTiersSentenceOnlyWhenBothTiersArePresent() {
        let app = candidate()
        let bothSameBundle = AppRunningState.running(matches: [match(1094, .sameBundle, "/Applications/Foo.app"),
                                                               match(1276, .sameBundle, "/Applications/Foo.app")])
        XCTAssertFalse(app.runningBasis(bothSameBundle).contains("两档"),
                       "两个进程同一档 ≠ 两档；这一句必须钉成否证")
        let onlyIdentifier = AppRunningState.running(matches: [match(7, .bundleIdentifierOnly, "/tmp/Copy.app")])
        XCTAssertFalse(app.runningBasis(onlyIdentifier).contains("两档"))
        let mixed = AppRunningState.running(matches: [match(1, .sameBundle, "/Applications/Foo.app"),
                                                      match(2, .bundleIdentifierOnly, "/tmp/Copy.app")])
        XCTAssertTrue(mixed.isRunning)
        XCTAssertTrue(app.runningBasis(mixed).contains("两档都算「正在运行」"),
                      "两档同时出现时这句是该说出来的：它回答「别处那一份算不算在跑」")
    }

    /// 列表那一格：只有"正在运行"配得上占位，与 `sourceChip` 同一取舍。
    func testOnlyRunningTakesAListChip() {
        let app = candidate()
        XCTAssertEqual(app.runningChip(.running(matches: [match(1, .sameBundle, "/Applications/Foo.app")]))?.text, "运行中")
        XCTAssertNil(app.runningChip(.notRunning))
        XCTAssertNil(app.runningChip(.undetermined(unattributableCount: 1)))
    }

    /// "没检测到"不该用一枚对勾庆祝：那一档的信息量是"我没看到"，不是"一切正常"。
    func testNotRunningIsNotPaintedAsAllClear() {
        let app = candidate()
        XCTAssertEqual(app.runningEmphasis(.notRunning).symbol, "circle")
        XCTAssertEqual(app.runningEmphasis(.undetermined(unattributableCount: 1)).symbol, "questionmark.circle")
        XCTAssertEqual(app.runningEmphasis(.running(matches: [match(1, .sameBundle, "/Applications/Foo.app")])).symbol,
                       "exclamationmark.triangle")
    }
}
