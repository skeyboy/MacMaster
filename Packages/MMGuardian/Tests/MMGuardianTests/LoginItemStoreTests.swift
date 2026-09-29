//
//  LoginItemStoreTests.swift — 写路径行为（tmpdir 伪造用户 LaunchAgents，绝不动真实系统 plist）
//

import XCTest
import MMCore
@testable import MMGuardian

final class LoginItemStoreTests: XCTestCase {

    private var tmp: URL!
    private var fakeHome: URL!
    private var agentsDir: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMGuardianStoreTests-\(UUID().uuidString)")
        agentsDir = tmp.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        fakeHome = tmp
    }

    override func tearDownWithError() throws {
        // 先恢复权限再删，否则 555 目录会让 removeItem 报 EACCES。
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agentsDir.path)
        try? FileManager.default.removeItem(at: tmp)
    }

    private func writePlist(named name: String, label: String = "com.example.agent") throws -> URL {
        let url = agentsDir.appendingPathComponent(name)
        let dict: [String: Any] = ["Label": label, "Program": "/usr/bin/true"]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        try data.write(to: url)
        return url
    }

    private func readDict(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }

    private func item(for url: URL, enabled: Bool = true) -> LoginItem {
        LoginItem(
            name: url.deletingPathExtension().lastPathComponent,
            path: url.path,
            domain: LaunchItemPolicy.domain(for: url.path, home: fakeHome.path),
            enabled: enabled,
            icon: "gear"
        )
    }

    // MARK: 成功路径：用户域 plist 写入 Disabled

    func testToggleUserItemWritesDisabledKey() throws {
        let url = try writePlist(named: "com.example.agent.plist")
        var launchctlCalls: [(String, String)] = []

        let failure = LoginItemStore.toggle(item(for: url), home: fakeHome.path) { command, path in
            launchctlCalls.append((command, path))
            return nil
        }

        XCTAssertNil(failure, "用户域 + 可写目录：toggle 应成功")
        let dict = try readDict(at: url)
        XCTAssertEqual(dict["Label"] as? String, "com.example.agent", "原有键不能丢")
        XCTAssertEqual(dict["Disabled"] as? Bool, true, "开着 → 关对应写 Disabled=true")
        XCTAssertEqual(launchctlCalls.count, 1)
        XCTAssertEqual(launchctlCalls.first?.0, "unload")
    }

    func testToggleAlreadyDisabledItemWritesFalse() throws {
        let url = try writePlist(named: "com.example.off.plist")
        var dict = try readDict(at: url)
        dict["Disabled"] = false
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)

        let failure = LoginItemStore.toggle(item(for: url, enabled: false), home: fakeHome.path) { _, _ in nil }
        XCTAssertNil(failure)
        XCTAssertEqual(try readDict(at: url)["Disabled"] as? Bool, false)
    }

    // MARK: 系统域：拒绝且零磁盘触碰

    func testSystemDomainIsRefusedWithoutTouchingDisk() {
        // 用一个不存在的系统域路径：若在拒绝前发生任何 I/O，行为会是"尝试读后静默失败"；
        // 现在必须在入口就返回 READ-ONLY，且绝不写 /Library。
        let item = LoginItem(
            name: "com.apple.something",
            path: "/Library/LaunchDaemons/com.apple.something.plist",
            domain: .system,
            enabled: true,
            icon: "gearshape.2"
        )
        var launchctlCalled = false
        let failure = LoginItemStore.toggle(item, home: fakeHome.path) { _, _ in
            launchctlCalled = true
            return nil
        }
        XCTAssertNotNil(failure)
        XCTAssertEqual(failure?.code, "READ-ONLY")
        XCTAssertTrue(failure?.message.contains("系统设置") ?? false, "失败文案要包含引导")
        XCTAssertFalse(launchctlCalled, "系统域拒绝后不得继续任何动作")
    }

    func testLookalikePathRejectedByPolicy() throws {
        // 挂在用户 home 下的仿冒目录：domain 判成 userPreferences（不可写），
        // 即使调用方硬塞 isWritable 的 LoginItem，toggle 也要按策略拒绝。
        let evil = fakeHome.appendingPathComponent("Library/LaunchAgentsEvil")
        try FileManager.default.createDirectory(at: evil, withIntermediateDirectories: true)
        let url = evil.appendingPathComponent("x.plist")
        try Data().write(to: url)

        let smuggled = LoginItem(name: "x", path: url.path, domain: .user, enabled: true, icon: "gear")
        let failure = LoginItemStore.toggle(smuggled, home: fakeHome.path) { _, _ in nil }
        XCTAssertEqual(failure?.code, "POLICY")
    }

    // MARK: 写失败必须可见（含 POSIX 码原文）

    func testReadOnlyDirectorySurfacesErrnoText() throws {
        try XCTSkipIf(geteuid() == 0, "root 下 chmod 不阻止写入，跳过")
        let url = try writePlist(named: "com.example.locked.plist")
        // 原子写 = 同目录建新文件再 rename；把目录设成只读即可复现 EACCES。
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: agentsDir.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: self.agentsDir.path)
        }

        var launchctlCalled = false
        let failure = LoginItemStore.toggle(item(for: url), home: fakeHome.path) { _, _ in
            launchctlCalled = true
            return nil
        }
        guard let failure else {
            return XCTFail("写失败必须返回 TrashFailure，不许静默")
        }
        XCTAssertEqual(failure.code, "EACCES")
        XCTAssertTrue(failure.message.contains("Permission denied") || failure.message.contains("errno"),
                      "错误原文（strerror 文本 + errno 码）必须都在：\(failure.message)")
        XCTAssertFalse(launchctlCalled, "plist 没写成，launchctl 不许假装生效")
    }

    func testMissingFileSurfacesENOENT() throws {
        let url = agentsDir.appendingPathComponent("com.example.gone.plist")
        let failure = LoginItemStore.toggle(item(for: url), home: fakeHome.path) { _, _ in nil }
        XCTAssertNotNil(failure)
        XCTAssertTrue(failure!.message.contains("errno \(ENOENT)") || failure!.message.contains("No such file"),
                      "读侧失败也要原文：\(failure!.message)")
    }

    func testLaunchctlFailureIsReportedNotSwallowed() throws {
        let url = try writePlist(named: "com.example.lc.plist")
        let failure = LoginItemStore.toggle(item(for: url), home: fakeHome.path) { _, _ in
            "exit 3：The service could not be found"
        }
        XCTAssertNotNil(failure)
        XCTAssertEqual(failure?.code, "LAUNCHCTL")
        XCTAssertTrue(failure!.message.contains("exit 3"), "launchctl 的 stderr 原文要展示")
        XCTAssertEqual(try readDict(at: url)["Disabled"] as? Bool, true, "plist 本身已写成，状态如实说明")
    }

    // MARK: 扫描（只读 tmp 目录，不碰真实系统）

    func testScannerReportsErrorsAndUserDomain() throws {
        let url = try writePlist(named: "com.example.scan.plist", label: "com.example.scan")
        // 故意放一个坏 plist：解析错误要进 readErrors，而不是被跳过当无事发生。
        try "not-a-plist".data(using: .utf8)!.write(to: agentsDir.appendingPathComponent("bad.plist"))

        // 只扫 fakeHome：把系统目录也指到 fakeHome 下等价目录会改变真实路径语义，
        // 所以这里只断言 fakeHome 用户域条目 + 错误收集机制。
        _ = url
        let report = LoginItemScanner.scan(home: fakeHome.path)
        let userItems = report.items.filter { $0.domain == .user }
        XCTAssertEqual(userItems.map(\.name), ["com.example.scan"])
        XCTAssertTrue(report.readErrors.contains { $0.contains("bad.plist") },
                      "坏 plist 的解析错误必须出现在 readErrors：\(report.readErrors)")
    }
}
