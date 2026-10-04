//
//  FormatTests.swift — 单位换算边界（KB/MB/GB、bytes/s）
//
//  格式化不再在本包私设 formatSize/formatMemory，统一走 MMUI 的 MMFormat；
//  这些用例把"迁移后数字仍然正确"钉住。
//

import XCTest
import MMUI
@testable import MMMonitor

final class FormatTests: XCTestCase {

    // MARK: MMFormat.compactBytes 边界（1024 进制）

    func testCompactBytesBoundaries() {
        XCTAssertEqual(MMFormat.compactBytes(0), "0 B")
        XCTAssertEqual(MMFormat.compactBytes(1_023), "1023 B")
        XCTAssertEqual(MMFormat.compactBytes(1_024), "1.0 KB")
        XCTAssertEqual(MMFormat.compactBytes(1_048_575), "1024.0 KB") // 还差 1B 到 MB
        XCTAssertEqual(MMFormat.compactBytes(1_048_576), "1.0 MB")
        XCTAssertEqual(MMFormat.compactBytes(1_073_741_824), "1.0 GB")
        XCTAssertEqual(MMFormat.compactBytes(1_073_741_824 * 2 + 536_870_912), "2.5 GB")
    }

    // MARK: 速率：调用方按 bytes/s 传，MMFormat 拼箭头与单位

    func testRateFormatting() {
        XCTAssertEqual(MMFormat.rate(1_024, up: true), "↑ 1.0 KB/s")
        XCTAssertEqual(MMFormat.rate(1_048_576, up: false), "↓ 1.0 MB/s")
        XCTAssertEqual(MMFormat.rate(0, up: true), "↑ 0 B/s")
        XCTAssertEqual(MMFormat.rate(1_500, up: false), "↓ 1.5 KB/s")
    }

    // MARK: MMFormat.bytes（ByteCountFormatter 口径）与百分比

    func testBytesAndPercent() {
        // ByteCountFormatter 的空格/小数位随 locale 变化，只对量级作证。
        XCTAssertTrue(MMFormat.bytes(UInt64(1_048_576)).contains("MB"))
        XCTAssertEqual(MMFormat.percent(0.6667), "66.7%")
        XCTAssertEqual(MMFormat.percent(0.004), "0.4%", "0.4% 不能塌成 0%")
    }

    func testSubKilobyteNeverReadsAsZero() {
        // .file 口径下 1 KB = 1000 字节；低于这个门槛必须自己拼中文单位，
        // 否则 ByteCountFormatter 给出 "8 bytes"（中英混排）或 "0 KB"（读起来像空目录）。
        XCTAssertEqual(MMFormat.bytes(UInt64(8)), "8 字节")
        XCTAssertEqual(MMFormat.bytes(UInt64(0)), "0 字节")
        XCTAssertEqual(MMFormat.bytes(Int64(999)), "999 字节")
        XCTAssertFalse(MMFormat.bytes(UInt64(999)).contains("0 KB"))
        XCTAssertTrue(MMFormat.bytes(UInt64(1000)).contains("KB"))
        XCTAssertEqual(MMFormat.bytes(Optional<UInt64>.none), "测量中")
    }

    // MARK: 采样器产出的数值经格式化后的显示口径

    func testSnapshotRateFormatsThroughMMFormat() {
        let bytesPerSecond = 2_097_152.0 // 2 MB/s
        XCTAssertEqual(MMFormat.compactBytes(UInt64(bytesPerSecond)) + "/s", "2.0 MB/s")
        // "—" 路径（nil）由 MetricSnapshot 表达，格式化层不参与猜数。
        XCTAssertEqual(MenuBarManager.percentText(nil), "—")
    }

    // MARK: - Swap 一行（I9）

    private func memory(swapUsed: UInt64, swapTotal: UInt64, available: Bool = true) -> MemoryMetrics {
        MemoryMetrics(
            totalBytes: 24 * 1024 * 1024 * 1024,
            activeBytes: 15_600 * 1024 * 1024,
            wiredBytes: 3_800 * 1024 * 1024,
            compressedBytes: 1_400 * 1024 * 1024,
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal,
            swapAvailable: available)
    }

    /// 读到 0 且总量也是 0：说成一句中文，不是「0 字节 / 0 字节」。
    func testSwapZeroReadsAsASentenceNotTwiceZero() {
        let text = MenuBarManager.swapText(memory(swapUsed: 0, swapTotal: 0))
        XCTAssertEqual(text, "0 字节（未使用）")
        XCTAssertFalse(text.contains("/"), "两侧都是 0 时报一个分量就是噪声")
    }

    /// 只有已用为 0 不代表总量为 0，那种情况照原样报对仗，不替用户下"未使用"的结论。
    func testSwapWithNonZeroTotalKeepsUsedOverTotal() {
        let text = MenuBarManager.swapText(memory(swapUsed: 0, swapTotal: 2_147_483_648))
        XCTAssertTrue(text.contains("/"))
        XCTAssertFalse(text.contains("未使用"))
    }

    func testSwapNonZeroIsPlainPair() {
        let text = MenuBarManager.swapText(memory(swapUsed: 838_860_800, swapTotal: 2_147_483_648))
        XCTAssertTrue(text.contains("/"))
        XCTAssertFalse(text.contains("—"))
    }

    /// "读不到 sysctl" 与 "读到 0" 必须是两句话——前者是 "—"。
    func testSwapUnavailableIsPlaceholder() {
        XCTAssertEqual(MenuBarManager.swapText(memory(swapUsed: 0, swapTotal: 0, available: false)), "—")
    }

    /// 菜单栏那档用紧凑单位，同一句话的口径要跟着行内其他项走。
    func testSwapCompactUsesMenuBarUnits() {
        XCTAssertEqual(MenuBarManager.swapText(memory(swapUsed: 0, swapTotal: 0), compact: true), "0 B（未使用）")
        XCTAssertTrue(MenuBarManager.swapText(memory(swapUsed: 1_048_576, swapTotal: 8_589_934_592), compact: true)
                      .contains("1.0 MB / 8.0 GB"))
    }

    /// 夹具的 swapZero 与 swapOff 只差 swapAvailable 一位，两档必须给出两句话。
    func testSwapZeroTierIsDistinctFromSwapOffTier() {
        let zero = MonitorSnapshotFixture.parse("swapZero").snapshot?.memory
        XCTAssertEqual(zero?.swapAvailable, true)
        XCTAssertEqual(zero?.swapUsedBytes, 0)
        XCTAssertEqual(zero?.swapTotalBytes, 0)
        XCTAssertEqual(MenuBarManager.swapText(zero!), "0 字节（未使用）")

        let off = MonitorSnapshotFixture.parse("swapOff").snapshot?.memory
        XCTAssertEqual(off?.swapAvailable, false)
        XCTAssertEqual(MenuBarManager.swapText(off!), "—")
    }
}
