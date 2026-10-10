import XCTest
import Foundation
@testable import MMUninstaller

/// 模型这一层只钉一件事：**快照读一次、按每个应用算一份、并且能被重读覆盖**。
/// 真读 `NSWorkspace` 的那一半不在这里（`RunningAppProbeTests` 里那条不变式 +
/// `Scripts/p31-running-capture.sh` 的带窗口截图），这里给的是注入的假快照。
@MainActor
final class UninstallerRunningStateModelTests: XCTestCase {

    private func model(with fixture: ResidualFixture,
                       snapshot: @escaping () -> [RunningAppInfo]) -> UninstallerModel {
        let model = UninstallerModel()
        model.optionsFactory = { ResidualScanOptions(home: fixture.homePath, systemRoot: fixture.systemPath) }
        model.appDirectoriesFactory = { _ in [fixture.homePath + "/Applications"] }
        model.provenancePrefixesFactory = { _ in [] }
        model.provenanceReceiptsRootFactory = { _ in nil }
        model.runningAppsFactory = snapshot
        return model
    }

    private func info(_ pid: Int32, _ bundleID: String, _ path: String) -> RunningAppInfo {
        RunningAppInfo(pid: pid, bundleIdentifier: bundleID, bundlePath: path, displayName: nil)
    }

    func testReloadPopulatesEveryAppAndDistinguishesRunningFromIdle() async throws {
        let fixture = try ResidualFixture(caseName: "runningStates")
        defer { fixture.cleanup() }
        let runningPath = try fixture.makeApp(name: "Running", bundleID: "com.example.Running")
        try fixture.makeApp(name: "Idle", bundleID: "com.example.Idle")

        let model = model(with: fixture, snapshot: { [self.info(4242, "com.example.Running", runningPath)] })
        await model.reloadListing()

        XCTAssertEqual(model.apps.count, 2)
        let running = try XCTUnwrap(model.apps.first { $0.bundleID == "com.example.Running" })
        let idle = try XCTUnwrap(model.apps.first { $0.bundleID == "com.example.Idle" })
        XCTAssertEqual(model.runningState(for: running)?.pids, [4242])
        XCTAssertEqual(model.runningState(for: idle), .notRunning)
    }

    /// 载入之前不给结论：`.notRunning` 是一种主张，不能当字典未命中时的默认值。
    func testStateIsAbsentBeforeTheFirstRead() throws {
        let fixture = try ResidualFixture(caseName: "runningStateAbsent")
        defer { fixture.cleanup() }
        try fixture.makeApp(name: "Idle", bundleID: "com.example.Idle")
        let model = model(with: fixture, snapshot: { [] })
        let ghost = UninstallCandidate(id: "/Applications/Ghost.app", name: "Ghost", bundleName: "Ghost",
                                       path: "/Applications/Ghost.app", bundleID: "com.example.Ghost",
                                       version: "1.0", build: "1", minSystemVersion: "14.0",
                                       executable: "Ghost", developer: "", teamID: "",
                                       modificationDate: nil, provenance: .unknown)
        XCTAssertNil(model.runningState(for: ghost))
    }

    /// 进程会起落，所以状态必须能被覆盖：重新读一次空快照，那一格要从"正在运行"变回"未检测到"。
    /// 通知驱动的那条刷新链路钉的就是这个性质。
    func testRefreshOverwritesPreviousRead() async throws {
        let fixture = try ResidualFixture(caseName: "runningStateRefresh")
        defer { fixture.cleanup() }
        let path = try fixture.makeApp(name: "Toggle", bundleID: "com.example.Toggle")
        var snapshot = [info(77, "com.example.Toggle", path)]
        let model = model(with: fixture, snapshot: { snapshot })
        await model.reloadListing()
        let app = try XCTUnwrap(model.apps.first)
        XCTAssertEqual(model.runningState(for: app)?.pids, [77])

        snapshot = []
        model.refreshRunningStates()
        XCTAssertEqual(model.runningState(for: app), .notRunning)
    }

    /// 列表换了一批应用，旧路径的状态不能跟着过来：整张表按当前 `apps` 重建。
    func testRefreshDropsStatesForAppsNoLongerListed() async throws {
        let fixture = try ResidualFixture(caseName: "runningStatePrune")
        defer { fixture.cleanup() }
        let first = try fixture.makeApp(name: "One", bundleID: "com.example.One")
        let model = model(with: fixture, snapshot: { [self.info(9, "com.example.One", first)] })
        await model.reloadListing()
        XCTAssertEqual(model.runningStates.keys.count, 1)

        try fixture.makeApp(name: "Two", bundleID: "com.example.Two")
        await model.reloadListing()
        XCTAssertEqual(model.runningStates.keys.count, 2)
        XCTAssertEqual(model.runningStates[first], .running(matches: [RunningAppMatch(pid: 9, evidence: .sameBundle,
                                                                                       bundlePath: first,
                                                                                       displayName: nil)]))
    }
}

private extension AppRunningState {
    var pids: [Int32]? {
        if case .running(let matches) = self { return matches.map(\.pid) }
        return nil
    }
}
