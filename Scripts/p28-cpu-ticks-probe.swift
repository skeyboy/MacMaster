import Foundation

// P28 否证探针的被测部分：只读 `host_cpu_load_info`，两次采样之间打总 tick 增量。
// 用法（由 ./Scripts/p28-cpu-ticks-probe.sh 代跑）：FRAMES=200 INTERVAL_MS=250 xcrun swift 本文件
//
// 为什么单独一支：`SystemSampler.load(from:to:)` 在 `deltaTotal <= 0` 时返回 nil（设计如此，
// 让 UI 沿用上一次的数而不是画 0%），而"0.25 s 的跨度里 tick 一定在走"这句**从来没有被量过**。
// 一条真机判据把没量过的前提当合同，就会随机红——判据红了查不到事，比没有判据更坏。
//
// 写法上有一条踩过：`read()` **返回四元组而不是返回 `host_cpu_load_info` 结构体**。
// 返回结构体那一版 20 帧里 19 帧增量为 0（合计停在同一个数上），换回元组就每帧都在走；
// 也就是说那一版量到的是这份脚本自己的读数问题，不是操作系统的。既然这一支的全部用途就是
// 给"操作系统这边到底会不会给零跨度"一个数，读数这一层不能有第二种解释，所以形态钉死在这里。
let frames = Int(ProcessInfo.processInfo.environment["FRAMES"] ?? "") ?? 12
let intervalMs = Int(ProcessInfo.processInfo.environment["INTERVAL_MS"] ?? "") ?? 250

typealias Ticks = (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)

func read() -> Ticks? {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }
    return (info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3)
}

func total(_ t: Ticks) -> UInt64 {
    UInt64(t.user) + UInt64(t.system) + UInt64(t.idle) + UInt64(t.nice)
}

print("每行 = 一次 \(intervalMs) ms 间隔：du/ds/di/dn 与 total_delta（tick 单位 1/100 s，跨全部 CPU 累计）")
var previous: Ticks?
var zeroOrNegative = 0
var readFailures = 0
var minDelta = Int64.max
for frame in 1...frames {
    guard let current = read() else {
        readFailures += 1
        print("帧 \(frame)：host_statistics 返回失败")
        continue
    }
    if let p = previous {
        let d = Int64(total(current)) - Int64(total(p))
        if d < minDelta { minDelta = d }
        if d <= 0 { zeroOrNegative += 1 }
        print("帧 \(frame)：du=\(Int64(current.user)-Int64(p.user)) ds=\(Int64(current.system)-Int64(p.system)) "
            + "di=\(Int64(current.idle)-Int64(p.idle)) dn=\(Int64(current.nice)-Int64(p.nice)) "
            + "total_delta=\(d)\(d <= 0 ? "  ← 这一帧 load(from:to:) 会返回 nil" : "")")
    } else {
        print("帧 \(frame)：首帧，合计=\(total(current))")
    }
    previous = current
    usleep(UInt32(intervalMs) * 1000)
}
print("结论：\(frames) 帧里 total_delta ≤ 0 的有 \(zeroOrNegative) 帧，读数失败 \(readFailures) 帧，最小增量=\(minDelta)")
