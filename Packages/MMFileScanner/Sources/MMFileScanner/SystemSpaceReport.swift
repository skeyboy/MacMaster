import Foundation

/// 只读空间报告（路线图 P4 第 4.6 项）。
///
/// 两件事都**只读取、只展示**：
/// - APFS 可清除空间：口径与访达/「关于本机」对齐，用 `volumeAvailableCapacityForImportantUsage`
///   减去普通可用容量。真正的 `purge` 需要 root，本项目不做。
/// - Time Machine 本地快照：只解析 `tmutil listlocalsnapshots` 的文本输出，
///   并且**只报条数和来历，不报字节**——APFS 不给单个快照的独立占用，无 root 也读不到，
///   拿"容器已用 − 各卷已用合计"去凑只会凑出元数据和预留空间（本机实测约 1.4 GB），
///   那不是快照足迹。删除快照需要 root 且会影响备份语义，明确不做（见 feature-roadmap「明确不采纳」）。
/// 一旦解析不出可信结构，整块降级成"不可用 + 原因"，绝不猜数字。

// MARK: - APFS 可清除空间

public struct PurgeableSpaceReport: Hashable, Sendable {
    public let volumeName: String
    public let volumePath: String
    public let totalCapacity: UInt64
    /// 访达口径：包含可清除空间。
    public let availableForImportantUsage: UInt64
    /// 普通口径：不含可清除空间，程序自己在写满时会看到这个数字。
    public let availableCapacity: UInt64
    public let isAvailable: Bool
    /// `isAvailable == false` 时说明为什么读不到，界面原样展示。
    public let reason: String?

    /// 两者的差额就是"系统认为可以清出去"的量。取 max(0, …) 是因为
    /// 某些 APFS 卷上普通可用会大于重要用途可用，差额为负时不能说"可清除 -3 GB"。
    public var purgeable: UInt64 {
        availableForImportantUsage > availableCapacity
            ? availableForImportantUsage - availableCapacity
            : 0
    }

    /// 不可用报告。UI 需要区分"读到了 0"和"没读到"。
    public static func unavailable(path: String, reason: String) -> PurgeableSpaceReport {
        PurgeableSpaceReport(
            volumeName: (path as NSString).lastPathComponent,
            volumePath: path,
            totalCapacity: 0,
            availableForImportantUsage: 0,
            availableCapacity: 0,
            isAvailable: false,
            reason: reason
        )
    }

    public init(volumeName: String, volumePath: String, totalCapacity: UInt64,
                availableForImportantUsage: UInt64, availableCapacity: UInt64,
                isAvailable: Bool, reason: String?) {
        self.volumeName = volumeName
        self.volumePath = volumePath
        self.totalCapacity = totalCapacity
        self.availableForImportantUsage = availableForImportantUsage
        self.availableCapacity = availableCapacity
        self.isAvailable = isAvailable
        self.reason = reason
    }
}

public enum PurgeableSpaceReader {
    /// 读单个卷。默认看启动卷（Data 卷与系统卷同一 APFS 容器，数字一致）。
    public static func read(at path: String = "/") -> PurgeableSpaceReport {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return .unavailable(path: path, reason: "路径不存在：\(path)")
        }
        guard let values = try? url.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]), let total = values.volumeTotalCapacity, total > 0 else {
            return .unavailable(path: path, reason: "该系统不支持读取卷容量信息")
        }
        guard let important = values.volumeAvailableCapacityForImportantUsage,
              let plain = values.volumeAvailableCapacity else {
            return .unavailable(path: path, reason: "该卷不提供「可清除空间」所需的容量口径")
        }
        return PurgeableSpaceReport(
            volumeName: values.volumeName ?? "Macintosh HD",
            volumePath: path,
            totalCapacity: UInt64(total),
            availableForImportantUsage: UInt64(max(0, important)),
            availableCapacity: UInt64(max(0, plain)),
            isAvailable: true,
            reason: nil
        )
    }
}

// MARK: - APFS 本地快照

public struct LocalSnapshot: Hashable, Sendable, Identifiable {
    /// 快照的来历。分这一档是因为本机上一台没接 Time Machine 的 Mac
    /// 也会有好几条 `com.apple.os.update-*`，把它们统称"Time Machine 快照"
    /// 会指错方向：前者是系统更新的安全网，动了会影响回滚。
    public enum Kind: String, Hashable, Sendable {
        case timeMachine
        case systemUpdate
        case other

        public var label: String {
            switch self {
            case .timeMachine: return "Time Machine"
            case .systemUpdate: return "系统更新"
            case .other: return "其他"
            }
        }
    }

    /// 完整快照标识，例如 com.apple.TimeMachine.2026-05-01-120100.local
    public let name: String
    public let volumePath: String?
    /// 名字里的时间戳读不出来时为 nil：此时只显示名字，不编造时间。
    public let date: Date?
    public let kind: Kind

    public var id: String { "\(volumePath ?? "")/\(name)" }

    public init(name: String, volumePath: String?, date: Date?) {
        self.name = name
        self.volumePath = volumePath
        self.date = date
        if name.contains("TimeMachine.") {
            self.kind = .timeMachine
        } else if name.hasPrefix("com.apple.os.update") {
            self.kind = .systemUpdate
        } else {
            self.kind = .other
        }
    }
}

/// 快照清单的两态。把"没有快照"和"读不出来"分开，是为了不把
/// "拿不到信息"渲染成"你的 Mac 很干净、多占了 0 GB"。
public enum LocalSnapshotListing: Hashable, Sendable {
    case available([LocalSnapshot])
    case unavailable(reason: String)

    public var snapshots: [LocalSnapshot] {
        if case .available(let items) = self { return items }
        return []
    }

    public var reason: String? {
        if case .unavailable(let text) = self { return text }
        return nil
    }

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public func count(of kind: LocalSnapshot.Kind) -> Int {
        snapshots.filter { $0.kind == kind }.count
    }
}

public enum LocalSnapshotReader {
    public enum CommandError: Error, Hashable {
        case launchFailed(String)
        case exited(Int32, String)
        case timedOut(TimeInterval)
    }

    /// `tmutil` 是系统自带的只读命令行工具；这里只用 `listlocalsnapshots`。
    public static let tmutilPath = "/usr/bin/tmutil"

    /// 表头有两种写法，都见过：
    /// - 老式：`Snapshots for disk /:`
    /// - macOS 11 起带签名系统卷的卷组：`Snapshots for volume group containing disk /:`
    /// 只认前一种会让这块卡片在新系统上**永远**显示"不可用"。
    private static let headerHeads = ["Snapshots for disk ", "Snapshots for volume group containing disk "]
    /// 快照标识都以 `com.apple.` 开头（含 `tmutil localsnapshot` 手工建的）。
    /// 其余行——警告、说明、空行——一律不算条目。
    private static let snapshotPrefix = "com.apple."

    /// 纯解析：单测直接喂样例文本，不依赖真机快照。
    public static func parse(_ output: String, fallbackVolume: String? = nil) -> LocalSnapshotListing {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return .unavailable(reason: "tmutil 没有任何输出")
        }

        var volume: String? = fallbackVolume
        var snapshots: [LocalSnapshot] = []
        var sawHeader = false

        for line in lines {
            let (isHeader, headerVolume) = headerMatch(in: line)
            if isHeader {
                sawHeader = true
                volume = headerVolume ?? fallbackVolume
                continue
            }
            guard line.hasPrefix(snapshotPrefix) else { continue }
            snapshots.append(LocalSnapshot(
                name: line, volumePath: volume, date: date(fromSnapshotName: line)
            ))
        }

        // 没有表头就认定这不是 listlocalsnapshots 的正常输出：
        // 报错文本、命令缺失时的包装信息、被本地化改写的版本都可能含
        // "com.apple." 字样，认下来就会把一份不存在的清单显示成"本机有 N 个快照"。
        guard sawHeader else {
            let first = lines.first ?? ""
            return .unavailable(reason: "无法解析 tmutil 输出：\(first.prefix(120))")
        }
        return .available(snapshots)
    }

    /// 是不是表头，以及表头里写的卷路径（写了但读不出来就是 nil，让调用方回落）。
    private static func headerMatch(in line: String) -> (Bool, String?) {
        for head in headerHeads where line.hasPrefix(head) {
            guard let colon = line.lastIndex(of: ":"), head.endIndex <= colon else {
                return (true, nil)
            }
            let path = String(line[head.endIndex..<colon])
                .trimmingCharacters(in: .whitespaces)
            return (true, path.isEmpty ? nil : path)
        }
        return (false, nil)
    }

    /// 快照名里的时间戳是 `yyyy-MM-dd-HHmmss`。格式随 macOS 版本变体很多，
    /// 解析失败只丢时间，不影响条目本身。
    static func date(fromSnapshotName name: String) -> Date? {
        guard let range = name.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: String(name[range]))
    }

    /// 执行一次 `tmutil listlocalsnapshots <volume>`。这是纯读取命令，
    /// 不删除快照、不申请 sudo；命令缺失或退出码非 0 都归为"不可用"。
    public static func read(
        volumePath: String = "/",
        timeout: TimeInterval = 5,
        runner: (String, [String], TimeInterval) throws -> String = run
    ) -> LocalSnapshotListing {
        do {
            let output = try runner(tmutilPath, ["listlocalsnapshots", volumePath], timeout)
            return parse(output, fallbackVolume: volumePath)
        } catch let error as CommandError {
            return .unavailable(reason: describe(error))
        } catch {
            return .unavailable(reason: "执行 tmutil 失败：\(error.localizedDescription)")
        }
    }

    private static func describe(_ error: CommandError) -> String {
        switch error {
        case .launchFailed(let message): return "无法执行 tmutil：\(message)"
        case .exited(let code, let message): return "tmutil 退出码 \(code)：\(message)"
        case .timedOut(let seconds): return "tmutil 在 \(Int(seconds)) 秒内没有返回"
        }
    }

    /// 默认真的命令执行器（`read` 的默认参数，因此必须是 public）。
    /// Process 的输出要在退出后一次性读完，否则大输出会把子进程堵在管道上。
    public static func run(executable: String, arguments: [String], timeout: TimeInterval) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CommandError.launchFailed("找不到可执行文件 \(executable)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                throw CommandError.timedOut(timeout)
            }
            usleep(20_000)
        }
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: outData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw CommandError.exited(process.terminationStatus,
                                      message.isEmpty ? "无错误输出" : message)
        }
        return text
    }
}

// MARK: - 供界面使用的只读汇总

public struct SystemSpaceReadout: Sendable {
    public let purgeable: PurgeableSpaceReport
    public let snapshots: LocalSnapshotListing
    public let readAt: Date

    public init(purgeable: PurgeableSpaceReport,
                snapshots: LocalSnapshotListing,
                readAt: Date = Date()) {
        self.purgeable = purgeable
        self.snapshots = snapshots
        self.readAt = readAt
    }
}

/// `tmutil` 要起子进程（秒级），不能在主线程上等，所以包一层 actor。
/// 这里只有读取，没有任何删除入口。
public actor SystemSpaceReporter {
    public init() {}

    public func readout(volumePath: String = "/") -> SystemSpaceReadout {
        SystemSpaceReadout(
            purgeable: PurgeableSpaceReader.read(at: volumePath),
            snapshots: LocalSnapshotReader.read(volumePath: volumePath)
        )
    }
}
