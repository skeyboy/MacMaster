//
//  HotBandTests.swift — I11：温度"转红"的进出双阈值判定
//
//  这套测试钉的是**颜色不该闪**这一件事。本机截图负载下最高温度实测 89.4 °C，
//  离进阈值 90 只差 0.6 °C，而采样每 2 秒一帧（fidelity-monitor.md §2.13）：
//  单点判定下 89.x↔90.x 的振荡会把同一行的颜色每帧翻一次。
//  阈值本身（90 / 85）是产品口径，写在 MonitorView 里；这里测的是机制。
//

import XCTest
@testable import MMMonitor

private let band = HotBand(enter: 90, exit: 85)

final class HotBandTests: XCTestCase {

    // MARK: - 判定

    func testColdRowNeedsEnterThresholdToTurnRed() {
        XCTAssertFalse(band.isHot(value: 89.4, alreadyHot: false))
        XCTAssertFalse(band.isHot(value: 89.99, alreadyHot: false))
        XCTAssertTrue(band.isHot(value: 90, alreadyHot: false))
    }

    /// 迟滞的正面：已经红着的行，回到 enter 以下、exit 以上时**保持红**——
    /// 这一条就是防闪的全部内容。
    func testHotRowStaysRedBetweenExitAndEnter() {
        XCTAssertTrue(band.isHot(value: 89.4, alreadyHot: true))
        XCTAssertTrue(band.isHot(value: 85.1, alreadyHot: true))
        XCTAssertTrue(band.isHot(value: 85, alreadyHot: true))
    }

    /// 迟滞的反面：跌进出阈值以下才复原，之后要重新够到进阈值才会再红。
    func testHotRowClearsOnlyBelowExit() {
        XCTAssertFalse(band.isHot(value: 84.9, alreadyHot: true))
        XCTAssertFalse(band.isHot(value: 84.9, alreadyHot: false))
    }

    func testMissingReadingIsNeverHot() {
        XCTAssertFalse(band.isHot(value: nil, alreadyHot: true))
        XCTAssertFalse(band.isHot(value: nil, alreadyHot: false))
    }

    // MARK: - 逐帧集合

    /// 这就是真机上会发生的序列：89.4 → 90.1 → 89.8 → 90.2。
    /// 单点判定给的是「白 红 白 红」（频闪）；迟滞给的是「白 红 红 红」。
    func testOscillationJustAboveEnterFlipsColorOnceNotFourTimes() {
        var track = HotBandTrack()
        var seen: [Bool] = []
        for value in [89.4, 90.1, 89.8, 90.2] {
            track.update([(key: "TZZa", value: value)], band: band)
            seen.append(track.isHot("TZZa"))
        }
        XCTAssertEqual(seen, [false, true, true, true])
    }

    /// 另一头：从热里往下摆，86 → 84 → 86 → 84 只翻两次（红→白，之后保持白），
    /// 不会因为在 85 上下摆动就再闪。
    func testOscillationJustBelowExitClearsOnceAndStaysCleared() {
        var track = HotBandTrack()
        track.update([(key: "TZZa", value: 92)], band: band)
        var seen: [Bool] = []
        let belowExit: [Double] = [86, 84, 86, 84]
        for value in belowExit {
            track.update([(key: "TZZa", value: value)], band: band)
            seen.append(track.isHot("TZZa"))
        }
        XCTAssertEqual(seen, [true, false, false, false])
    }

    func testKeysAreIndependentAndAbsentKeysDropOut() {
        var track = HotBandTrack()
        track.update([(key: "TZZa", value: 95), (key: "TZZb", value: 71.5)], band: band)
        XCTAssertEqual(track.hotKeys, ["TZZa"])

        // 下一帧 TZZa 读不到了：掉出集合，不需要为它单独写"退出"判定。
        track.update([(key: "TZZb", value: 71.5), (key: "TZZc", value: 91)], band: band)
        XCTAssertEqual(track.hotKeys, ["TZZc"])
    }

    /// 排序变了不影响判定——键是身份，位置不是（本卡按键值降序，同值按键名升序）。
    func testReorderDoesNotChangeWhoIsHot() {
        var track = HotBandTrack()
        track.update([(key: "TZZa", value: 95), (key: "TZZb", value: 88)], band: band)
        track.update([(key: "TZZb", value: 88), (key: "TZZa", value: 88)], band: band)
        XCTAssertEqual(track.hotKeys, ["TZZa"])
    }
}
