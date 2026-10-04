//
//  MonitorFixtureHooks.swift — 把 fidelity-monitor.md §4 那 13 项
//  "只在代码里读到分支、实机一张没截到" 的状态做成可注入档位。
//
//  还原度审计（fidelity-monitor）补的缺口：每核红档、内存 nil、swap 关、
//  磁盘四种 unavailable、进程固定列表、首帧定格、菜单栏关闭态，此前都没有
//  实机可达路径（本模块只有 MM_OPEN_MODULE 一个入口，滚动/骨架/失败分支都构造不出）。
//
//  铁律（照 GuardianFixtureHooks 的口径）：
//  - 钩子只在环境变量存在且取值合法时生效，未设置时生产路径逐字节不变；
//  - 只顶替展示数据：不采样、不写盘、不碰系统状态；
//  - 含非法取值时整个钩子作废并写 stderr——半生效夹具 = 假通过。
//  - 本夹具不读任何 /tmp 路径（纯数值注入），因此不做 /tmp 前缀校验；
//    若以后要加"读夹具文件"档，必须照 MM_ORPHAN_FIXTURE_HOME 的规矩只认 /tmp。
//

import Foundation

// MARK: - 首帧定格（MM_MONITOR_HOLD）

enum MonitorLoadHook {
    struct Result: Equatable, Sendable {
        let holdInitialFrame: Bool
        let rejected: String?
    }

    /// 只认 `hold`：onAppear 不调用 enable()、也不 loadProcesses()，
    /// 页面停在 `.empty` 首帧（测量中 + 骨架 + 内存"尚未采样"），可截图核对折叠线以上态。
    static func parse(_ raw: String?) -> Result {
        guard let raw, !raw.isEmpty else { return Result(holdInitialFrame: false, rejected: nil) }
        if raw.trimmingCharacters(in: .whitespaces).lowercased() == "hold" {
            return Result(holdInitialFrame: true, rejected: nil)
        }
        return Result(holdInitialFrame: false, rejected: raw)
    }
}

// MARK: - 快照注入（MM_MONITOR_FIXTURE）

enum MonitorFixtureTier: String, Sendable {
    case populated       // B 稿底座：全套真实口径数值
    case memoryNil       // D3：memory=nil 但 hasSampled=true
    case swapOff         // Swap 行 "—"（swapAvailable=false）
    case swapZero        // Swap 读到 0/0（I9 那一档；本机不会自然出现，sysctl 给的是 800M/2048M）
    case perCoreRed      // 每核 ≥85% 红档（核 1 = 91.4%）
    case perCoreEmpty    // D1：perCoreCPU 空数组 → 单「—」
    case diskUnavailable // D2：diskIOStatus=.unavailable(reason:)
    case processes       // 注入固定进程列表
    case menubarOff      // 菜单栏监控关闭态：真把状态项摘掉（`disable()`），开关才显示 off——"不 enable" 不够，启动时壳层已经 enable 过了
    case sensors         // 温度与风扇 loaded 夹具档（夹具键名 TZZ*，一眼是假的；E1 用的是真读数，不注夹具）
    case sensorsUnavailable // E2：整卡 unavailable(reason:)，含自定义 reason 后缀
    case sensorsNoFan       // E3：读到风扇数为 0（无风扇机型那一档）
    case sensorsFanUnknown  // E4：FNum 读不出（fanCount=nil，"不知道" ≠ "0 个"）
    case sensorsHot         // E5：最高键 ≥90 °C 转红（实机空闲量不到这一档）
}

struct MonitorSnapshotFixture {
    struct Result: Equatable, Sendable {
        let snapshot: MetricSnapshot?
        let processes: [MonitorProcess]?
        let menubarOff: Bool
        let rejected: [String]
    }

    /// 解析逗号分隔的档位列表。base 用 populated 的确定数值，各档在其上改写；
    /// 非法取值进 rejected，调用方写 stderr 并忽略整个钩子。
    static func parse(_ raw: String?) -> Result {
        guard let raw, !raw.isEmpty else {
            return Result(snapshot: nil, processes: nil, menubarOff: false, rejected: [])
        }
        let tokens = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var accepted: [MonitorFixtureTier] = []
        var rejected: [String] = []
        var diskReason: String?
        var sensorReason: String?

        for token in tokens {
            if token.hasPrefix("disk-unavailable:") {
                let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, !parts[1].isEmpty else { rejected.append(token); continue }
                diskReason = parts[1]
                accepted.append(.diskUnavailable)
            } else if token.hasPrefix("sensors-unavailable:") {
                let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, !parts[1].isEmpty else { rejected.append(token); continue }
                sensorReason = parts[1]
                accepted.append(.sensorsUnavailable)
            } else if token == "diskUnavailable" {
                accepted.append(.diskUnavailable)
            } else if token.hasPrefix("processes") {
                accepted.append(.processes)
            } else if let tier = MonitorFixtureTier(rawValue: token) {
                accepted.append(tier)
            } else {
                rejected.append(token)
            }
        }

        guard !accepted.isEmpty else {
            return Result(snapshot: nil, processes: nil, menubarOff: false, rejected: rejected)
        }

        let base = Self.baseSnapshot()
        var snapshot = base
        var menubarOff = false

        for tier in accepted {
            switch tier {
            case .populated:
                break
            case .memoryNil:
                snapshot.memory = nil
            case .swapOff:
                if let m = snapshot.memory {
                    snapshot.memory = MemoryMetrics(
                        totalBytes: m.totalBytes, activeBytes: m.activeBytes,
                        wiredBytes: m.wiredBytes, compressedBytes: m.compressedBytes,
                        swapUsedBytes: 0, swapTotalBytes: 0, swapAvailable: false)
                }
            case .swapZero:
                if let m = snapshot.memory {
                    // 与 .swapOff 唯一的区别是 swapAvailable=true——"读到 0"和"读不到"
                    // 必须是两档，否则这一档拍出来的就是同一句话。
                    snapshot.memory = MemoryMetrics(
                        totalBytes: m.totalBytes, activeBytes: m.activeBytes,
                        wiredBytes: m.wiredBytes, compressedBytes: m.compressedBytes,
                        swapUsedBytes: 0, swapTotalBytes: 0, swapAvailable: true)
                }
            case .perCoreRed:
                snapshot.perCoreCPU = [0.914] + Array(repeating: nil, count: 9)
            case .perCoreEmpty:
                snapshot.perCoreCPU = []
            case .diskUnavailable:
                snapshot.diskIOStatus = .unavailable(reason: diskReason ?? "IOKit 未返回统计（夹具档）")
            case .processes:
                break
            case .menubarOff:
                menubarOff = true
            case .sensors:
                snapshot.sensors = Self.baseSensors()
            case .sensorsUnavailable:
                snapshot.sensors = .unavailable(
                    reason: sensorReason ?? "AppleSMC 用户客户端打不开（夹具档）")
            case .sensorsNoFan:
                snapshot.sensors = Self.baseSensors(fanCount: 0)
            case .sensorsFanUnknown:
                snapshot.sensors = Self.baseSensors(fanCount: nil)
            case .sensorsHot:
                snapshot.sensors = Self.baseSensors(hottest: 94.0)
            }
        }

        let processes = accepted.contains(.processes) ? Self.syntheticProcesses() : nil
        return Result(snapshot: snapshot, processes: processes, menubarOff: menubarOff, rejected: rejected)
    }

    /// B 稿底座：数值照 fidelity-monitor.md §0 实机量到的 A 稿（10 核 = M4），
    /// 让 B 稿（内存卡 + 进程卡在折叠线以下）的"内容"变成确定值，可被截图核对。
    static func baseSnapshot() -> MetricSnapshot {
        MetricSnapshot(
            totalCPU: 0.358,
            perCoreCPU: [0.175, 0.140, 0.077, 0.048, 0.024, 0.024, 0.742, 0.779, 0.780, 0.775],
            diskIOStatus: .ok,
            diskReadBytesPerSecond: 1.9e6,
            diskWriteBytesPerSecond: 293.3e3,
            memory: MemoryMetrics(
                totalBytes: 24 * 1024 * 1024 * 1024,
                activeBytes: 15_600 * 1024 * 1024,
                wiredBytes: 3_800 * 1024 * 1024,
                compressedBytes: 1_400 * 1024 * 1024,
                // 形状取自实机：`sysctl vm.swapusage` 2026-10-04 量到 total=2048M、used≈800M，
                // 这里取整成 800 MiB / 2 GiB（夹具要的是"非零对仗"这个形状，不是某一帧的数）。
                // 这一档原来写的是 0/0——那正好是 I9 那句「0 字节 / 0 字节」，
                // 于是 populated（底座）和 swapZero（专门拍零值那一档）在照片上同一个样，
                // 夹具的两个档合成一个。底座回到真实形状，零值留给 swapZero。
                swapUsedBytes: 838_860_800,
                swapTotalBytes: 2_147_483_648,
                swapAvailable: true
            ),
            networkDownBytesPerSecond: 1.42e6,
            networkUpBytesPerSecond: 0.31e6,
            sensors: baseSensors(),
            sampledAt: Date(timeIntervalSince1970: 1_700_000_000) // 固定时刻，hasSampled=true
        )
    }

    /// E 稿底座：10 个温度点 + 1 台风扇。键名一律用 `TZZ*`——真实 SMC 键没有这个前缀，
    /// 截图里一眼就能看出是夹具，不会被当成"本机量到的温度"（照 com.example.* 进程的规矩）。
    /// 数值形状照实机（Scripts/smc-probe.swift 2026-10-04：本机 174 个可读 `flt ` 键、
    /// 最高 54.5 °C、FNum=1、F0Ac=1000/F0Mn=1000/F0Mx=4900），但刻意做成降序 + 跨 8 行溢出。
    static func baseSensors(fanCount: Int? = 1, hottest: Double = 78.0) -> SensorsSnapshot {
        let temps: [SensorTemperature] = [
            SensorTemperature(key: "TZZa", celsius: hottest),
            SensorTemperature(key: "TZZb", celsius: 71.5),
            SensorTemperature(key: "TZZc", celsius: 66.2),
            SensorTemperature(key: "TZZd", celsius: 61.9),
            SensorTemperature(key: "TZZe", celsius: 57.4),
            SensorTemperature(key: "TZZf", celsius: 54.5),
            SensorTemperature(key: "TZZg", celsius: 49.1),
            SensorTemperature(key: "TZZh", celsius: 44.0),
            SensorTemperature(key: "TZZi", celsius: 38.6),
            SensorTemperature(key: "TZZj", celsius: 32.3),
        ]
        let fans: [SensorFan]
        switch fanCount {
        case .some(let count):
            fans = (0..<count).map {
                SensorFan(index: $0, currentRPM: $0 == 0 ? 2_100 : 1_850, minRPM: 1_000, maxRPM: 4_900)
            }
        case nil:
            fans = []   // FNum 读不出 → 连有几台风扇都不知道，不去编 F0Ac
        }
        return .loaded(temperatures: temps, fanCount: fanCount, fans: fans)
    }

    /// 合成进程：com.example.* 命名一眼可与真实数据区分；pid 用小整数占位。
    static func syntheticProcesses(count: Int = 10) -> [MonitorProcess] {
        let names = [
            "com.example.windowserver", "com.example.kernel-task", "com.example.safari",
            "com.example.xcode", "com.example.spotlight", "com.example.photos",
            "com.example.mail", "com.example.messages", "com.example.music", "com.example.terminal",
        ]
        return (0..<min(count, names.count)).map { i in
            MonitorProcess(
                name: names[i], pid: Int32(1000 + i),
                cpuSeconds: Double(120 - i * 10),
                memoryBytes: UInt64((500 - i * 40) * 1024 * 1024))
        }
    }
}

// MARK: - 卡片过滤（MM_MONITOR_CARDS）

/// 监控页的六块卡，顺序即代码里的堆叠顺序。
enum MonitorCard: String, Sendable {
    case stats, perCore, disk, memory, process, sensors
}

/// 只保留列出的卡——把折叠线以下的卡顶到首屏来拍，而不是把窗口画高
/// （照 MM_GUARDIAN_CARDS 的做法）。纯显示层过滤：数据流、采样、夹具一概不动，
/// 所以"过滤后"的截图仍然能核对卡片本身的还原度。
enum MonitorCardFilter {
    struct Result: Equatable, Sendable {
        /// nil = 不设过滤（生产路径）。
        let visible: Set<MonitorCard>?
        let rejected: [String]
    }

    static func parse(_ raw: String?) -> Result {
        guard let raw, !raw.isEmpty else { return Result(visible: nil, rejected: []) }
        let tokens = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var accepted: Set<MonitorCard> = []
        var rejected: [String] = []
        for token in tokens {
            if let card = MonitorCard(rawValue: token.lowercased()) {
                accepted.insert(card)
            } else {
                rejected.append(token)
            }
        }
        // 含非法值就整批作废：只过滤掉一半的截图会被当成"卡都齐了"的假通过。
        guard rejected.isEmpty, !accepted.isEmpty else {
            return Result(visible: nil, rejected: rejected)
        }
        return Result(visible: accepted, rejected: [])
    }
}
