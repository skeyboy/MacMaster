//
//  SystemMetricSampler.swift — 采样节拍组装层
//
//  readers 与 clock 都可注入：单元测试喂假计数器与假时钟即可复现
//  首帧/回绕/零间隔全部路径；生产代码用 .live。
//  采样在后台线程执行（调用方负责），本类型只保证"每次 tick 读一组计数器、
//  与上一组做差分"，不触碰任何 UI。
//

import Foundation

/// 单调时钟（秒）。用 CLOCK_MONOTONIC，系统唤醒/改表不受影响。
public struct MetricClock: Sendable {
    public let now: @Sendable () -> TimeInterval

    public init(now: @escaping @Sendable () -> TimeInterval) {
        self.now = now
    }

    public static let monotonic = MetricClock {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}

public struct SystemMetricSampler {

    /// 一组可替换的数据源；签名返回"累计计数器"，差分一律在本类型内完成。
    public struct Readers: Sendable {
        public var perCoreCPU: @Sendable () -> [CoreTicks]?
        public var totalCPU: @Sendable () -> CoreTicks?
        public var diskIO: @Sendable () -> Result<DiskIOCounters, DiskIOFailure>
        public var memory: @Sendable () -> MemoryMetrics?
        public var network: @Sendable () -> NetworkBytes?
        /// 温度/风扇：SMC 的瞬时量，不做差分，所以签名直接给整卡状态
        /// （读不到时 reason 已经在里面，tick 不参与）。
        public var sensors: @Sendable () -> SensorsSnapshot
        /// 电池：AppleSmartBattery 的瞬时量，同样不做差分。
        public var battery: @Sendable () -> BatterySnapshot

        public init(
            perCoreCPU: @escaping @Sendable () -> [CoreTicks]?,
            totalCPU: @escaping @Sendable () -> CoreTicks?,
            diskIO: @escaping @Sendable () -> Result<DiskIOCounters, DiskIOFailure>,
            memory: @escaping @Sendable () -> MemoryMetrics?,
            network: @escaping @Sendable () -> NetworkBytes?,
            sensors: @escaping @Sendable () -> SensorsSnapshot,
            battery: @escaping @Sendable () -> BatterySnapshot
        ) {
            self.perCoreCPU = perCoreCPU
            self.totalCPU = totalCPU
            self.diskIO = diskIO
            self.memory = memory
            self.network = network
            self.sensors = sensors
            self.battery = battery
        }

        public static let live = Readers(
            perCoreCPU: { HostCPUReader.perCoreTicks() },
            totalCPU: { HostCPUReader.totalTicks() },
            diskIO: { DiskIOReader.read() },
            memory: { MemoryReader.read() },
            network: { NetworkReader.read() },
            sensors: { SMCSensorReader.shared.read() },
            battery: { BatteryReader.read() }
        )
    }

    private struct Previous {
        var perCore: [CoreTicks]?
        var total: CoreTicks?
        var disk: DiskIOCounters?
        var network: NetworkBytes?
        var clockTime: TimeInterval?
    }

    public var readers: Readers
    public var clock: MetricClock
    private var previous = Previous()

    public init(readers: Readers = .live, clock: MetricClock = .monotonic) {
        self.readers = readers
        self.clock = clock
    }

    /// 采一帧。首帧（无上一组计数器）各速率/CPU 全为 nil，内存和 SMC 温度是瞬时值所以有。
    /// interval 用两次 clock 读数之差，而不是"配置里写死的 2 秒"——
    /// 主线程拥塞导致 tick 迟到时，差分仍然除以真实间隔。
    public mutating func tick(sampledAt: Date = Date()) -> MetricSnapshot {
        let now = clock.now()
        let interval = previous.clockTime.map { now - $0 }

        let perCoreNow = readers.perCoreCPU()
        let totalNow = readers.totalCPU()
        let diskNow = readers.diskIO()
        let networkNow = readers.network()

        let perCore = CPUDiff.perCoreUsage(previous: previous.perCore, current: perCoreNow ?? [])
        let total = totalNow.flatMap { CPUDiff.totalUsage(previous: previous.total, current: $0) }

        var diskStatus: DiskIOStatus = .ok
        var diskRate: DiskIORate?
        switch diskNow {
        case .success(let counters):
            if let interval, interval > 0 {
                diskRate = DiskIODiff.rate(previous: previous.disk, current: counters, interval: interval)
            }
            previous.disk = counters
        case .failure(let error):
            diskStatus = .unavailable(reason: error.reason)
            diskRate = nil
        }

        let netRate: NetworkRate?
        if let networkNow, let interval {
            netRate = NetworkDiff.rate(previous: previous.network, current: networkNow, interval: interval)
        } else {
            netRate = nil
        }

        previous.perCore = perCoreNow
        previous.total = totalNow
        previous.network = networkNow
        previous.clockTime = now

        return MetricSnapshot(
            totalCPU: total,
            perCoreCPU: perCore,
            diskIOStatus: diskStatus,
            diskReadBytesPerSecond: diskRate?.readBytesPerSecond,
            diskWriteBytesPerSecond: diskRate?.writeBytesPerSecond,
            memory: readers.memory(),
            networkDownBytesPerSecond: netRate?.downBytesPerSecond,
            networkUpBytesPerSecond: netRate?.upBytesPerSecond,
            sensors: readers.sensors(),
            battery: readers.battery(),
            sampledAt: sampledAt
        )
    }
}
