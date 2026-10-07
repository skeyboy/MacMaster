//
//  CleanerHeaderContractTests.swift — 清理页页头副标题的段序合同
//
//  这一条缺口是 P24 的窄窗照片照出来的（`release-readiness.md` §7.15 第 ③ 条、§8）：
//  窗口 1000 pt 宽时副标题被**中间截断**，画面上是 `可释放 3.74 GB…MB 只读`——
//  被吃掉的正好是"另有 N 只读"那个数字，而它单独存在的理由就是"只读档混进可释放里
//  就是一个偏大的假数字"。**段序在这里不是排版问题，是"用户看见哪一句话"的问题。**
//
//  所以这里钉三件事：① 会被人当成"能删多少"的那两段必须在**尾部**（中间截断保头保尾）；
//  ② 时间戳不许占尾部；③ 只读那一档为零时整段不出现（不许写"另有 0 字节 只读"）。
//
//  钉不住的那一半写在这儿：单测能钉段序，钉不住"这一句在 1000 pt 放不放得下"——
//  那要实机照片，判据与复现命令见 `fidelity-cleaner.md` 与 `release-readiness.md` §7.16。
//

import XCTest
import MMUI
@testable import MMCleaner

final class CleanerHeaderContractTests: XCTestCase {

    private func segments(readOnlyTotal: UInt64,
                          isScanning: Bool = false,
                          isPartial: Bool = false,
                          scannedAt: Date? = Date(timeIntervalSince1970: 1_760_000_000)) -> [String] {
        CleanerHeaderCopy.subtitleSegments(isScanning: isScanning,
                                           scanningCategoryName: isScanning ? "缓存" : nil,
                                           categoryCount: 16,
                                           measuredTotal: 4_026_531_840,
                                           readOnlyTotal: readOnlyTotal,
                                           scannedAt: scannedAt,
                                           isPartial: isPartial)
    }

    /// 中间截断只吃中段，所以尾部那两段就是"窄窗上也必须看得见"的那两段。
    func testReclaimableAndReadOnlySegmentsHoldTheTail() {
        let s = segments(readOnlyTotal: 140_278_720)
        // 满档就四段：已扫描 N 类 · 时间 · 可释放 X · 另有 Y 只读。
        // 多一段就是有人往头部前面加了东西，把只读往后推。
        XCTAssertEqual(s.count, 4)
        XCTAssertTrue(s[s.count - 1].contains("只读"), "最后一段是「\(s[s.count - 1])」，只读那一档不在尾部")
        XCTAssertTrue(s[s.count - 2].hasPrefix("可释放"), "倒数第二段是「\(s[s.count - 2])」")
    }

    func testTimestampNeverTakesTheTail() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let s = segments(readOnlyTotal: 140_278_720, scannedAt: date)
        let index = s.firstIndex(of: MMFormat.dateTime(date))
        XCTAssertNotNil(index, "副标题里没有那枚时间戳，这一条判据等于没跑")
        // 尾部两格是"可释放 + 另有 N 只读"。时间戳一旦挤进去，中间截断吃掉的就是只读那句。
        XCTAssertLessThan(index ?? .max, s.count - 2,
                          "时间戳占了尾部：\(s.joined(separator: " · "))")
    }

    func testZeroReadOnlyWritesNoSegmentAtAll() {
        let s = segments(readOnlyTotal: 0)
        XCTAssertFalse(s.contains { $0.contains("只读") }, "零只读时不该出现这一句，更不该占住尾部")
        XCTAssertTrue(s.last?.hasPrefix("可释放") ?? false)
    }

    /// 「未完成」说的是这一趟扫描没走完，它必须留在头部那一截里，不然窄窗看不见。
    func testPartialFlagStaysInHead() {
        let s = segments(readOnlyTotal: 140_278_720, isPartial: true)
        XCTAssertEqual(s[1], "未完成")
        XCTAssertNotEqual(s.last, "未完成")
    }

    func testScanningBranchHasNoScannedCounts() {
        let s = segments(readOnlyTotal: 140_278_720, isScanning: true, scannedAt: nil)
        XCTAssertEqual(s, ["正在扫描 缓存"])
    }

    func testNoTimestampStillLeavesTheTailIntact() {
        let s = segments(readOnlyTotal: 140_278_720, scannedAt: nil)
        // 时间戳是可以没有的（从没扫过就没得报），尾部那两段不行。
        XCTAssertEqual(s.count, 3)
        XCTAssertTrue(s.last?.contains("只读") ?? false)
    }
}
