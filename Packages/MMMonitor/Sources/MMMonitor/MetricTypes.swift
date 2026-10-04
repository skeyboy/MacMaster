//
//  MetricTypes.swift — 监控指标的纯函数层
//
//  读数口径参考 exelban/stats（MIT License, Copyright (c) 2019 Serhiy Mytrovtsiy）：
//  - 每核 CPU：host_processor_info(PROCESSOR_CPU_LOAD_INFO) 两次采样差分
//    （stats/Modules/CPU/readers.swift 的做法）；
//  - 磁盘 IO：IOKit IOBlockStorageDriver 的 "Statistics" 字典 Bytes (Read)/Bytes (Write) 差分
//    （stats/Modules/Disk/readers.swift 的做法）。
//  本文件为独立实现，未复制 stats 源码（MIT 要求保留署名，见上文）。
//
//  约定：
//  - 所有差分都是纯函数：入参两组计数器 + 时钟读数，出参 Optional；
//    可测、不触碰系统调用。采样节拍在 SystemMetricSampler 里用可注入 readers/clock 组装。
//  - "量不出" 一律用 nil 表达（UI 显示 "—"），绝不塌成 0%：
//    首次采样、计数器回绕（新值 < 旧值，视为重置）、零间隔、总数为 0 都返回 nil。
//

import Foundation

// MARK: - CPU

/// 单个核（或总体 host_cpu_load_info）的四状态累计 tick。
public struct CoreTicks: Equatable, Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    /// 用 UInt64 累加，避免四状态相加在 UInt32 上溢出。
    public var busyTicks: UInt64 { UInt64(user) + UInt64(system) + UInt64(nice) }
    public var totalTicks: UInt64 { busyTicks + UInt64(idle) }
}

public enum CPUDiff {

    /// 单组差分占用率（0...1）。任何一路计数器回绕（新值 < 旧值）视为计数器重置 → nil；
    /// 总增量（含 idle）为 0（同一时刻重复采样）也给 nil，而不是 0% 或 NaN。
    public static func usage(before: CoreTicks, after: CoreTicks) -> Double? {
        guard after.user >= before.user,
              after.system >= before.system,
              after.idle >= before.idle,
              after.nice >= before.nice
        else { return nil }
        let deltaTotal = after.totalTicks &- before.totalTicks
        guard deltaTotal > 0 else { return nil }
        let deltaIdle = UInt64(after.idle) &- UInt64(before.idle)
        return min(1.0, max(0.0, 1.0 - Double(deltaIdle) / Double(deltaTotal)))
    }

    /// 每核占用。previous == nil（首次采样）或核数对不上（热插拔/口径变化）
    /// 时整列返回 nil —— UI 据此显示 "—"，不返回 0%。
    public static func perCoreUsage(previous: [CoreTicks]?, current: [CoreTicks]) -> [Double?] {
        guard let previous, previous.count == current.count else {
            return Array(repeating: nil, count: current.count)
        }
        return zip(previous, current).map { usage(before: $0, after: $1) }
    }

    /// 总占用：口径与每核一致（user+system+nice 增量 / 总增量）。
    public static func totalUsage(previous: CoreTicks?, current: CoreTicks) -> Double? {
        guard let previous else { return nil }
        return usage(before: previous, after: current)
    }
}

// MARK: - 磁盘 IO

/// 所有 IOBlockStorageDriver 实例汇总后的累计字节数。
public struct DiskIOCounters: Equatable, Sendable {
    public let readBytes: UInt64
    public let writeBytes: UInt64

    public init(readBytes: UInt64, writeBytes: UInt64) {
        self.readBytes = readBytes
        self.writeBytes = writeBytes
    }
}

/// 每秒字节速率；单路 nil 表示该路计数器回绕/无法计算，UI 显示 "—"。
public struct DiskIORate: Equatable, Sendable {
    public let readBytesPerSecond: Double?
    public let writeBytesPerSecond: Double?

    public init(readBytesPerSecond: Double?, writeBytesPerSecond: Double?) {
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
    }

    public static let unavailable = DiskIORate(readBytesPerSecond: nil, writeBytesPerSecond: nil)
}

/// 磁盘 IO 这一行的可观测状态：unavailable 带一句副标题原文（无权限/无设备），
/// UI 整行显示 "—" 并展示原因，不再静默。
public enum DiskIOStatus: Equatable, Sendable {
    case ok
    case unavailable(reason: String)
}

/// DiskIOReader 失败时携带的原文原因。
public struct DiskIOFailure: Error, Equatable, Sendable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
}

public enum DiskIODiff {

    /// 两次采样的字节差 ÷ 实际间隔。间隔 ≤ 0 或非有限值 → 整体 nil（"零间隔不给速率"）。
    /// 某一路新值 < 旧值 → 该路视为计数器重置，nil，而不是负数。
    public static func rate(previous: DiskIOCounters?, current: DiskIOCounters, interval: TimeInterval) -> DiskIORate? {
        guard let previous, interval > 0, interval.isFinite else { return nil }
        let readRate: Double?
        if current.readBytes >= previous.readBytes {
            readRate = Double(current.readBytes - previous.readBytes) / interval
        } else {
            readRate = nil
        }
        let writeRate: Double?
        if current.writeBytes >= previous.writeBytes {
            writeRate = Double(current.writeBytes - previous.writeBytes) / interval
        } else {
            writeRate = nil
        }
        return DiskIORate(readBytesPerSecond: readRate, writeBytesPerSecond: writeRate)
    }
}

// MARK: - 内存

/// vm_statistics64 + sysctl(xsw_usage) 的一帧内存读数。
///
/// compressed 口径（明确写出，两种口径数字不同，不许混）：
/// 采用 `compressor_page_count × page size`，即压缩器池占用的**物理内存**，
/// 与 MMCore.SystemSampler 的 used = active + wired + compressed 同一口径；
/// 不采用 external_page_count（那是压缩前的逻辑外部分页数，会把"省下的内存"也算成占用）。
public struct MemoryMetrics: Equatable, Sendable {
    public let totalBytes: UInt64
    public let activeBytes: UInt64
    public let wiredBytes: UInt64
    /// compressor_page_count × pageSize（见类型注释）。
    public let compressedBytes: UInt64
    /// sysctl VM_SWAPUSAGE 的 xsw_usage.xsu_used。
    public let swapUsedBytes: UInt64
    /// xsw_usage.xsu_total。
    public let swapTotalBytes: UInt64
    /// sysctl 读不到 swap（异常环境）时为 false，UI 该行显示 "—"。
    public let swapAvailable: Bool

    public init(
        totalBytes: UInt64,
        activeBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64,
        swapAvailable: Bool
    ) {
        self.totalBytes = totalBytes
        self.activeBytes = activeBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapAvailable = swapAvailable
    }

    /// 与 MMCore.SystemSampler 相同：不含 inactive（可随时被回收，算进占用是虚报）。
    public var usedBytes: UInt64 { activeBytes &+ wiredBytes &+ compressedBytes }

    public var usedRatio: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1.0, Double(usedBytes) / Double(totalBytes))
    }
}

// MARK: - 网络（沿用原有 AF_LINK 累计字节，差分口径与磁盘一致）

public struct NetworkBytes: Equatable, Sendable {
    public let received: UInt64
    public let sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }
}

public struct NetworkRate: Equatable, Sendable {
    public let downBytesPerSecond: Double?
    public let upBytesPerSecond: Double?
}

public enum NetworkDiff {
    public static func rate(previous: NetworkBytes?, current: NetworkBytes, interval: TimeInterval) -> NetworkRate? {
        guard let previous, interval > 0, interval.isFinite else { return nil }
        let down: Double? = current.received >= previous.received
            ? Double(current.received - previous.received) / interval : nil
        let up: Double? = current.sent >= previous.sent
            ? Double(current.sent - previous.sent) / interval : nil
        return NetworkRate(downBytesPerSecond: down, upBytesPerSecond: up)
    }
}

// MARK: - 一帧快照（主线程只赋值它，不做采样）

public struct MetricSnapshot: Equatable, Sendable {
    /// 总 CPU 占用（0...1）。nil = "—"（首帧/回绕/零增量）。
    public var totalCPU: Double?
    /// 每核占用，元素 nil = 该核 "—"。
    public var perCoreCPU: [Double?]
    public var diskIOStatus: DiskIOStatus
    public var diskReadBytesPerSecond: Double?
    public var diskWriteBytesPerSecond: Double?
    public var memory: MemoryMetrics?
    public var networkDownBytesPerSecond: Double?
    public var networkUpBytesPerSecond: Double?
    /// 温度/风扇（SMC 瞬时量，和 memory 一样首帧就有，不做差分）。
    public var sensors: SensorsSnapshot
    public var sampledAt: Date

    /// `.distantPast` 是 `empty` 用的哨兵，不是一个真实时刻。凡是准备把"没有值"
    /// 说成一个具体原因（host_statistics64 失败、IOKit 错误码……）的地方都得先看这个。
    public var hasSampled: Bool { sampledAt != .distantPast }

    public static let empty = MetricSnapshot(
        totalCPU: nil,
        perCoreCPU: [],
        diskIOStatus: .unavailable(reason: "尚未完成首次采样"),
        diskReadBytesPerSecond: nil,
        diskWriteBytesPerSecond: nil,
        memory: nil,
        networkDownBytesPerSecond: nil,
        networkUpBytesPerSecond: nil,
        sensors: .notSampled,
        sampledAt: .distantPast
    )

    public init(
        totalCPU: Double?,
        perCoreCPU: [Double?],
        diskIOStatus: DiskIOStatus,
        diskReadBytesPerSecond: Double?,
        diskWriteBytesPerSecond: Double?,
        memory: MemoryMetrics?,
        networkDownBytesPerSecond: Double?,
        networkUpBytesPerSecond: Double?,
        sensors: SensorsSnapshot,
        sampledAt: Date
    ) {
        self.totalCPU = totalCPU
        self.perCoreCPU = perCoreCPU
        self.diskIOStatus = diskIOStatus
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.memory = memory
        self.networkDownBytesPerSecond = networkDownBytesPerSecond
        self.networkUpBytesPerSecond = networkUpBytesPerSecond
        self.sensors = sensors
        self.sampledAt = sampledAt
    }
}
