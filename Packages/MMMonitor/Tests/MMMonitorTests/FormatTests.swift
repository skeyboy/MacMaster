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

    // MARK: 采样器产出的数值经格式化后的显示口径

    func testSnapshotRateFormatsThroughMMFormat() {
        let bytesPerSecond = 2_097_152.0 // 2 MB/s
        XCTAssertEqual(MMFormat.compactBytes(UInt64(bytesPerSecond)) + "/s", "2.0 MB/s")
        // "—" 路径（nil）由 MetricSnapshot 表达，格式化层不参与猜数。
        XCTAssertEqual(MenuBarManager.percentText(nil), "—")
    }
}
