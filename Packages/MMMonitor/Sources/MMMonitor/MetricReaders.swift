//
//  MetricReaders.swift — 系统调用层（有副作用，不在此层做差分）
//
//  读数字段口径借鉴 stats（MIT, Copyright (c) 2019 Serhiy Mytrovtsiy，
//  见 MetricTypes.swift 头注），实现独立。
//

import Foundation
import IOKit
import MMCore

// MARK: - CPU

public enum HostCPUReader {

    /// 每核四状态 tick。host_processor_info 返回的数组必须由调用方 vm_deallocate，
    /// 这里在作用域结束时统一释放（defer），不漏放。
    public static func perCoreTicks() -> [CoreTicks]? {
        var cpuCount = natural_t(0)
        var info: processor_info_array_t?
        var infoCount = mach_msg_type_number_t(0)
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let raw = info else {
            if kr != KERN_SUCCESS, let message = machErrorString(kr) {
                NSLog("MMMonitor host_processor_info failed: \(message)")
            }
            return nil
        }
        defer {
            let byteSize = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: raw), byteSize)
        }
        // integer_t 平铺数组按 processor_cpu_load_info_data_t 步进重排；
        // 核数用 infoCount / CPU_STATE_MAX，而不是猜 ProcessInfo.processorCount。
        return loadInfo(raw, infoCount: Int(infoCount)).map { ticks(from: $0) }
    }

    /// 总体 host_cpu_load_info（与旧实现同口径，不依赖每核求和）。
    public static func totalTicks() -> CoreTicks? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &load) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let ticks = load.cpu_ticks
        return CoreTicks(user: ticks.0, system: ticks.1, idle: ticks.2, nice: ticks.3)
    }

    private static func loadInfo(_ raw: processor_info_array_t, infoCount: Int) -> [processor_cpu_load_info_data_t] {
        // processor_info_t 与 processor_cpu_load_info_t 是同一块 integer_t 数组的不同视图。
        let states = Int(CPU_STATE_MAX)
        let coreCount = infoCount / max(1, states)
        let pointer = UnsafeRawPointer(raw).assumingMemoryBound(to: processor_cpu_load_info_data_t.self)
        return (0..<coreCount).map { pointer[$0] }
    }

    private static func ticks(from info: processor_cpu_load_info_data_t) -> CoreTicks {
        // cpu_ticks 在 Swift 导入里就是 natural_t(UInt32) 元组，无需 bitPattern 转换。
        CoreTicks(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }
}

func machErrorString(_ kr: kern_return_t) -> String? {
    guard let c = mach_error_string(kr) else { return nil }
    return String(cString: c)
}

// MARK: - 磁盘 IO（IOKit IOBlockStorageDriver）

public enum DiskIOReader {

    /// 汇总所有 IOBlockStorageDriver 的 Statistics["Bytes (Read)"/"Bytes (Write)"]。
    /// 失败（无匹配服务 / 拿不到属性）返回带原文原因 Result.failure，
    /// UI 整行显示 "—" 并把原因写进副标题 —— 不再静默给 0。
    public static func read() -> Result<DiskIOCounters, DiskIOFailure> {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else {
            return .failure(DiskIOFailure("IOServiceMatching(\"IOBlockStorageDriver\") 返回空，无法枚举磁盘统计"))
        }
        var iterator = io_object_t(0)
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else {
            let detail = machErrorString(kr) ?? "kern_return_t \(kr)"
            return .failure(DiskIOFailure("枚举 IOBlockStorageDriver 失败：\(detail)"))
        }
        defer { IOObjectRelease(iterator) }

        var readBytes: UInt64 = 0
        var writeBytes: UInt64 = 0
        var driversFound = 0
        var statisticsMissing = false

        // 已知坑：目录/注册表枚举用 while + next 逐个取，不要用批量 for-in。
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            if let counters = statistics(of: service) {
                readBytes &+= counters.readBytes
                writeBytes &+= counters.writeBytes
                driversFound += 1
            } else {
                statisticsMissing = true
            }
            service = IOIteratorNext(iterator)
        }

        guard driversFound > 0 else {
            return .failure(DiskIOFailure(statisticsMissing
                ? "所有磁盘驱动均未暴露 Statistics 字典（可能被沙盒/权限限制）"
                : "未发现任何 IOBlockStorageDriver 设备"))
        }
        return .success(DiskIOCounters(readBytes: readBytes, writeBytes: writeBytes))
    }

    private static func statistics(of service: io_object_t) -> DiskIOCounters? {
        var propsPointer: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsPointer, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsPointer?.takeRetainedValue() as? [String: Any],
              let statistics = props["Statistics"] as? [String: Any],
              let read = statistics["Bytes (Read)"] as? NSNumber,
              let write = statistics["Bytes (Write)"] as? NSNumber
        else { return nil }
        return DiskIOCounters(readBytes: read.uint64Value, writeBytes: write.uint64Value)
    }
}

// MARK: - 内存

public enum MemoryReader {

    /// vm_statistics64(HOST_VM_INFO64) + sysctl VM_SWAPUSAGE。
    /// compressed 用 compressor_page_count（物理占用口径，见 MemoryMetrics 注释）。
    public static func read() -> MemoryMetrics? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        // 页大小与内核页大小在 arm64 上通常都是 16 KB；用 vm_kernel_page_size 与
        // MMCore.SystemSampler 保持同一换算。
        let pageSize = UInt64(vm_kernel_page_size)
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        let swapOK = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0

        return MemoryMetrics(
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            activeBytes: UInt64(stats.active_count) &* pageSize,
            wiredBytes: UInt64(stats.wire_count) &* pageSize,
            compressedBytes: UInt64(stats.compressor_page_count) &* pageSize,
            swapUsedBytes: swapOK ? swap.xsu_used : 0,
            swapTotalBytes: swapOK ? swap.xsu_total : 0,
            swapAvailable: swapOK
        )
    }
}

// MARK: - 电池（IOKit AppleSmartBattery，只读）

public enum BatteryReader {

    /// 一次 `IORegistryEntryCreateCFProperties` 拿整张属性字典，换算与判状态全在
    /// `BatterySnapshot.assemble(from:)`（纯函数，单测喂字典即可覆盖正分支）。
    ///
    /// 三条失败路径各有各的话，不塌成一句"读不到"：那会把"这台机器没有电池"
    /// 说成一次故障，而它是个事实（本机 Mac mini 实测：节点在、`BatteryInstalled=No`）。
    ///
    /// 刻意不枚举多个匹配服务、也不用 `IOPSCopyPowerSourcesInfo`：stats 两条路都走
    /// （`docs/github-references/stats/Modules/Battery/readers.swift:16` 与 :61-71），
    /// 但那个 API 会把"没有电池"报成一张空的电源列表，读不出来的东西在我们这儿必须是 nil。
    /// 单来源的代价是健康度只认 mAh 那一对，Intel 机型走不到——这条写在 roadmap 的 P37a 一节里。
    public static func read() -> BatterySnapshot {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            return .unavailable(reason: "IOServiceMatching(\"AppleSmartBattery\") 返回空，无法枚举电池节点")
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return .unavailable(reason: "IORegistry 里没有 AppleSmartBattery 节点，问不出这台机器有没有电池")
        }
        defer { IOObjectRelease(service) }

        var propsPointer: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &propsPointer, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let props = propsPointer?.takeRetainedValue() as? [String: Any] else {
            let detail = machErrorString(kr) ?? "kern_return_t \(kr)"
            return .unavailable(reason: "读取 AppleSmartBattery 属性失败：\(detail)")
        }
        return BatterySnapshot.assemble(from: BatteryRawValues(from: props))
    }
}

// MARK: - 网络

public enum NetworkReader {
    /// 复用 MMCore 全站唯一口径（只计物理 AF_LINK，排除回环与别名）。
    public static func read() -> NetworkBytes? {
        guard let bytes = SystemSampler.networkBytes() else { return nil }
        return NetworkBytes(received: bytes.received, sent: bytes.sent)
    }
}
