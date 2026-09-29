import Foundation
import MMCore
import XCTest
@testable import MMUninstaller

/// 1.3 启动项：卸载时列出，但默认不勾选；root 属主的项只展示、不给删除入口。
/// 匹配两轮 —— A 文件名对应包名，B plist 的 Program / ProgramArguments 指向 app 本体。
final class LaunchServiceScannerTests: XCTestCase {
    private var fixture: ResidualFixture!

    override func setUpWithError() throws {
        fixture = try ResidualFixture(caseName: name)
    }

    override func tearDownWithError() throws {
        fixture?.cleanup()
        fixture = nil
    }

    // MARK: 第一轮：文件名

    /// 惯例是 label = bundleID 命名文件，第一轮就能命中。
    func testRoundAMatchByFileName() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let directory = try fixture.libraryFolder("LaunchAgents")
        let plist = directory + "/com.example.MyApp.plist"
        try fixture.writePlist(plist, ["Label": "com.example.MyApp",
                                      "Program": "\(app)/Contents/MacOS/MyApp"])

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        let item = report.items.first { $0.path == plist }
        XCTAssertEqual(item?.category, .launchService)
        XCTAssertEqual(item?.risk, .caution, "启动项影响自启动，必须谨慎档")
        XCTAssertTrue(item?.reason.contains("文件名") == true, "证据要说明是文件名命中：\(item?.reason ?? "nil")")
    }

    /// 派生标识（`.Helper`）的启动项同属这个 bundle。
    func testDerivedLabelIsClaimed() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let directory = try fixture.libraryFolder("LaunchAgents")
        let plist = directory + "/com.example.MyApp.Helper.plist"
        try fixture.writePlist(plist, ["Label": "com.example.MyApp.Helper"])

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        XCTAssertNotNil(report.items.first { $0.path == plist })
    }

    // MARK: 第二轮：plist 内容指向 app 路径

    /// 文件名毫无规律，只能靠 `ProgramArguments` 指向的路径认领。
    func testRoundBMatchByProgramArguments() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let directory = try fixture.libraryFolder("LaunchAgents")
        let plist = directory + "/update-helper.plist"
        try fixture.writePlist(plist, [
            "Label": "update-helper",
            "ProgramArguments": ["/usr/bin/nohup", "\(app)/Contents/Resources/MyAppUpdater", "--quiet"],
        ])

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        let item = report.items.first { $0.path == plist }
        XCTAssertNotNil(item, "ProgramArguments 指向 app 内可执行文件时也要命中")
        XCTAssertEqual(item?.category, .launchService)
        XCTAssertTrue(item?.reason.contains("可执行文件") == true, "证据要写出命中的键：\(item?.reason ?? "nil")")
    }

    /// 单键 `Program` 也算第二轮命中。
    func testRoundBMatchByProgramKey() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let directory = try fixture.libraryFolder("LaunchAgents")
        let plist = directory + "/agent.plist"
        try fixture.writePlist(plist, ["Label": "com.example.MyApp.agent", "Program": "\(app)/Contents/MacOS/MyApp"])

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        XCTAssertNotNil(report.items.first { $0.path == plist }, "Label 对应包名同样算第二轮")
    }

    /// 指向别的 app 的启动项不能认领（路径比较前先解析符号链接）。
    func testUnrelatedLaunchAgentIsNotClaimed() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let other = try fixture.makeApp(name: "Other", bundleID: "com.other.Unrelated")
        let directory = try fixture.libraryFolder("LaunchAgents")
        _ = try fixture.folderWithFile(directory + "/com.other.Unrelated")
        try fixture.writePlist(directory + "/com.other.Unrelated.plist", [
            "Label": "com.other.Unrelated",
            "ProgramArguments": ["\(other)/Contents/MacOS/Other"],
        ])

        let report = scan(fixture, appPath: app, sensitivity: .deep)
        XCTAssertTrue(report.items.contains { $0.path.contains("com.other.Unrelated") } == false,
                      "不能把别人的启动项算进来")
    }

    /// 没有包名也没有路径证据时不认领启动项。
    func testEmptyBundleIDClaimsNothing() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let directory = try fixture.libraryFolder("LaunchAgents")
        _ = try fixture.folderWithFile(directory)
        try fixture.writePlist(directory + "/anything.plist", ["Label": "anything"])

        let report = ResidualScanner.scan(appName: "My App", bundleID: "", appPath: app,
                                         options: fixture.options(sensitivity: .deep),
                                         measure: ResidualFixture.constantMeasure)
        XCTAssertTrue(report.items.contains { $0.category == .launchService } == false)
    }

    // MARK: 系统域与默认勾选

    /// `/Library/LaunchDaemons` 属 root：列出来，但标只读、不给删除入口、绝不默认勾选。
    func testSystemDomainLaunchDaemonIsReadOnlyAndUnselected() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let daemons = try fixture.libraryFolder("LaunchDaemons", under: fixture.systemRoot)
        try fixture.writePlist("\(daemons)/com.example.MyApp.daemon.plist", [
            "Label": "com.example.MyApp.daemon",
            "Program": "/Library/PrivilegedHelperTools/com.example.MyApp.helper",
        ])
        try fixture.writePlist("\(daemons)/com.other.Unrelated.daemon.plist", ["Label": "com.other.Unrelated.daemon"])
        try fixture.makeReadOnly(daemons)

        let report = scan(fixture, appPath: app, sensitivity: .strict, includeSystem: true)
        let item = report.items.first { $0.path.contains("com.example.MyApp.daemon.plist") }
        XCTAssertNotNil(item, "系统域启动项也要列出来")
        XCTAssertEqual(item?.risk, .readOnly, "root 属主且父目录不可写 → 只读")
        XCTAssertTrue(item?.reason.contains("root") == true, "证据要写明需要 root：\(item?.reason ?? "nil")")
        XCTAssertTrue(report.items.contains { $0.path.contains("com.other.Unrelated") } == false)

        let defaults = UninstallSelection.defaultSelectedIDs(report.items)
        XCTAssertTrue(defaults.contains(item!.id) == false, "启动项绝不默认勾选")
        let selectable = UninstallSelection.selectableIDs(report.items)
        XCTAssertTrue(selectable.contains(item!.id) == false, "只读项不提供删除入口")

        let paths = UninstallSelection.deletionPaths(appPath: app, items: report.items,
                                                     selectedIDs: defaults.union([item!.id]))
        XCTAssertTrue(paths.contains { $0 == item!.path } == false, "即使被勾选，只读项也不能进入删除列表")
    }

    /// 系统域 LaunchAgents 与用户 LaunchAgents 都要扫（两个域、两轮匹配）。
    func testBothUserAndSystemLaunchAgentDomainsAreScanned() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let userDomain = try fixture.libraryFolder("LaunchAgents")
        let systemDomain = try fixture.libraryFolder("LaunchAgents", under: fixture.systemRoot)
        try fixture.writePlist("\(userDomain)/com.example.MyApp.agent.plist", ["Label": "com.example.MyApp.agent"])
        try fixture.writePlist("\(systemDomain)/com.example.MyApp.agent.plist", ["Label": "com.example.MyApp.agent"])

        let report = scan(fixture, appPath: app, sensitivity: .strict, includeSystem: true)
        let services = report.items.filter { $0.category == .launchService }
        XCTAssertEqual(Set(services.map(\.id)).count, 2, "两个域各命中一项")
        XCTAssertTrue(services.contains { $0.path.hasPrefix(fixture.homePath) })
        XCTAssertTrue(services.contains { $0.path.hasPrefix(fixture.systemPath) })
    }

    /// 默认不扫系统域（真实机型需要 root 才读得动），只扫用户域。
    func testUserDomainOnlyWhenSystemRootAbsent() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        _ = try fixture.libraryFolder("LaunchAgents")
        let systemDomain = try fixture.libraryFolder("LaunchAgents", under: fixture.systemRoot)
        try fixture.writePlist("\(systemDomain)/com.example.MyApp.agent.plist", ["Label": "com.example.MyApp.agent"])

        let report = scan(fixture, appPath: app, sensitivity: .strict, includeSystem: false)
        XCTAssertTrue(report.items.contains { $0.path.hasPrefix(fixture.systemPath) } == false)
    }

    /// 域不存在 ≠ 域读不动。真实机型上多半就没有系统域那两个目录，
    /// 一律报"无法访问"会堆出一屏假警告，把真正的 TCC 拒绝淹没掉。
    func testAbsentDomainIsNotReportedInaccessible() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        // 故意不创建 ~/Library/LaunchAgents。
        let report = scan(fixture, appPath: app, sensitivity: .strict)
        XCTAssertTrue(report.inaccessiblePaths.isEmpty,
                      "不存在的目录不该出现在不可访问清单里：\(report.inaccessiblePaths)")
    }

    /// 勾选状态要能被"全选可删项"接受，同时只读项不在其中。
    func testCautionLaunchAgentIsSelectableButNotDefaulted() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let directory = try fixture.libraryFolder("LaunchAgents")
        try fixture.writePlist(directory + "/com.example.MyApp.plist", ["Label": "com.example.MyApp"])

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        guard let item = report.items.first(where: { $0.category == .launchService }) else {
            return XCTFail("应命中用户启动项")
        }
        XCTAssertEqual(item.risk, .caution)
        XCTAssertTrue(UninstallSelection.defaultSelectedIDs(report.items).contains(item.id) == false)
        XCTAssertTrue(UninstallSelection.selectableIDs(report.items).contains(item.id))
        XCTAssertEqual(UninstallSelection.unselectedDeletableCount(report.items,
                                                                  selectedIDs: UninstallSelection.defaultSelectedIDs(report.items)),
                       1, "默认不勾选的可删项要计入徽章")
    }
}
