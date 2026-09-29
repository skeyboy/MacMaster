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
        let listing = TimeMachineSnapshotReader.parse(output, fallbackVolume: "/")
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

    func testParsesPerVolumeHeadersAndIgnoresNoiseLines() throws {
        let output = """
        Snapshots for disk /System/Volumes/Data:
        com.apple.TimeMachine.2026-04-30-221105.local
        warning: something unrelated
        Snapshots for disk /:
        """
        let listing = TimeMachineSnapshotReader.parse(output, fallbackVolume: "/")
        guard case .available(let snapshots) = listing else {
            return XCTFail("应当解析成功，实际不可用：\(listing.reason ?? "—")")
        }
        XCTAssertEqual(snapshots.count, 1, "非快照行不能被当成快照计入")
        XCTAssertEqual(snapshots[0].volumePath, "/System/Volumes/Data")
    }

    func testHeaderWithoutSnapshotsMeansNoSnapshots() throws {
        let listing = TimeMachineSnapshotReader.parse("Snapshots for disk /:\n", fallbackVolume: "/")
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
            "",
            "   \n\t\n",
        ]
        for text in cases {
            let listing = TimeMachineSnapshotReader.parse(text, fallbackVolume: "/")
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
        guard case .available(let snapshots) = TimeMachineSnapshotReader.parse(output),
              let snapshot = snapshots.first else {
            return XCTFail("命名异常也应列出条目")
        }
        XCTAssertNil(snapshot.date, "读不出的时间不许编")
    }

    // MARK: - 命令执行失败也要降级，不能报成"没有快照"

    func testCommandFailureBecomesUnavailable() {
        let listing = TimeMachineSnapshotReader.read(volumePath: "/") { _, _, _ in
            throw TimeMachineSnapshotReader.CommandError.exited(70, "Operation not permitted")
        }
        guard case .unavailable(let reason) = listing else {
            return XCTFail("退出码非 0 不能被当成正常清单")
        }
        XCTAssertTrue(reason.contains("70"), "原始错误码要留着：\(reason)")
    }

    func testMissingBinaryBecomesUnavailable() {
        let listing = TimeMachineSnapshotReader.read(volumePath: "/") { _, _, _ in
            throw TimeMachineSnapshotReader.CommandError.launchFailed("找不到可执行文件")
        }
        guard case .unavailable = listing else { return XCTFail("命令缺失应报告不可用") }
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
