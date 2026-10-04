//
//  MetricDiffTests.swift — 差分纯函数与采样器的单元测试
//
//  全部用假计数器 + 假时钟，不触碰真实系统调用；口径注释见 MetricTypes.swift 头注
//  （读数口径参考 exelban/stats，MIT License, Copyright (c) 2019 Serhiy Mytrovtsiy）。
//

import XCTest
@testable import MMMonitor

final class MetricDiffTests: XCTestCase {

    // MARK: CPU — 两组计数器得出正确百分比

    func testPerCoreUsageComputesDelta() {
        let prev = [
            CoreTicks(user: 100, system: 50, idle: 300, nice: 50),
            CoreTicks(user: 10, system: 10, idle: 480, nice: 0),
        ]
        let cur = [
            CoreTicks(user: 150, system: 75, idle: 375, nice: 75), // Δbusy=100 Δidle=75 Δtotal=175 → 100/175
            CoreTicks(user: 10, system: 10, idle: 480, nice: 0),    // 无增量 → nil，不是 0%
        ]
        let usage = CPUDiff.perCoreUsage(previous: prev, current: cur)
        XCTAssertEqual(usage.count, 2)
        XCTAssertEqual(usage[0]!, 100.0 / 175.0, accuracy: 0.0001)
        XCTAssertNil(usage[1], "零增量应给 \"—\" 而不是 0%")
    }

    func testFirstSampleYieldsPlaceholderNotZero() {
        let cur = [CoreTicks(user: 10, system: 1, idle: 5, nice: 1)]
        let usage = CPUDiff.perCoreUsage(previous: nil, current: cur)
        XCTAssertEqual(usage, [nil])
        XCTAssertFalse(usage.contains { $0 == 0 })
        XCTAssertEqual(MenuBarManager.percentText(usage[0]), "—")
        XCTAssertNil(CPUDiff.totalUsage(previous: nil, current: cur[0]))
    }

    func testCounterWraparoundYieldsPlaceholder() {
        let prev = CoreTicks(user: 500, system: 200, idle: 1000, nice: 50)
        let reset = CoreTicks(user: 10, system: 200, idle: 1000, nice: 50) // user 变小 = 计数器重置
        XCTAssertNil(CPUDiff.usage(before: prev, after: reset))
        XCTAssertNil(CPUDiff.totalUsage(previous: prev, current: reset))

        let idleReset = CoreTicks(user: 501, system: 201, idle: 999, nice: 51)
        XCTAssertNil(CPUDiff.usage(before: prev, after: idleReset), "任何一路回绕都要报 —，禁止负数")
    }

    func testCoreCountMismatchYieldsAllPlaceholder() {
        let prev = [CoreTicks(user: 1, system: 1, idle: 1, nice: 1)]
        let cur = [CoreTicks(user: 2, system: 2, idle: 2, nice: 2),
                   CoreTicks(user: 3, system: 3, idle: 3, nice: 3)]
        XCTAssertEqual(CPUDiff.perCoreUsage(previous: prev, current: cur), [nil, nil])
    }

    // MARK: 磁盘 IO 速率

    func testDiskRateComputesBytesPerSecond() {
        let prev = DiskIOCounters(readBytes: 1_000, writeBytes: 2_000)
        let cur = DiskIOCounters(readBytes: 3_000, writeBytes: 2_000)
        let rate = DiskIODiff.rate(previous: prev, current: cur, interval: 2)!
        XCTAssertEqual(rate.readBytesPerSecond!, 1_000, accuracy: 0.001)
        XCTAssertEqual(rate.writeBytesPerSecond!, 0, accuracy: 0.001)
    }

    func testDiskRateFirstSampleAndZeroIntervalArePlaceholder() {
        let cur = DiskIOCounters(readBytes: 3_000, writeBytes: 1)
        XCTAssertNil(DiskIODiff.rate(previous: nil, current: cur, interval: 2))
        XCTAssertNil(DiskIODiff.rate(previous: cur, current: cur, interval: 0), "零间隔不给速率")
        XCTAssertNil(DiskIODiff.rate(previous: cur, current: cur, interval: -1))
    }

    func testDiskCounterResetIsPerChannelPlaceholder() {
        let prev = DiskIOCounters(readBytes: 5_000, writeBytes: 5_000)
        let cur = DiskIOCounters(readBytes: 100, writeBytes: 9_000) // read 回绕、write 正常
        let rate = DiskIODiff.rate(previous: prev, current: cur, interval: 1)!
        XCTAssertNil(rate.readBytesPerSecond, "回绕的一路报 —")
        XCTAssertEqual(rate.writeBytesPerSecond!, 4_000, accuracy: 0.001, "另一路照常出数")
    }

    // MARK: 网络差分

    func testNetworkResetAndZeroInterval() {
        let prev = NetworkBytes(received: 100, sent: 100)
        let cur = NetworkBytes(received: 50, sent: 300)
        let rate = NetworkDiff.rate(previous: prev, current: cur, interval: 5)!
        XCTAssertNil(rate.downBytesPerSecond)
        XCTAssertEqual(rate.upBytesPerSecond!, 40, accuracy: 0.001)
        XCTAssertNil(NetworkDiff.rate(previous: prev, current: cur, interval: 0))
    }

    // MARK: 采样器（注入假时钟/假计数器）

    func testSamplerFirstTickAllRatesNilThenComputes() {
        let fakeTime = 1_000.0
        let diskTicks: Result<DiskIOCounters, DiskIOFailure> = .success(DiskIOCounters(readBytes: 0, writeBytes: 0))
        let mem = MemoryMetrics(
            totalBytes: 8_000, activeBytes: 1_000, wiredBytes: 500, compressedBytes: 250,
            swapUsedBytes: 7, swapTotalBytes: 100, swapAvailable: true
        )

        var sampler = SystemMetricSampler(
            readers: .init(
                perCoreCPU: { [CoreTicks(user: 0, system: 0, idle: 100, nice: 0)] },
                totalCPU: { CoreTicks(user: 0, system: 0, idle: 100, nice: 0) },
                diskIO: { diskTicks },
                memory: { mem },
                network: { NetworkBytes(received: 0, sent: 0) },
                sensors: { .loaded(temperatures: [SensorTemperature(key: "TZZa", celsius: 50)], fanCount: 0, fans: []) }
            ),
            clock: MetricClock { fakeTime }
        )

        let first = sampler.tick()
        XCTAssertNil(first.totalCPU, "首帧 CPU 必须是 —")
        XCTAssertEqual(first.perCoreCPU, [nil])
        XCTAssertNil(first.diskReadBytesPerSecond)
        XCTAssertEqual(first.memory?.compressedBytes, 250, "内存是瞬时值，首帧就有")
        XCTAssertEqual(first.sensors.status, .loaded, "温度/风扇也是瞬时值，首帧就有")
    }

    func testSamplerComputesRatesOnSecondTick() {
        var fakeTime = 0.0
        var core = CoreTicks(user: 0, system: 0, idle: 100, nice: 0)
        var disk = DiskIOCounters(readBytes: 100, writeBytes: 50)
        var net = NetworkBytes(received: 10, sent: 10)

        var sampler = SystemMetricSampler(
            readers: .init(
                perCoreCPU: { [core] },
                totalCPU: { core },
                diskIO: { .success(disk) },
                memory: { nil },
                network: { net },
                sensors: { .notSampled }
            ),
            clock: MetricClock { fakeTime }
        )

        let first = sampler.tick()
        XCTAssertNil(first.totalCPU)

        fakeTime = 2.0
        core = CoreTicks(user: 50, system: 0, idle: 150, nice: 0) // Δbusy 50, Δidle 50 → 50%
        disk = DiskIOCounters(readBytes: 2_100, writeBytes: 50)
        net = NetworkBytes(received: 10, sent: 10)
        let second = sampler.tick()
        XCTAssertEqual(second.totalCPU!, 0.5, accuracy: 0.0001)
        XCTAssertEqual(second.perCoreCPU, [0.5])
        XCTAssertEqual(second.diskReadBytesPerSecond!, 1_000, accuracy: 0.001, "按真实间隔 2s 差分成 1000 B/s")
        XCTAssertEqual(second.diskWriteBytesPerSecond!, 0, accuracy: 0.001)
        XCTAssertEqual(second.diskIOStatus, .ok)
    }

    func testSamplerReportsDiskUnavailableWithReason() {
        var fakeTime = 0.0
        var sampler = SystemMetricSampler(
            readers: .init(
                perCoreCPU: { [] },
                totalCPU: { nil },
                diskIO: { .failure(DiskIOFailure("未发现任何 IOBlockStorageDriver 设备")) },
                memory: { nil },
                network: { nil },
                sensors: { .notSampled }
            ),
            clock: MetricClock { fakeTime }
        )
        fakeTime = 1.0
        let snap = sampler.tick()
        XCTAssertEqual(snap.diskIOStatus, .unavailable(reason: "未发现任何 IOBlockStorageDriver 设备"))
        XCTAssertNil(snap.diskReadBytesPerSecond)
    }

    // MARK: 菜单栏文本：nil → "—"

    func testPercentTextMapping() {
        XCTAssertEqual(MenuBarManager.percentText(0.0), "0.0%")
        XCTAssertEqual(MenuBarManager.percentText(0.6667), "66.7%")
        XCTAssertEqual(MenuBarManager.percentText(nil), "—")
    }
}
