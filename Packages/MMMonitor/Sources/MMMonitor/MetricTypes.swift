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

// MARK: - 电池

/// AppleSmartBattery 属性字典里电池那一族的原始值（未换算、未判状态）。
///
/// 每一项都是 Optional，而且**"键缺席"与"读到 0"是两回事**：本机（Mac mini M4，
/// 2026-10-13 实跑 `swift Scripts/p37-battery-probe.swift`）这些键**都在**、值全是 0，
/// 同时 `BatteryInstalled=No`。所以"这台机器有没有电池"只能认 `installed`——
/// 拿容量去判会把一台台式机报成"电量 0%"。
public struct BatteryRawValues: Equatable, Sendable {
    /// `BatteryInstalled`。nil = 连"有没有电池"都问不出来。
    public var installed: Bool?
    /// `CurrentCapacity`：Apple Silicon 上是百分数，分母 `MaxCapacity` 恒为 100。
    public var currentCapacity: Int?
    public var maxCapacity: Int?
    /// `AppleRawCurrentCapacity`：真实剩余容量（mAh）。本机没这个键。
    public var appleRawCurrentCapacity: Int?
    /// `AppleRawMaxCapacity`：当前满充容量（mAh），健康度的分子。本机没这个键。
    public var appleRawMaxCapacity: Int?
    /// `DesignCapacity`：设计容量（mAh），健康度的分母。本机没这个键。
    public var designCapacity: Int?
    public var cycleCount: Int?
    /// `TimeRemaining`（分钟）。系统不给估计时是 0 或 -1，换算层一律当"没有估计"。
    public var timeRemainingMinutes: Int?
    /// `ExternalConnected`：是否接了外接电源。
    public var externalConnected: Bool?
    public var isCharging: Bool?

    /// 单测/夹具用的显式构造：缺省一律 nil（"没读到"），不写 0。
    public init(
        installed: Bool? = nil,
        currentCapacity: Int? = nil,
        maxCapacity: Int? = nil,
        appleRawCurrentCapacity: Int? = nil,
        appleRawMaxCapacity: Int? = nil,
        designCapacity: Int? = nil,
        cycleCount: Int? = nil,
        timeRemainingMinutes: Int? = nil,
        externalConnected: Bool? = nil,
        isCharging: Bool? = nil
    ) {
        self.installed = installed
        self.currentCapacity = currentCapacity
        self.maxCapacity = maxCapacity
        self.appleRawCurrentCapacity = appleRawCurrentCapacity
        self.appleRawMaxCapacity = appleRawMaxCapacity
        self.designCapacity = designCapacity
        self.cycleCount = cycleCount
        self.timeRemainingMinutes = timeRemainingMinutes
        self.externalConnected = externalConnected
        self.isCharging = isCharging
    }

    /// 从 IORegistry 属性字典解码。键缺席、类型不是数字/布尔 → 留 nil，
    /// 这一层不补默认值，也不在这里判状态。
    public init(from properties: [String: Any]) {
        func boolean(_ key: String) -> Bool? { properties[key] as? Bool }
        func integer(_ key: String) -> Int? { properties[key] as? Int }
        self.init(
            installed: boolean("BatteryInstalled"),
            currentCapacity: integer("CurrentCapacity"),
            maxCapacity: integer("MaxCapacity"),
            appleRawCurrentCapacity: integer("AppleRawCurrentCapacity"),
            appleRawMaxCapacity: integer("AppleRawMaxCapacity"),
            designCapacity: integer("DesignCapacity"),
            cycleCount: integer("CycleCount"),
            timeRemainingMinutes: integer("TimeRemaining"),
            externalConnected: boolean("ExternalConnected"),
            isCharging: boolean("IsCharging")
        )
    }
}

public enum BatteryStatus: Equatable, Sendable {
    case loaded
    /// 这台机器没有电池（`BatteryInstalled=No`；本机实测就是这一档）。
    /// 这不是故障：UI 说"本机没有电池"，不说"读不到"。
    case noBattery
    /// 问不出答案（IOKit 调用失败、属性字典拿不到、`BatteryInstalled` 键缺席）。
    /// reason 是原文，和磁盘 IO / SMC 同一套话术。
    case unavailable(reason: String)
}

/// 电池卡的一帧（只读：这里没有任何"能不能唤醒休眠""估算还剩几小时"的承诺）。
public struct BatterySnapshot: Equatable, Sendable {
    public var status: BatteryStatus
    /// 电量 0...1。nil = "—"，不是 0%。
    public var level: Double?
    /// 健康度 0...1 = 满充容量 ÷ 设计容量。nil = 没有可比的设计容量（本机实测就没有）。
    public var health: Double?
    /// 循环次数。0 = 读到 0 次（新电池），nil = 没读到。
    public var cycleCount: Int?
    public var isCharging: Bool?
    public var isExternalConnected: Bool?
    /// 系统给出的剩余时间估计（分钟），nil = 没给。
    public var timeRemainingMinutes: Int?

    /// 剩余时间可信区间（分钟）。0 与 -1 是"没有估计"，一天以上是这个键在胡说。
    public static let plausibleTimeRemainingRange: ClosedRange<Int> = 1...1_440
    /// 循环次数可信上限。真实锂电记录在数千量级，读到几万是键在胡说（同风扇 RPM 上限的道理）。
    public static let plausibleCycleRange: ClosedRange<Int> = 0...9_999
    /// 健康度可信下限。低于它不是"电池快不行了"，是分子分母单位对不上。
    public static let plausibleHealthFloor = 0.3

    public init(
        status: BatteryStatus,
        level: Double?,
        health: Double?,
        cycleCount: Int?,
        isCharging: Bool?,
        isExternalConnected: Bool?,
        timeRemainingMinutes: Int?
    ) {
        self.status = status
        self.level = level
        self.health = health
        self.cycleCount = cycleCount
        self.isCharging = isCharging
        self.isExternalConnected = isExternalConnected
        self.timeRemainingMinutes = timeRemainingMinutes
    }

    /// 与 `MetricSnapshot.empty`、`SensorsSnapshot.notSampled` 同一条约定：
    /// "还没采过"不能被说成"这台机器读不到电池"。
    public static let notSampled = BatterySnapshot(
        status: .unavailable(reason: "尚未完成首次采样"),
        level: nil, health: nil, cycleCount: nil,
        isCharging: nil, isExternalConnected: nil, timeRemainingMinutes: nil
    )

    public static func unavailable(reason: String) -> BatterySnapshot {
        BatterySnapshot(
            status: .unavailable(reason: reason),
            level: nil, health: nil, cycleCount: nil,
            isCharging: nil, isExternalConnected: nil, timeRemainingMinutes: nil
        )
    }

    /// "这台机器没有电池"是一个可以正面成立的结论，所以它有自己的构造，
    /// 不借用 unavailable 那一族（那需要一句故障原因）。
    /// 整卡一句话、字段全 nil，连外接电源那一行也留空——
    /// 免得"没有电池"旁边挂个"已接通电源"，看着像在说电池。
    public static let noBattery = BatterySnapshot(
        status: .noBattery,
        level: nil, health: nil, cycleCount: nil,
        isCharging: nil, isExternalConnected: nil, timeRemainingMinutes: nil
    )

    /// 纯装配：原始属性 → 卡片状态与换算值。UI 不参与判断。
    public static func assemble(from raw: BatteryRawValues) -> BatterySnapshot {
        switch raw.installed {
        case .some(false):
            return .noBattery
        case .none:
            return .unavailable(reason: "AppleSmartBattery 没有暴露 BatteryInstalled 键，问不出这台机器有没有电池")
        case .some(true):
            let level = level(of: raw)
            let health = health(of: raw)
            let cycles = raw.cycleCount.flatMap { plausibleCycleRange.contains($0) ? $0 : nil }
            let minutes = raw.timeRemainingMinutes.flatMap { plausibleTimeRemainingRange.contains($0) ? $0 : nil }
            if level == nil, health == nil, cycles == nil {
                return .unavailable(reason: "BatteryInstalled=Yes，但电量、健康度、循环次数一个都没有可信读数")
            }
            return BatterySnapshot(
                status: .loaded,
                level: level, health: health, cycleCount: cycles,
                isCharging: raw.isCharging, isExternalConnected: raw.externalConnected,
                timeRemainingMinutes: minutes
            )
        }
    }

    /// 电量：先按 mAh 一对（`AppleRawCurrentCapacity ÷ AppleRawMaxCapacity`，
    /// Apple Silicon 上的真剩余），这对缺任一再退到百分数一对（`CurrentCapacity ÷ MaxCapacity`，
    /// 后者在 ARM 上恒为 100，除完还是同一个数）。
    /// 分子 > 分母 → nil 而不是钳到 100%：那说明两对口径被混着用了，钳过去是把错数报成满电。
    /// 分母 ≤ 0 → nil（本机 Mac mini 的 `MaxCapacity` 就是 0，除它是除零）。
    private static func level(of raw: BatteryRawValues) -> Double? {
        ratio(current: raw.appleRawCurrentCapacity, full: raw.appleRawMaxCapacity)
            ?? ratio(current: raw.currentCapacity, full: raw.maxCapacity)
    }

    private static func ratio(current: Int?, full: Int?) -> Double? {
        guard let current, let full, current >= 0, full > 0, current <= full else { return nil }
        return Double(current) / Double(full)
    }

    /// 健康度 = `AppleRawMaxCapacity ÷ DesignCapacity`（mAh 除 mAh）。
    /// 只认这一对：`MaxCapacity` 在 Apple Silicon 上是百分数（恒 100），拿它除设计容量会算出
    /// 2% 这种"看着在说话"的假健康度，所以宁可 nil。
    /// 上限钳到 100%——新电池满充容量略高于设计值是真事；低于 `plausibleHealthFloor` 一律 nil。
    /// 对照 stats：它把读不到的分母强成 1（`docs/github-references/stats/Modules/Battery/readers.swift:106-116`），
    /// 于是没电池的机器也能显示"健康度 100%"，本仓库的 nil-not-zero 规矩不收这种写法。
    private static func health(of raw: BatteryRawValues) -> Double? {
        guard let design = raw.designCapacity, design > 0,
              let full = raw.appleRawMaxCapacity, full > 0
        else { return nil }
        let value = Double(full) / Double(design)
        guard value >= plausibleHealthFloor else { return nil }
        return min(1.0, value)
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
    /// 电池（IOKit AppleSmartBattery 瞬时量，同样首帧就有、不做差分）。
    public var battery: BatterySnapshot
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
        battery: .notSampled,
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
        battery: BatterySnapshot,
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
        self.battery = battery
        self.sampledAt = sampledAt
    }
}
