import XCTest
import Foundation
@testable import MMUninstaller

/// 运行中判定的测试全部在值类型快照上跑。`NSWorkspace.shared.runningApplications`
/// 在测试里是"别的进程此刻说了什么"，不是能钉住的前提 —— 与 `TrashWatcherTests`、
/// `AppProvenanceTests` 同一条理由。真机那一半由带窗口的截图负责。
final class RunningAppProbeTests: XCTestCase {

    private func info(_ pid: Int32, _ bundleID: String?, _ path: String?, _ name: String? = nil) -> RunningAppInfo {
        RunningAppInfo(pid: pid, bundleIdentifier: bundleID, bundlePath: path, displayName: name)
    }

    private func pids(_ state: AppRunningState) -> [Int32] {
        if case .running(let matches) = state { return matches.map(\.pid) }
        return []
    }

    private func evidence(of state: AppRunningState, _ pid: Int32) -> AppRunningEvidence? {
        if case .running(let matches) = state { return matches.first { $0.pid == pid }?.evidence }
        return nil
    }

    // MARK: 两条证据

    func testBundlePathMatchIsSameBundle() {
        let state = AppRunningState.resolve(bundleID: "com.example.Foo", bundlePath: "/Applications/Foo.app",
                                            running: [info(42, "com.example.Foo", "/Applications/Foo.app", "Foo")])
        XCTAssertEqual(state, .running(matches: [RunningAppMatch(pid: 42, evidence: .sameBundle,
                                                                 bundlePath: "/Applications/Foo.app",
                                                                 displayName: "Foo")]))
    }

    func testIdentifierOnlyCarriesTheOtherPath() {
        // 真机形态：App Translocation 把用户从隔离区拉起的那份放到 /var/folders 下的临时副本。
        let state = AppRunningState.resolve(bundleID: "com.example.Foo", bundlePath: "/Applications/Foo.app",
                                            running: [info(7, "com.example.Foo",
                                                           "/private/var/folders/xx/Foo.app", "Foo")])
        XCTAssertEqual(evidence(of: state, 7), .bundleIdentifierOnly)
    }

    /// 位置对上而包名不同（换了 bundleID 的两份构建）：这是同一个文件在跑，不能被"包名不符"推翻。
    func testPathMatchBeatsDifferentIdentifier() {
        let state = AppRunningState.resolve(bundleID: "com.example.Foo", bundlePath: "/Applications/Foo.app",
                                            running: [info(9, "com.oldname.Foo", "/Applications/Foo.app")])
        XCTAssertEqual(evidence(of: state, 9), .sameBundle)
    }

    func testComparisonIsCaseInsensitive() {
        // 路径这侧是 APFS 默认卷不区分大小写；包名那侧宁可多提醒一次也不要漏。
        let state = AppRunningState.resolve(bundleID: "com.example.foo", bundlePath: "/applications/FOO.app",
                                            running: [info(1, "com.example.FOO", "/Applications/Foo.app")])
        XCTAssertEqual(state, .running(matches: [RunningAppMatch(pid: 1, evidence: .sameBundle,
                                                                 bundlePath: "/Applications/Foo.app",
                                                                 displayName: nil)]))
    }

    func testMultipleMatchesAreSortedByPid() {
        let state = AppRunningState.resolve(bundleID: "com.example.Foo", bundlePath: "/Applications/Foo.app",
                                            running: [info(300, "com.example.Foo", "/tmp/Other.app"),
                                                      info(100, "com.example.Foo", "/Applications/Foo.app"),
                                                      info(200, "com.example.Foo", "/Applications/Foo.app")])
        XCTAssertEqual(pids(state), [100, 200, 300])
        XCTAssertEqual(evidence(of: state, 300), .bundleIdentifierOnly)
    }

    // MARK: 空值不参与比对

    func testEmptyIdentifierNeverMatchesEmptyIdentifier() {
        let state = AppRunningState.resolve(bundleID: "", bundlePath: "/Applications/Foo.app",
                                            running: [info(5, "", "/Applications/Else.app")])
        XCTAssertEqual(state, .notRunning, "两条空串相等不等于同一个应用")
    }

    func testEmptyPathNeverMatchesEmptyPath() {
        let state = AppRunningState.resolve(bundleID: "com.example.Foo", bundlePath: "",
                                            running: [info(5, "com.other", "")])
        XCTAssertEqual(state, .notRunning)
    }

    // MARK: 看不见 ≠ 没有

    func testUnattributableProcessesForceUndetermined() {
        let state = AppRunningState.resolve(bundleID: "com.example.Foo", bundlePath: "/Applications/Foo.app",
                                            running: [info(1, nil, nil), info(2, "", ""),
                                                      info(3, "com.other.Bar", "/Applications/Bar.app")])
        XCTAssertEqual(state, .undetermined(unattributableCount: 2))
    }

    /// 命中了就不该因为快照里有读不出身份的进程而退回"无法判定"——那会把已经拿到的事实丢掉。
    func testPositiveMatchOutweighsUnattributableGaps() {
        let state = AppRunningState.resolve(bundleID: "com.example.Foo", bundlePath: "/Applications/Foo.app",
                                            running: [info(1, nil, nil),
                                                      info(2, "com.example.Foo", "/Applications/Foo.app")])
        XCTAssertEqual(pids(state), [2])
    }

    func testEmptySnapshotIsNotRunningNotUndetermined() {
        XCTAssertEqual(AppRunningState.resolve(bundleID: "com.example.Foo", bundlePath: "/Applications/Foo.app",
                                               running: []), .notRunning)
    }

    func testIsRunningOnlyForPositiveEvidence() {
        XCTAssertFalse(AppRunningState.notRunning.isRunning)
        XCTAssertFalse(AppRunningState.undetermined(unattributableCount: 1).isRunning)
        let hit = AppRunningState.resolve(bundleID: "com.example.Foo", bundlePath: "/Applications/Foo.app",
                                          running: [info(1, "com.example.Foo", "/Applications/Foo.app")])
        XCTAssertTrue(hit.isRunning)
    }

    // MARK: 快照从哪来

    /// 只读快照的字段照抄 `NSRunningApplication`。这里钉的是"读的是哪一个属性"，
    /// 不是"本机有多少条"——后者不是能在单测里钉的东西（`snapshot()` 与真机那一半
    /// 由 `Scripts/p31-running-capture.sh` 的带窗口截图负责）。
    func testSnapshotReadsOnlyWhatItNeeds() {
        let snapshot = RunningAppProbe.snapshot()
        // 真机上这条几乎一定非空（Finder 至少在跑）；单测机器上若为空也不该失败，
        // 所以断言只写成"每个字段都来自同一条实例"这一条不变式。
        for entry in snapshot {
            XCTAssertTrue(entry.pid > 0, "pid 由系统给出，非正数说明读错了属性")
        }
    }

    /// 本机现读（2026-10-10 当日两次，参与判定的分别是 163 条、165 条——这个数随机器状态变）：
    /// 包名报不出 31 条、bundle 位置报不出 17 / 19 条、两者同时报不出 **0** 条。
    /// 所以 `undetermined` 这一档拍不出照片，
    /// 但它不是空想出来的分支——它是那 31 条与那 19 条的交集，只是本机没赶上。
    func testUnattributableIsDefinedByBothFieldsMissing() {
        XCTAssertTrue(info(1, nil, nil).isUnattributable)
        XCTAssertTrue(info(1, "", "").isUnattributable)
        XCTAssertFalse(info(1, nil, "/Applications/WeChat.app").isUnattributable,
                       "微信的主进程就是这样：包名报不出，位置报得出——位置就够定案")
        XCTAssertFalse(info(1, "com.apple.WebKit.WebContent", nil).isUnattributable)
    }
}
