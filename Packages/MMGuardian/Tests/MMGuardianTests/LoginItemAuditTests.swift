import XCTest
@testable import MMGuardian

/// P3.3：磁盘清单 × launchd 快照的交叉核对。
/// 这里守的是两条红线：查不到时不许塌成"没加载"；判定范围不许越出发给它的域。
final class LoginItemAuditTests: XCTestCase {

    private func item(_ label: String, path: String, enabled: Bool = true,
                      domain: LaunchDomain = .user,
                      kind: LoginItemFileKind = .plist) -> LoginItem {
        LoginItem(name: label, path: path, domain: domain, enabled: enabled,
                  icon: "gear", fileKind: kind)
    }

    private let userDir = "/Users/lee/Library/LaunchAgents"

    // MARK: 解析

    func testParsesStandardThreeColumnOutput() {
        let out = """
        PID\tStatus\tLabel
        67556\t-9\tcom.apple.cloudphotod
        -\t0\tcom.tencent.Lemon.trash
        -\t0\tsh.brew.jenkins-lts
        """
        guard case .labels(let labels) = LaunchctlListParser.parse(out) else {
            return XCTFail("应当解析成功")
        }
        XCTAssertEqual(labels, ["com.apple.cloudphotod", "com.tencent.Lemon.trash", "sh.brew.jenkins-lts"])
    }

    func testMissingHeaderIsUnavailableNotEmptySet() {
        // 表头认不出来 = 我们不知道在读什么。这一档必须让上层放弃判定，
        // 而不是给一个空集合让所有 plist 都变成"没加载"。
        let snapshot = LaunchctlListParser.parse("some other tool's output\nfoo\n")
        guard case .unavailable(let reason) = snapshot else {
            return XCTFail("应当降级成不可用")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testZeroLabelsIsTreatedAsParseFailure() {
        // 有表头、零行：这台机器什么都不跑是不可能的，说明是格式变了。
        let snapshot = LaunchctlListParser.parse("PID\tStatus\tLabel\n")
        if case .labels(let s) = snapshot {
            XCTFail("空标签集合不该被当成可信快照，实际：\(s)")
        }
    }

    // MARK: 判定范围

    func testDaemonsAreNeverJudged() {
        // /Library/LaunchDaemons 属 system 域，GUI 的 launchctl list 里本来就没有它。
        // 拿"查不到"判它"没加载"就是假话。
        let daemon = item("com.example.daemon", path: "/Library/LaunchDaemons/com.example.daemon.plist",
                          domain: .system)
        let audit = LoginItemAuditor.audit(items: [daemon], snapshot: .labels([]), plistExists: { _ in true })
        XCTAssertTrue(audit.anomalies.isEmpty)
    }

    func testSystemLaunchAgentsAreJudged() {
        // /Library/LaunchAgents 会进当前用户的 GUI 域，可以核对（只是不可写）。
        let agent = item("com.example.agent", path: "/Library/LaunchAgents/com.example.agent.plist",
                         domain: .system)
        let audit = LoginItemAuditor.audit(items: [agent], snapshot: .labels(["other"]), plistExists: { _ in true })
        XCTAssertEqual(audit.anomalies["/Library/LaunchAgents/com.example.agent.plist"], .plistNotLoaded)
    }

    func testRenamedDisabledFileIsNotReportedAsNotLoaded() {
        // 改名停用本来就不该被加载，标它"没加载"是把手段当故障。
        let renamed = item("com.example.tool", path: "\(userDir)/com.example.tool.disabled",
                           enabled: false, kind: .renamedDisabled)
        let audit = LoginItemAuditor.audit(items: [renamed], snapshot: .labels(["other"]), plistExists: { _ in true })
        XCTAssertTrue(audit.anomalies.isEmpty)
    }

    // MARK: 三种结论

    func testEnabledPlistAbsentFromSessionIsFlagged() {
        let plist = item("com.example.helper", path: "\(userDir)/com.example.helper.plist")
        let audit = LoginItemAuditor.audit(items: [plist], snapshot: .labels(["com.apple.Something"]),
                                           plistExists: { _ in true })
        XCTAssertEqual(audit.anomalies["\(userDir)/com.example.helper.plist"], .plistNotLoaded)
        XCTAssertTrue(audit.determinate)
    }

    func testDisabledKeyButStillLoadedIsFlagged() {
        let plist = item("com.example.zombie", path: "\(userDir)/com.example.zombie.plist", enabled: false)
        let audit = LoginItemAuditor.audit(items: [plist], snapshot: .labels(["com.example.zombie"]),
                                           plistExists: { _ in true })
        XCTAssertEqual(audit.anomalies["\(userDir)/com.example.zombie.plist"], .disabledButLoaded)
    }

    func testAppleLabelsAreExcludedFromOrphans() {
        // 本机实测：101 个候选里 99 个是 com.apple.*。它们的落盘位置我们枚举不全，
        // 列出来只会把真正该看的那两三条埋掉——所以宁可少报。
        let audit = LoginItemAuditor.audit(items: [], snapshot: .labels([
            "com.apple.Dock.agent", "com.apple.CharacterPicker.FileService", "com.ollama.ollama",
        ])) { _ in false }
        XCTAssertEqual(audit.orphanLabels, ["com.ollama.ollama"])
    }

    func testLoadedAndEnabledIsClean() {
        let plist = item("com.example.good", path: "\(userDir)/com.example.good.plist")
        let audit = LoginItemAuditor.audit(items: [plist], snapshot: .labels(["com.example.good"]),
                                           plistExists: { _ in true })
        XCTAssertTrue(audit.anomalies.isEmpty)
        XCTAssertTrue(audit.orphanLabels.isEmpty)
    }

    // MARK: 孤儿标签

    func testOrphanLabelNeedsAllKnownDirsMissing() {
        let exists = ["/Library/LaunchAgents/com.example.kept.plist"]
        let audit = LoginItemAuditor.audit(items: [], snapshot: .labels(["com.example.kept", "com.example.gone"])
        ) { path in exists.contains(path) }
        XCTAssertEqual(audit.orphanLabels, ["com.example.gone"])
    }

    func testSystemScopeLabelsAreNotOrphans() {
        // /System 下的两个目录也在"已知位置"里：苹果自家条目不该刷满屏幕。
        let audit = LoginItemAuditor.audit(items: [], snapshot: .labels(["com.apple.notifyd"])) { path in
            path == "/System/Library/LaunchAgents/com.apple.notifyd.plist"
        }
        XCTAssertTrue(audit.orphanLabels.isEmpty)
    }

    func testAppLifecycleLabelsAreExcludedFromOrphans() {
        // application.* / pid.* 是 launchd 给进程发的临时标签，从来就没有 plist 文件。
        let audit = LoginItemAuditor.audit(items: [], snapshot: .labels([
            "application.com.example.app.123456", "pid.4242", "com.example.real",
        ])) { _ in false }
        XCTAssertEqual(audit.orphanLabels, ["com.example.real"])
    }

    // MARK: 不可核对

    func testUnavailableSnapshotProducesNoAnomaliesAndAReason() {
        let plist = item("com.example.helper", path: "\(userDir)/com.example.helper.plist")
        let audit = LoginItemAuditor.audit(items: [plist], snapshot: .unavailable(reason: "launchctl list exit 1"))
            { _ in true }
        XCTAssertFalse(audit.determinate)
        XCTAssertEqual(audit.reason, "launchctl list exit 1")
        XCTAssertTrue(audit.anomalies.isEmpty, "没核对成就不许留任何徽章")
        XCTAssertTrue(audit.orphanLabels.isEmpty)
    }

    func testIndeterminateNoteKeepsTheRawReason() {
        let note = LoginItemAnomalyCopy.indeterminateNote("无法启动 launchctl")
        XCTAssertTrue(note.contains("无法启动 launchctl"))
        XCTAssertTrue(note.contains("没查到"))
    }

    // MARK: 改名停用的条目不许走写 Disabled 键

    func testToggleRefusesRenamedDisabledFile() {
        let path = "\(userDir)/com.example.tool.disabled"
        // 用户域前缀是真的才会进到改名判定；拒绝发生在任何文件操作之前，
        // 所以这条测试既不碰真目录，也不该留下任何文件。
        let renamed = item("com.example.tool", path: path, enabled: false, kind: .renamedDisabled)
        let failure = LoginItemStore.toggle(renamed, home: "/Users/lee") { _, _ in nil }
        XCTAssertEqual(failure?.code, "RENAME-MANAGED")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "拒绝写入就不该留下文件")
    }
}
