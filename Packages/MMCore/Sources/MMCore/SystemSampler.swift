import Foundation

// MARK: - 系统读数
//
// 全站唯一的"量一下机器现在什么样"的入口。放在 MMCore 是因为多个模块都要用：
// 仪表盘、优化页、菜单栏。之前每个页面各抄一份 host_statistics 的写法，
// 抄出来的口径还不一样（有的把 inactive 算进占用，有的不算），同一台机器显示两个数。
//
// 约定：
// - 只报"量得出的"，量不到就返回 nil / 0，由 UI 显示占位而不是猜一个数；
// - 内存占用 = active + wired + compressed，不含 inactive（inactive 可随时被回收，
//   把它算成"占用"是这类工具最常见的虚报）；
// - 磁盘可用用 volumeAvailableCapacityForImportantUsage，它含 purgeable 空间，
//   和访达显示的一致；用 statvfs 的 f_bavail 会比访达少好几 GB。

public enum SystemSampler {

    // MARK: 内存

    public struct Memory {
        public let total: UInt64
        public let used: UInt64
        public let swapUsed: UInt64
        public let swapTotal: UInt64

        public var pressure: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    public static func memory() -> Memory {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let ok = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        } == KERN_SUCCESS
        guard ok else {
            return Memory(total: total, used: 0, swapUsed: 0, swapTotal: 0)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let used = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let swapOK = sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0
        return Memory(
            total: total,
            used: used,
            swapUsed: swapOK ? swap.xsu_used : 0,
            swapTotal: swapOK ? swap.xsu_total : 0
        )
    }

    // MARK: CPU

    /// 四个状态的累计 tick 数。CPU 使用率是两次采样之间的差值，单次读数没有意义，
    /// 所以这里只给原始 tick，由调用方保存上一帧。
    public struct CPUTicks: Equatable {
        public let user: UInt32
        public let system: UInt32
        public let idle: UInt32
        public let nice: UInt32

        public var total: UInt64 { UInt64(user) + UInt64(system) + UInt64(idle) + UInt64(nice) }
    }

    public static func cpuTicks() -> CPUTicks? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &load) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return CPUTicks(user: load.cpu_ticks.0, system: load.cpu_ticks.1,
                        idle: load.cpu_ticks.2, nice: load.cpu_ticks.3)
    }

    /// 上一次与这一次的差值；跨度为 0 时返回 nil，让 UI 继续显示上一次的数而不是 0%。
    public static func load(from previous: CPUTicks?, to current: CPUTicks) -> Double? {
        guard let previous else { return nil }
        let deltaTotal = Int64(current.total) - Int64(previous.total)
        guard deltaTotal > 0 else { return nil }
        let deltaIdle = Int64(current.idle) - Int64(previous.idle)
        return max(0, min(1, 1 - Double(deltaIdle) / Double(deltaTotal)))
    }

    // MARK: 网络

    public struct NetBytes: Equatable {
        public let received: UInt64
        public let sent: UInt64
    }

    /// 只统计物理网卡（AF_LINK），排除回环与虚拟接口别名，否则和系统监视器对不上。
    public static func networkBytes() -> NetBytes? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return nil }
        defer { freeifaddrs(first) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var pointer = first
        while let entry = pointer {
            pointer = entry.pointee.ifa_next
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            if name.hasPrefix("lo") || name.contains(".") { continue }
            guard let raw = entry.pointee.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self)
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        return NetBytes(received: received, sent: sent)
    }

    public static func rate(from previous: NetBytes?, to current: NetBytes, interval: TimeInterval) -> NetBytes? {
        guard let previous, interval > 0 else { return nil }
        let rx = current.received >= previous.received ? current.received - previous.received : 0
        let tx = current.sent >= previous.sent ? current.sent - previous.sent : 0
        return NetBytes(received: rx / UInt64(interval), sent: tx / UInt64(interval))
    }

    // MARK: 卷

    public struct Volume {
        public let name: String
        public let path: String
        public let total: UInt64
        /// 访达口径的可用空间（含 purgeable）。
        public let available: UInt64
        public let usedRatio: Double
        /// 用 available 反推的"已用"，与访达显示的数字一致。
        public var used: UInt64 { total > available ? total - available : 0 }
    }

    public static func volume(atPath path: String = "/") -> Volume? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]), let capacity = values.volumeTotalCapacity, capacity > 0 else { return nil }

        let total = UInt64(capacity)
        let available = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
        return Volume(
            name: values.volumeName ?? "Macintosh HD",
            path: path,
            total: total,
            available: available,
            usedRatio: Double(total - available) / Double(total)
        )
    }

    // MARK: 目录体积

    /// 用 allocated（实际占块）而不是 apparent（标称大小）：APFS 压缩与稀疏文件的
    /// 标称大小会把用户带偏。目录本身不重复计。
    ///
    /// 不跳过隐藏项。`options: [.skipsHiddenFiles]` 看着只是省掉 `.DS_Store`，
    /// 实际会把整个以点开头的目录一起剪掉——cargo 的 registry 体积几乎全在
    /// `index.crates.io-*/.cache/` 底下，本机因此被报成 12 KB（实测 75 MB）。
    /// 一个"能回收多少"的读数错四倍数量级，比慢一点严重得多。
    public static func directoryBytes(_ path: String) -> UInt64? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return nil }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey,
            ]) else { continue }
            if values.isDirectory == true { continue }
            total += UInt64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    public static func trashBytes() -> UInt64? {
        directoryBytes(NSHomeDirectory() + "/.Trash") ?? 0
    }
}
