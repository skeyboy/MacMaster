import XCTest
@testable import MMFileScanner

/// 4.6 只读报告的测试。这里没有一棵"真"的快照列表可依赖，
/// 所以测的是**解析口径**：给定 tmutil 的实际输出格式要得出正确清单，
/// 给定任何不是这个格式的东西要整块降级成"不可用 + 原因"，而不是猜一个空清单。
final class SystemSpaceReportTests: XCTestCase {

    // MARK: - 快照输出解析

    func testParsesSampleSnapshotListing() throws {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-05-01-120100.local
        com.apple.TimeMachine.2026-05-02-093312.local
        """
        let listing = LocalSnapshotReader.parse(output, fallbackVolume: "/")
        guard case .available(let snapshots) = listing else {
            return XCTFail("应当解析成功，实际不可用：\(listing.reason ?? "—")")
        }
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.map(\.name), [
            "com.apple.TimeMachine.2026-05-01-120100.local",
            "com.apple.TimeMachine.2026-05-02-093312.local",
        ])
        XCTAssertEqual(snapshots.first?.volumePath, "/")
        XCTAssertNotNil(snapshots.first?.date, "标准命名里的时间戳要能读出来")
    }

    /// macOS 11 起带签名系统卷的机器上，表头写的是"卷组"而不是"盘"。
    /// 只认老式表头会让这块卡片在新系统上**永远**显示"不可用"——
    /// 而单测当时全按老式表头写样例，所以全绿。这条钉住真机形态。
    func testParsesVolumeGroupHeader() throws {
        let output = """
        Snapshots for volume group containing disk /:
        com.apple.os.update-5203530F8BB20B9DABC5CE76A0FFE87CCC885EE69B8A5488C24B458A7555E3AB
        com.apple.os.update-MSUPrepareUpdate
        """
        let listing = LocalSnapshotReader.parse(output, fallbackVolume: "/")
        guard case .available(let snapshots) = listing else {
            return XCTFail("卷组表头是当代 macOS 的正常输出：\(listing.reason ?? "—")")
        }
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.first?.volumePath, "/", "表头里的 / 要当作卷路径")
    }

    /// 没接 Time Machine 的 Mac 上也会有快照，全是系统更新留的安全网。
    /// 把它们统称"Time Machine 快照"会指错方向：动了会影响更新回滚。
    func testSnapshotKindsAreSeparated() throws {
        let output = """
        Snapshots for volume group containing disk /:
        com.apple.TimeMachine.2026-05-01-120100.local
        com.apple.os.update-MSUPrepareUpdate
        com.apple.os.update-5203530F8BB20B9D
        com.apple.ThirdPartyTool.2026-01-01
        """
        let listing = LocalSnapshotReader.parse(output, fallbackVolume: "/")
        guard case .available(let snapshots) = listing else {
            return XCTFail("应当解析成功：\(listing.reason ?? "—")")
        }
        XCTAssertEqual(snapshots.map(\.kind), [LocalSnapshot.Kind](
            [.timeMachine, .systemUpdate, .systemUpdate, .other]
        ))
        XCTAssertEqual(listing.count(of: .timeMachine), 1)
        XCTAssertEqual(listing.count(of: .systemUpdate), 2)
        XCTAssertEqual(listing.count(of: .other), 1)
    }

    func testParsesPerVolumeHeadersAndIgnoresNoiseLines() throws {
        let output = """
        Snapshots for disk /System/Volumes/Data:
        com.apple.TimeMachine.2026-04-30-221105.local
        warning: something unrelated
        Snapshots for disk /:
        """
        let listing = LocalSnapshotReader.parse(output, fallbackVolume: "/")
        guard case .available(let snapshots) = listing else {
            return XCTFail("应当解析成功，实际不可用：\(listing.reason ?? "—")")
        }
        XCTAssertEqual(snapshots.count, 1, "非快照行不能被当成快照计入")
        XCTAssertEqual(snapshots[0].volumePath, "/System/Volumes/Data")
    }

    func testHeaderWithoutSnapshotsMeansNoSnapshots() throws {
        let listing = LocalSnapshotReader.parse("Snapshots for disk /:\n", fallbackVolume: "/")
        guard case .available(let snapshots) = listing else {
            return XCTFail("有表头没有条目是合法的「本机没有快照」")
        }
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testGarbageOutputIsReportedUnavailable() {
        let cases = [
            "tmutil: Error: Getting snapshot infos failed with error: 70",
            "%%% not a snapshot listing %%%",
            "com.apple.TimeMachine.2026-05-01-120100.local",   // 没有表头，孤行不足以认定格式
            "Snapshots for something else entirely:",           // 两种已知表头都不匹配
            "",
            "   \n\t\n",
        ]
        for text in cases {
            let listing = LocalSnapshotReader.parse(text, fallbackVolume: "/")
            guard case .unavailable(let reason) = listing else {
                return XCTFail("这段输出不该被当成快照清单：\(text)")
            }
            XCTAssertFalse(reason.isEmpty, "不可用必须给出原因")
        }
    }

    func testUnparsableSnapshotNameKeepsEntryButDropsDate() throws {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.local-snapshot-weird
        """
        guard case .available(let snapshots) = LocalSnapshotReader.parse(output),
              let snapshot = snapshots.first else {
            return XCTFail("命名异常也应列出条目")
        }
        XCTAssertNil(snapshot.date, "读不出的时间不许编")
    }

    // MARK: - 命令执行失败也要降级，不能报成"没有快照"

    func testCommandFailureBecomesUnavailable() {
        let listing = LocalSnapshotReader.read(volumePath: "/") { _, _, _ in
            throw LocalSnapshotReader.CommandError.exited(70, "Operation not permitted")
        }
        guard case .unavailable(let reason) = listing else {
            return XCTFail("退出码非 0 不能被当成正常清单")
        }
        XCTAssertTrue(reason.contains("70"), "原始错误码要留着：\(reason)")
    }

    func testMissingBinaryBecomesUnavailable() {
        let listing = LocalSnapshotReader.read(volumePath: "/") { _, _, _ in
            throw LocalSnapshotReader.CommandError.launchFailed("找不到可执行文件")
        }
        guard case .unavailable = listing else { return XCTFail("命令缺失应报告不可用") }
    }

    /// 真机结构断言：不猜这台机器有几条快照，只要求**解析得动**。
    /// 上面那条 bug 正是"样例全对、真机全废"，只有把真机输出喂进来才拦得住。
    /// 快照条数随机器状态变，所以这里不比数量。
    func testRealMachineOutputParses() {
        let listing = LocalSnapshotReader.read(volumePath: "/")
        XCTAssertTrue(listing.isAvailable, "真机 tmutil 输出必须能解析：\(listing.reason ?? "—")")
    }

    /// 默认执行器换成 `CommandRunner` 之后要钉的一条：tmutil 在本机只输出 22 字节，
    /// **"没发作"从来不等于"写对了"**——先等退出再读管道的那一版，遇到超过 64 KB 的
    /// 输出会把自己卡到超时，再把整批丢掉报成"不可用"（P11 的实测形状）。
    /// 这里喂一条必定 512 KB 的命令，走真的执行器，要求整批拿回来。
    func testDefaultRunnerReadsOutputBiggerThanPipeBuffer() throws {
        let text = try LocalSnapshotReader.run(
            executable: "/bin/sh",
            arguments: ["-c", "yes A | head -c 524288"],
            timeout: 10
        )
        XCTAssertEqual(text.count, 524_288,
                       "默认执行器只拿回 \(text.count) 字节（应为 524288）——管道被堵住时的典型读数")
    }

    // MARK: - APFS 可清除空间

    func testPurgeableIsTheDifferenceBetweenTheTwoCapacityReadings() {
        let report = PurgeableSpaceReport(
            volumeName: "Macintosh HD", volumePath: "/", totalCapacity: 1_000,
            availableForImportantUsage: 700, availableCapacity: 500,
            isAvailable: true, reason: nil
        )
        XCTAssertEqual(report.purgeable, 200)

        // 普通口径偶尔会大于重要用途口径，差额不能报成负数。
        let odd = PurgeableSpaceReport(
            volumeName: "Macintosh HD", volumePath: "/", totalCapacity: 1_000,
            availableForImportantUsage: 400, availableCapacity: 500,
            isAvailable: true, reason: nil
        )
        XCTAssertEqual(odd.purgeable, 0)
    }

    func testPurgeableReadOnARealVolume() throws {
        // 只读地读启动卷（临时目录就在它上面）：口径必须是"重要用途"，且不能是假数字。
        let report = PurgeableSpaceReader.read(at: FileManager.default.temporaryDirectory.path)
        XCTAssertTrue(report.isAvailable, report.reason ?? "读取失败")
        XCTAssertGreaterThan(report.totalCapacity, 0)
        XCTAssertGreaterThanOrEqual(report.availableForImportantUsage, report.availableCapacity)
    }

    func testPurgeableReadOnMissingPathSaysWhy() {
        let report = PurgeableSpaceReader.read(at: "/definitely-not-a-volume-\(UUID().uuidString)")
        XCTAssertFalse(report.isAvailable)
        XCTAssertNotNil(report.reason)
    }
}
