import Foundation
import MMCore
import MMFileScanner
import MMUI

// MARK: - 概览/优化页共用的真实读数
//
// 为什么放在 MMOptimizer 而不是直接用 MMCore.SystemSampler：
// MMCore 的 memory() 在 host_statistics64 失败时返回 used=0、swap=0，
// 把"没量到"说成"占用为零"，违反"拿不到就显示 —"的口径要求；
// 且它不单独暴露 compressed。MMCore 不在本次可改动范围内，
// 所以这里自己采一次 vm_statistics64，量不到就是 nil，绝不落回 0。
// CPU tick 差分、卷容量与网络继续复用 MMCore.SystemSampler（口径已正确：
// host_statistics 两次采样差分、volumeTotalCapacityKey +
// volumeAvailableCapacityForImportantUsageKey），两处显示不会打架。

// MARK: 内存采样（含 compressed 与失败语义）

public enum DashboardMemory {
    /// 每个字段独立可失败：total 来自 ProcessInfo（总是有），
    /// used/active/wired/compressed 来自 host_statistics64，swap 来自 sysctl(vm.swapusage)。
    /// nil = 该数据源这次没量到，UI 必须走 "—" 分支。
    public struct Reading: Equatable {
        public let total: UInt64
        public let used: UInt64?
        /// active/wired 只为"内存构成"这一段服务：它们与 used 来自**同一次**
        /// host_statistics64 调用，所以条子各段之和必然与 used 对得上。
        /// 分两次采样会量出两个真相，那种"构成"是假的。
        public let active: UInt64?
        public let wired: UInt64?
        public let compressed: UInt64?
        public let swapUsed: UInt64?
        public let swapTotal: UInt64?

        public init(total: UInt64, used: UInt64?, active: UInt64? = nil, wired: UInt64? = nil,
                    compressed: UInt64?, swapUsed: UInt64?, swapTotal: UInt64?) {
            self.total = total
            self.used = used
            self.active = active
            self.wired = wired
            self.compressed = compressed
            self.swapUsed = swapUsed
            self.swapTotal = swapTotal
        }

        /// 已用量拿不到时压力也是 nil——没有"0 压力"这种猜出来的乐观值。
        public var pressure: Double? {
            guard let used, total > 0 else { return nil }
            return min(1, Double(used) / Double(total))
        }
    }

    public static func sample() -> Reading {
        let total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return Reading(total: total, used: nil, compressed: nil, swapUsed: nil, swapTotal: nil)
        }

        // 口径：已用 = (active + wired + compressed) × pageSize，不含 inactive
        // （inactive 可随时被回收，算进占用是虚报，与 MMCore 保持同一口径）。
        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let swapOK = sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0
        return Reading(
            total: total,
            used: used,
            active: active,
            wired: wired,
            compressed: compressed,
            swapUsed: swapOK ? swap.xsu_used : nil,
            swapTotal: swapOK ? swap.xsu_total : nil
        )
    }
}

// MARK: 可清理估算（只认真实扫描结果）

/// 扫描状态机。注意没有"默认 2.3 GB"这种初始值：没扫过就是没扫过。
public enum ReclaimMeasureState: Equatable {
    case notMeasured
    case measuring
    case failed(reason: String)
    case measured(totalBytes: UInt64, categoryCount: Int)

    /// 只有真实扫描结果才允许按"数字"样式展示；其余状态走灰置文案。
    public var isMeasuredValue: Bool {
        if case .measured = self { return true }
        return false
    }
}

public enum DashboardReclaim {
    /// 概览页把这个数字标成"可清理"，所以它只能累加真的删得掉的部分。
    /// `.readOnly` 的类别（root 属主、不可写）用户点了也不会变小，算进去就是虚报。
    /// 求和与分类严格一致：CacheScanner 已按"子树认领"去重，父目录不会把子类别算两遍。
    public static func totalBytes(of categories: [CacheCategory]) -> UInt64 {
        deletableCategories(categories).reduce(UInt64(0)) { $0 + $1.scannedSize }
    }

    /// 与 `totalBytes` 同一个集合：数量说了"N 类"就必须正好是加起来等于总量的那 N 类。
    public static func deletableCategories(_ categories: [CacheCategory]) -> [CacheCategory] {
        categories.filter { $0.risk.allowsDeletion }
    }

    public static func state(from categories: [CacheCategory]?) -> ReclaimMeasureState {
        guard let categories, !categories.isEmpty else {
            return .failed(reason: "扫描没有返回结果")
        }
        let deletable = deletableCategories(categories)
        guard deletable.isEmpty == false else {
            // 全都不归当前用户所有：这不是"可清理 0 B"，而是没有可操作项。
            return .notMeasured
        }
        return .measured(totalBytes: deletable.reduce(0) { $0 + $1.scannedSize },
                         categoryCount: deletable.count)
    }
}

// MARK: 存储构成（概览页堆叠条）

/// 设计稿把整卷画成一条分段条。这里只画**量得到**的分段：
/// 可清理与废纸篓来自真实扫描，"其他已用"是减法剩下的那部分。
/// 三段之和 + 可用 == 整卷，所以条子必然铺满，不会出现"剩一截没颜色"。
public enum StorageBreakdown {
    public struct Segment: Equatable, Identifiable {
        public let id: String
        public let label: String
        public let bytes: UInt64
    }

    /// - Parameters:
    ///   - reclaimable: 真实扫描出的可清理字节；nil = 还没扫，不画这一段。
    ///   - trash: 废纸篓实测字节；nil = 量不到，不画这一段。
    /// 两者都按"不超过已用量"截断：扫描结果可能比这次读卷早几个小时，
    /// 期间用户已经清掉了一部分，不截断就会出现可用容量算成负数。
    public static func segments(total: UInt64, available: UInt64,
                                reclaimable: UInt64?, trash: UInt64?) -> [Segment] {
        guard total > 0 else { return [] }
        let availableCapped = min(available, total)
        let used = total - availableCapped
        let reclaim = min(reclaimable ?? 0, used)
        let trashPart = min(trash ?? 0, used - reclaim)
        var out: [Segment] = []
        if reclaim > 0 { out.append(Segment(id: "reclaimable", label: "可清理", bytes: reclaim)) }
        if trashPart > 0 { out.append(Segment(id: "trash", label: "废纸篓", bytes: trashPart)) }
        out.append(Segment(id: "used", label: "其他已用", bytes: used - reclaim - trashPart))
        out.append(Segment(id: "available", label: "可用", bytes: availableCapped))
        return out.filter { $0.bytes > 0 }
    }

    /// 告警只在可用低于 10% 时出现。设计稿里那颗红色 badge 是"可用空间偏低"，
    /// 不是"用过 90% 就叫危险"的通用装饰——阈值写死在这里，页面不各说各话。
    public static func isLowSpace(total: UInt64, available: UInt64) -> Bool {
        guard total > 0 else { return false }
        return Double(available) / Double(total) < 0.10
    }
}

// MARK: 内存构成（概览页第二条堆叠条）

public enum MemoryComposition {
    public struct Part: Equatable, Identifiable {
        public let id: String
        public let label: String
        public let bytes: UInt64
    }

    /// 前台(active) / 联动(wired) / 压缩(compressed) / 未占用（减法）。
    /// 任何一项没量到就整条不返回——把缺的那部分并进"未占用"会画出一条
    /// 骗人的绿条："未占用 60%"其实只是没读到 wired。
    public static func parts(_ reading: DashboardMemory.Reading?) -> [Part]? {
        guard let reading, reading.total > 0,
              let active = reading.active, let wired = reading.wired,
              let compressed = reading.compressed else { return nil }
        let used = active + wired + compressed
        guard used <= reading.total else { return nil }
        var parts = [
            Part(id: "active", label: "前台", bytes: active),
            Part(id: "wired", label: "联动", bytes: wired),
            Part(id: "compressed", label: "压缩", bytes: compressed),
        ]
        let free = reading.total - used
        if free > 0 { parts.append(Part(id: "free", label: "未占用", bytes: free)) }
        return parts
    }
}

// MARK: 负载结论

public enum LoadVerdict {
    /// 一句话结论。阈值：CPU 70%、内存压力 80%，任一越线即"负载偏高"。
    /// 两者都没量到时不给结论——"运行平稳"是一句承诺，不能靠猜。
    public static func text(cpu: Double?, memoryPressure: Double?) -> String? {
        guard let cpu, let memoryPressure else { return nil }
        return (cpu >= 0.70 || memoryPressure >= 0.80) ? "负载偏高" : "运行平稳"
    }
}

// MARK: 口径文案（纯函数，"—" 分支全部可单测）

public enum DashboardText {
    public static let placeholder = "—"

    public static func percent(_ ratio: Double?) -> String {
        guard let ratio else { return placeholder }
        return MMFormat.percent(ratio)
    }

    /// "已用 / 总量"；任何一侧没量到都是 "—"，不是 "0 字节 / 16 GB"。
    public static func memoryUsedText(_ reading: DashboardMemory.Reading?) -> String {
        guard let reading, let used = reading.used, reading.total > 0 else { return placeholder }
        return "\(MMFormat.bytes(used)) / \(MMFormat.bytes(reading.total))"
    }

    public static func memoryPressureText(_ reading: DashboardMemory.Reading?) -> String {
        percent(reading?.pressure)
    }

    public static func compressedText(_ reading: DashboardMemory.Reading?) -> String {
        guard let reading, let compressed = reading.compressed else { return placeholder }
        return MMFormat.bytes(compressed)
    }

    /// swap 单独一行：没量到显示 "—"；量到且为 0 才可以说"未使用"。
    public static func swapText(_ reading: DashboardMemory.Reading?) -> String {
        guard let reading, let used = reading.swapUsed, let total = reading.swapTotal else {
            return "交换空间 \(placeholder)"
        }
        if used == 0 { return "交换空间 0 字节" }
        return "交换 \(MMFormat.bytes(used)) / \(MMFormat.bytes(total))"
    }

    /// CPU 口径声明：总占用（跨所有核），不是每核。
    public static func cpuCaliberNote(coreCount: Int) -> String {
        "总占用 · \(coreCount) 核"
    }

    /// P/E 核拆分来自 sysctl，读不到就说口径而不是编一个"6 性能 + 4 能效"。
    public static func cpuCoreNote(total: Int, performance: Int?, efficiency: Int?) -> String {
        if let performance, let efficiency, performance > 0, efficiency > 0,
           performance + efficiency == total {
            return "\(performance) 性能 + \(efficiency) 能效"
        }
        return "跨所有核总占用"
    }

    public static func reclaimableText(_ state: ReclaimMeasureState) -> String {
        switch state {
        case .notMeasured: "未扫描 · 去清理"
        case .measuring: "扫描中…"
        case .failed(let reason): "测量失败（\(reason)）"
        case .measured(let total, _): MMFormat.bytes(total)
        }
    }

    /// 悬浮/副标题说明：这个数字从哪来、为什么现在没有。
    public static func reclaimDetailText(_ state: ReclaimMeasureState) -> String {
        switch state {
        case .notMeasured: "数字来自真实扫描，扫描前不预估。"
        case .measuring: "正在统计各类缓存、日志与临时文件…"
        case .failed(let reason): reason
        case .measured(_, let count): "来自 \(count) 个分类的真实扫描求和"
        }
    }
}
