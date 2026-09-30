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
    case perCoreRed      // 每核 ≥85% 红档（核 1 = 91.4%）
    case perCoreEmpty    // D1：perCoreCPU 空数组 → 单「—」
    case diskUnavailable // D2：diskIOStatus=.unavailable(reason:)
    case processes       // 注入固定进程列表
    case menubarOff      // 菜单栏监控关闭态（不 enable、toggle off）
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

        for token in tokens {
            if token.hasPrefix("disk-unavailable:") {
                let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, !parts[1].isEmpty else { rejected.append(token); continue }
                diskReason = parts[1]
                accepted.append(.diskUnavailable)
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
                swapUsedBytes: 0,
                swapTotalBytes: 0,
                swapAvailable: true
            ),
            networkDownBytesPerSecond: 1.42e6,
            networkUpBytesPerSecond: 0.31e6,
            sampledAt: Date(timeIntervalSince1970: 1_700_000_000) // 固定时刻，hasSampled=true
        )
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
