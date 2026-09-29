//
//  LaunchItemPolicyTests.swift — 只读判定（任务 B 的域规则）
//
//  全部用字符串/临时目录断言，绝不触碰真实系统 plist。
//

import XCTest
@testable import MMGuardian

final class LaunchItemPolicyTests: XCTestCase {

    func testSystemDomainPathsAreReadOnly() {
        XCTAssertEqual(
            LaunchItemPolicy.domain(for: "/Library/LaunchAgents/com.apple.foo.plist"),
            .system
        )
        XCTAssertEqual(
            LaunchItemPolicy.domain(for: "/Library/LaunchDaemons/com.apple.bar.plist"),
            .system
        )
        XCTAssertFalse(LaunchItemPolicy.isUserLaunchAgent(
            path: "/Library/LaunchAgents/com.apple.foo.plist",
            home: "/Users/tester"
        ))
        // domain.isWritable 是 UI 决定是否画开关的唯一依据。
        XCTAssertFalse(LaunchItemPolicy.domain(for: "/Library/LaunchDaemons/x.plist").isWritable)
    }

    func testUserLaunchAgentsPathIsWritable() {
        let home = "/Users/tester"
        let path = "\(home)/Library/LaunchAgents/com.mine.agent.plist"
        XCTAssertTrue(LaunchItemPolicy.isUserLaunchAgent(path: path, home: home))
        XCTAssertEqual(LaunchItemPolicy.domain(for: path, home: home), .user)
        XCTAssertTrue(LaunchItemPolicy.domain(for: path, home: home).isWritable)
    }

    func testPrefixLookalikeIsRejected() {
        // "LaunchAgentsEvil" 不能因为裸前缀匹配被当成用户域。
        XCTAssertFalse(LaunchItemPolicy.isUserLaunchAgent(
            path: "/Users/tester/Library/LaunchAgentsEvil/x.plist",
            home: "/Users/tester"
        ))
        // 目录本身（非其中文件）也不算。
        XCTAssertFalse(LaunchItemPolicy.isUserLaunchAgent(
            path: "/Users/tester/Library/LaunchAgents",
            home: "/Users/tester"
        ))
    }

    func testSymlinkedHomeStillMatches() throws {
        // 已知坑：/var ↔ /private/var 这类符号链接别名。home 传符号链接路径、
        // 文件传真实路径，归一化后仍必须匹配。
        let tmp = try makeTemporaryDirectory()
        let realHome = tmp.appendingPathComponent("realHome")
        let launchDir = realHome.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: launchDir, withIntermediateDirectories: true)
        let plist = launchDir.appendingPathComponent("a.plist")
        try "<plist/>".write(to: plist, atomically: true, encoding: .utf8)

        let linkHome = tmp.appendingPathComponent("linkHome")
        try FileManager.default.createSymbolicLink(at: linkHome, withDestinationURL: realHome)

        XCTAssertTrue(LaunchItemPolicy.isUserLaunchAgent(
            path: plist.path,
            home: linkHome.path
        ))
        XCTAssertTrue(LaunchItemPolicy.isUserLaunchAgent(
            path: linkHome.appendingPathComponent("Library/LaunchAgents/a.plist").path,
            home: realHome.path
        ))
    }

    func testUnrelatedPathFallsBackToUserPreferences() {
        XCTAssertEqual(
            LaunchItemPolicy.domain(for: "/Users/tester/Library/Preferences/loginitems.plist"),
            .userPreferences
        )
        XCTAssertFalse(LaunchItemPolicy.domain(for: "/Users/tester/Library/Preferences/loginitems.plist").isWritable)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMGuardianPolicyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
}
