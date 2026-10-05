//
//  ActivityScannerLogRowTests.swift — `log show` 定宽列拆行的纯函数测试
//
//  这一路是 P11 实测轮修出来的三处用户可见错误里的后两处：修好管道死锁之后，
//  活动卡第一次真的有 5 条「系统日志事件」，可每条只有列宽（日期 时间 线程 类型
//  Activity PID TTL 就占 78 个字符，而旧代码截的是前 80 个），正文一个字都没有；
//  而 `log show` 是升序输出的，`prefix(5)` 拿到的又是最旧的 5 条。
//  所以这里盯的是"正文有没有活下来、这 5 条是不是真的最近"，不是"有没有崩"。
//
//  零系统调用：喂进去的是从本机 `log show` 抄下来的行形状。
//

import XCTest
@testable import MMGuardian

final class ActivityScannerLogRowTests: XCTestCase {

    func testRealColumnPaddedRowKeepsTheMessage() {
        let line = "2026-10-05 14:57:15.732004+0800 0x19dd     Error       0x0                  709    3    "
            + "sharingd: (CoreUtils) [com.apple.sharing:SDNearbyAgentCore] ### Unable to decrypt activity level"
        let row = ActivityScanner.unifiedLogRow(line)
        XCTAssertTrue(row.contains("Unable to decrypt activity level"), "正文被列宽挤掉了：\(row)")
        XCTAssertTrue(row.contains("sharingd:"), "进程名是这行最有用的信息：\(row)")
        XCTAssertTrue(row.contains("14:57:15.732004+0800"), "卡片 time 只有「最近」，行内得留时间：\(row)")
        XCTAssertFalse(row.contains("0x19dd"), "列宽不该出现在正文里：\(row)")
    }

    func testDefaultTypeRowKeepsTheMessage() {
        // Default 一行的列宽和 Error 不同，拆列不能按字符数、只能按空格段。
        let line = "2026-10-05 14:57:50.902484+0800 0x33cc8b   Default     0x0                  466    0    "
            + "airportd: (CFNetwork) [com.apple.CFNetwork:Default] Task auth completion disp=1 cred=0"
        let row = ActivityScanner.unifiedLogRow(line)
        XCTAssertTrue(row.contains("auth completion"), row)
        XCTAssertFalse(row.contains("0x33cc8b"), row)
    }

    func testShortLineFallsBackToRawText() {
        // 换行续行 / 别的 `log` 版本少列：宁可难看，不能丢事件。
        let line = "some continuation text"
        XCTAssertEqual(ActivityScanner.unifiedLogRow(line), "some continuation text")
    }

    func testRowWithColumnsButNoMessageFallsBack() {
        let line = "2026-10-05 14:57:15.732004+0800 0x19dd     Error       0x0                  709    3"
        XCTAssertEqual(ActivityScanner.unifiedLogRow(line), String(line.prefix(120)))
    }

    func testLongMessageIsTruncated() {
        let line = "2026-10-05 14:57:15.732004+0800 0x19dd     Error       0x0                  709    3    "
            + String(repeating: "x", count: 400)
        XCTAssertEqual(ActivityScanner.unifiedLogRow(line).count, 140)
    }

    // MARK: - 折行续行不能顶成第 6 条事件

    func testHeaderAndContinuationLines() {
        let output = """
        Timestamp                       Thread     Type        Activity             PID    TTL
        2026-10-05 15:00:20.737846+0800 0x1f2a     Default     0x0                  341    0    runningboardd: (C5AFC) RBConnectionListener
        <RBConnectionListener| clients:[
        com.apple.cfprefsd]
        2026-10-05 15:00:21.100000+0800 0x1f2b     Default     0x0                  341    0    airportd: auth completion
        """
        let records = ActivityScanner.groupLogRecords(output)
        XCTAssertEqual(records.count, 2, "列标题不算事件，两条续行算进上一条：\(records)")
        XCTAssertTrue(records[0].contains("clients:["), "续行内容该并进上一条：\(records[0])")
        XCTAssertTrue(records[1].hasPrefix("2026-10-05 15:00:21"), records[1])
    }

    func testRecordsWithoutAnyTimestampAreNotDropped() {
        // 认不出时间戳就整批丢掉，等于把"这台机器有事件"读成"没有事件"——
        // 这一轮已经栽过一次静默空值了，不再给第二次机会。
        // 换行的处理规则在这里是"没有父行就先立一条，其余并进去"，所以别的 `log` 版本
        // 最坏退化成一条内容很长的记录，而不是一行都不剩。
        let records = ActivityScanner.groupLogRecords("weird line one\nweird line two")
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].contains("weird line one"))
        XCTAssertTrue(records[0].contains("weird line two"))
    }

    func testIsLogRecordLineRejectsLookalikes() {
        XCTAssertTrue(ActivityScanner.isLogRecordLine("2026-10-05 15:00:03.019740+0800 x"))
        XCTAssertFalse(ActivityScanner.isLogRecordLine("Timestamp Thread Type"))
        XCTAssertFalse(ActivityScanner.isLogRecordLine("2026x10-05 15:00"))
        XCTAssertFalse(ActivityScanner.isLogRecordLine("2026"))
    }

    // MARK: - 「最近」得真的是最近

    func testRecentRecordsTakeTheNewestEndNotTheOldest() {
        // `log show` 是**升序**输出：首行是窗口起点，末行是"刚刚那一秒"（本机实测，
        // 末行时间戳与 `date` 只差一秒）。旧代码取 `prefix(5)`，于是标着「最近」的卡片
        // 画的是这 5 分钟里**最旧**的 5 条——P11 对照照片里 15:07 拍的那张，5 行全在 15:02。
        let output = (0..<9).map { i in
            "2026-10-05 15:00:0\(i).000000+0800 0x1f2a     Default     0x0                  341    0    airportd: event \(i)"
        }.joined(separator: "\n")
        let records = ActivityScanner.recentLogRecords(of: output)
        XCTAssertEqual(records.count, 5)
        XCTAssertTrue(records[0].contains("event 8"), "第一行该是最新那条：\(records[0])")
        XCTAssertTrue(records[4].contains("event 4"), "5 个名额用完就停：\(records[4])")
    }

    func testRecentRecordsUnderTheLimitStayNewestFirst() {
        let output = "2026-10-05 15:00:01.000000+0800 0x1f2a Default 0x0 341 0 airportd: one\n"
            + "2026-10-05 15:00:02.000000+0800 0x1f2a Default 0x0 341 0 airportd: two"
        let records = ActivityScanner.recentLogRecords(of: output)
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records[0].contains("two"), "\(records)")
        XCTAssertTrue(records[1].contains("one"), "\(records)")
    }
}
