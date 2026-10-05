//
//  ActivityCardContractTests.swift — 活动卡的「文案合同」测试
//
//  这一卡从前叫「系统活动」，里面混三族：`log show` 命中行、用户 LaunchAgent、
//  敏感目录。P11c 把每一条的口径量了一遍，结论是**只有后两族撑得住界面上说的话**：
//
//  1. `log show` 那条谓词（`eventMessage contains "login" OR contains "auth"`）量到的是
//     "正文里含这几个字母组合的行"，不是"系统活动"：本机 5 分钟 139 行里 47 行是 sharingd 的
//     `authTag`，另有 5 行是 `log` 把我们自己的谓词原文回声回来。换窄白名单也没有出路——
//     tccd 52 行/5m 全是 `SecTrustCopyAppleTrustAnchors`、`kauth_membership_check` 这类内部转储，
//     syspolicyd 20,741 行/30m，loginwindow 2,763 行/60m，而只留 authd+authorizationhost 是 0 行/5m。
//  2. LaunchAgent 那一族写在 `files.prefix(3)` **之后**才过滤 `.plist`：本机该目录 9 个条目里
//     6 个是改名停用的 `.disabled`，且排在最前 → 这一族在真机上恒为 0 行，磁盘上明明有 3 个 .plist。
//  3. 敏感目录那一行写「最近访问」，读的却是 `.modificationDate`（mtime）。mtime 只在目录**增删条目**
//     时变，读取里面的密钥文件不会动它——所以这句话恰好是这个卡最不该说的那件事。
//
//  于是这一卡收口成"只报文件系统的改动时间"，合同写在 `ActivityCardCopy` 里，
//  下面每个测试钉住其中一句话或一个形状。全部零系统调用：喂进去的是本机抄来的条目形状。
//

import XCTest
@testable import MMGuardian

final class ActivityCardContractTests: XCTestCase {

    // MARK: - 二、LaunchAgent：先过滤再截断

    func testDisabledAgentsDoNotCrowdOutTheRealPlists() {
        // 本机 ~/Library/LaunchAgents 的真实形状：9 个条目，前 6 个是 .disabled。
        // 旧写法 files.prefix(3) 之后再 where hasSuffix(".plist") → 这一族返回 0 行。
        let now = Date()
        let entries: [(name: String, modificationDate: Date)] = [
            ("com.codex.clean-project-build-artifacts.disabled", now),
            ("com.google.GoogleUpdater.wake.disabled", now),
            ("com.pnuts.jenkins.disabled", now),
            ("com.pnuts.jenkins.plist", now.addingTimeInterval(-86_400 * 3)),
            ("com.tencent.Lemon.trash.disabled", now),
            ("com.tencent.Lemon.trash.plist", now.addingTimeInterval(-3_600)),
            ("local.jenkins-lts.disabled", now),
            ("netdisk_service.disabled", now),
            ("sh.brew.jenkins-lts.plist", now.addingTimeInterval(-86_400)),
        ]
        let picked = ActivityScanner.launchAgentFiles(in: entries, root: "/Users/tester/Library/LaunchAgents")
        XCTAssertEqual(picked.map(\.name), [
            "com.tencent.Lemon.trash.plist",
            "sh.brew.jenkins-lts.plist",
            "com.pnuts.jenkins.plist",
        ], "三个 .plist 都在磁盘上，一个都不该被 .disabled 挤掉：\(picked.map(\.name))")
    }

    func testLaunchAgentRowsAreNewestFirstAndCapped() {
        let now = Date()
        let entries: [(name: String, modificationDate: Date)] = (0..<6).map { i in
            ("a\(i).plist", now.addingTimeInterval(TimeInterval(i) * -86_400))
        } + [("z-not-a-plist", now)]
        let picked = ActivityScanner.launchAgentFiles(in: entries, root: "/r", limit: 3)
        XCTAssertEqual(picked.count, 3)
        XCTAssertEqual(picked.map(\.name), ["a0.plist", "a1.plist", "a2.plist"])
        XCTAssertEqual(picked.first?.path, "/r/a0.plist", "行里要给全路径，光有标识符认不出是谁")
    }

    // MARK: - 三、敏感目录：只有 mtime，没有"访问"

    func testWatchedDirectoriesAreTheThreeKeyPaths() {
        let dirs = ActivityScanner.watchableDirectories(home: "/Users/tester")
        XCTAssertEqual(dirs.map(\.path), [
            "/Users/tester/.ssh",
            "/Users/tester/.gnupg",
            "/Users/tester/Library/Keychains",
        ])
    }

    func testRowDetailIsThePathAndNeverClaimsAccessTime() {
        let now = Date()
        let dirs = [ActivityScanner.WatchedDirectory(
            label: "SSH 密钥目录", path: "/Users/tester/.ssh", icon: "key.fill",
            modificationDate: now.addingTimeInterval(-86_400 * 2)
        )]
        let rows = ActivityScanner.activityRows(directories: dirs, launchAgents: [])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "SSH 密钥目录")
        XCTAssertEqual(rows[0].detail, "/Users/tester/.ssh")
        XCTAssertEqual(rows[0].time, "2 天前", "右侧那一格要给的是改动时间的相对说法")
        XCTAssertEqual(rows[0].tone, .caution)
        XCTAssertFalse(rows.contains { $0.detail.contains("最近访问") },
                       "读的是 mtime，就不能写「最近访问」")
    }

    func testNoRowCarriesAHardcodedTimeLabel() {
        // 「最近」这一格从前是写死的（`time: "最近"`），而它旁边的正文里根本没有时间列。
        let now = Date()
        let dirs = ActivityScanner.watchableDirectories(home: "/Users/tester").map {
            ActivityScanner.WatchedDirectory(label: $0.label, path: $0.path, icon: $0.icon,
                                             modificationDate: now)
        }
        let agents = ActivityScanner.launchAgentFiles(
            in: [("com.example.agent.plist", now.addingTimeInterval(-90))], root: "/r")
        let rows = ActivityScanner.activityRows(directories: dirs, launchAgents: agents)
        XCTAssertEqual(rows.count, 4)
        XCTAssertFalse(rows.contains(where: { $0.time == "最近" }), "每一格的时间都必须来自一个真实 mtime")
        XCTAssertTrue(rows.allSatisfy { $0.time == "刚刚" || $0.time.hasSuffix("前") },
                      "时间列只能是相对时间说法：\(rows.map(\.time))")
        XCTAssertEqual(rows.filter { $0.tone == .neutral }.count, 1, "LaunchAgent 行不报警，它只是存在")
    }

    // MARK: - 一、日志族不在卡里：卡片说的话不能再暗示"事件流"

    func testCardCopyScopesTheClaimToModificationTimes() {
        XCTAssertTrue(ActivityCardCopy.title.contains("改动"),
                      "标题不能再叫「系统活动」：这一卡没有事件流，只有几个 mtime")
        XCTAssertFalse(ActivityCardCopy.title.contains("活动"))
        XCTAssertTrue(ActivityCardCopy.footnote.contains("mtime"))
        XCTAssertTrue(ActivityCardCopy.footnote.contains("读取"),
                      "脚注必须写明读取密钥文件不会留下这里显示的那个时间")
        XCTAssertTrue(ActivityCardCopy.emptyText.contains("LaunchAgent"))
        XCTAssertFalse(ActivityCardCopy.emptyText.contains("分钟"),
                       "剩下的两族没有 5 分钟窗口，空态不能再承诺一个窗口")
    }

    func testRelativeTimeBoundaries() {
        let now = Date()
        XCTAssertEqual(ActivityScanner.relativeTime(now.addingTimeInterval(-5)), "刚刚")
        XCTAssertEqual(ActivityScanner.relativeTime(now.addingTimeInterval(-120)), "2 分钟前")
        XCTAssertEqual(ActivityScanner.relativeTime(now.addingTimeInterval(-7_200)), "2 小时前")
        XCTAssertEqual(ActivityScanner.relativeTime(now.addingTimeInterval(-86_400 * 5 - 60)), "5 天前")
    }

    func testFixtureRowsUseTheSameVocabularyAsRealRows() {
        // 夹具档如果留着「系统日志事件」「最近访问」，无头照片就会教一套真机已不再产出的口径。
        let items = GuardianActivityFixture.items()
        XCTAssertFalse(items.isEmpty)
        XCTAssertFalse(items.contains(where: { $0.title.contains("系统日志事件") }))
        XCTAssertFalse(items.contains(where: { $0.detail.contains("最近访问") }))
        XCTAssertFalse(items.contains(where: { $0.time == "最近" }))
        XCTAssertTrue(items.allSatisfy { $0.detail.contains("/") },
                      "夹具行的 detail 也该是路径，跟真机同一形状")
    }
}
