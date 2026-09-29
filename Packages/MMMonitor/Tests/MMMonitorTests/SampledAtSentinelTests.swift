//
//  SampledAtSentinelTests.swift — "还没采过"这一帧的口径
//
//  sampledAt 用的是 Date 而不是 Date?，`.distantPast` 因此兼任"未采样"哨兵。
//  凡是准备把"没有值"说成一个具体失败原因的地方，都得先看这个哨兵——
//  否则页头会写出"上次采样 0001-01-01 08:05"，内存卡会把"还没采到"说成
//  "host_statistics64 失败"。这两处都是虚报，测试把它们钉住。
//

import XCTest
@testable import MMMonitor

final class SampledAtSentinelTests: XCTestCase {

    func testEmptySnapshotDoesNotClaimToHaveSampled() {
        XCTAssertFalse(MetricSnapshot.empty.hasSampled)
    }

    func testAnyRealTimestampCountsAsSampled() {
        XCTAssertFalse(MetricSnapshot.empty.with(sampledAt: .distantPast).hasSampled)
        XCTAssertTrue(MetricSnapshot.empty.with(sampledAt: Date(timeIntervalSince1970: 1)).hasSampled)
        XCTAssertTrue(MetricSnapshot.empty.with(sampledAt: Date()).hasSampled)
    }

    func testEmptySnapshotSaysItHasNotSampledYet() {
        guard case .unavailable(let reason) = MetricSnapshot.empty.diskIOStatus else {
            return XCTFail("empty 的磁盘 IO 应处于不可用档")
        }
        XCTAssertEqual(reason, "尚未完成首次采样")
    }
}

private extension MetricSnapshot {
    func with(sampledAt: Date) -> MetricSnapshot {
        MetricSnapshot(totalCPU: totalCPU, perCoreCPU: perCoreCPU, diskIOStatus: diskIOStatus,
                       diskReadBytesPerSecond: diskReadBytesPerSecond,
                       diskWriteBytesPerSecond: diskWriteBytesPerSecond,
                       memory: memory, networkDownBytesPerSecond: networkDownBytesPerSecond,
                       networkUpBytesPerSecond: networkUpBytesPerSecond, sampledAt: sampledAt)
    }
}
