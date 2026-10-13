import Foundation
import SwiftUI
import AppKit
import Combine
import MMCleaner
import MMCore
import MMFileScanner
import MMMonitor
import MMOptimizer

/// 仪表盘的数据源。原则：这里只放"每次都从系统量出来的"和"没量出来就显示 —"的，
/// 不允许出现写死的样例数字。采样与口径逻辑抽在 MMOptimizer 的纯函数里
/// （DashboardMemory / StorageBreakdown / MemoryComposition / DashboardText），便于单测。
@MainActor
final class DashboardModel: ObservableObject {
    @Published var volume: SystemSampler.Volume?
    @Published var memory: DashboardMemory.Reading?
    @Published var cpuLoad: Double?
    @Published var netRate: SystemSampler.NetBytes?
    @Published var sampledAt: Date?

    /// 磁盘 I/O：读不到时把 IOKit 给的原文原因一起带上，页面据此说明为什么是 "—"。
    @Published var diskRead: Double?
    @Published var diskWrite: Double?
    @Published var diskIOFailure: String?

    /// 迷你柱状图的历史。nil = 那一次没采到，画空槽；0 才是"确实没流量"。
    @Published private(set) var netHistory: [Double?] = []
    @Published private(set) var diskHistory: [Double?] = []

    /// 概览页页脚那句"N 个卷"。P35b 起口径换成**候选根数**（"我们能扫的卷"），
    /// 不再是枚举回来的条数：本机默认档 14 条挂载点里 13 条是系统切片与只读快照卷，
    /// 数条数会把"这台机器上有 14 个卷可看"说给一个只有一个能扫的用户（P35a §3）。
    /// nil = 这一趟一行都没读到，页脚显示占位而不是"0 个卷"（`MainWindow.swift` 那一格）。
    @Published var volumeCount: Int?
    @Published var filesystemName: String?

    let coreCount = ProcessInfo.processInfo.activeProcessorCount
    let performanceCoreCount = DashboardModel.sysctlInt("hw.perflevel0.physicalcpu")
    let efficiencyCoreCount = DashboardModel.sysctlInt("hw.perflevel1.physicalcpu")

    /// 可清理估算走状态机：没扫过就明说"未扫描"，绝不起手报一个编的数。
    @Published var reclaimState: ReclaimMeasureState = .notMeasured
    @Published var undoFailures: [TrashFailure] = []

    /// 扫描分类明细：概览页"可释放空间"列表与"可清理"总数共用这一次扫描结果，
    /// 分两次扫会量出两个不同的数，页面自己就会跟自己对不上。
    @Published private(set) var categories: [CacheCategory] = []
    @Published private(set) var trashBytes: UInt64?

    /// 扫描结果提供者。默认用清理页同一个 CacheScanner（真实扫描，不预估），
    /// 并且**按传进来的范围与排除清单扫**——概览以前走 `scanAll()`，那等于永远全开，
    /// 用户在清理页关掉类别之后概览照样把它们算进"可清理"。
    /// 测试注入假结果即可验证"求和与分类一致"，不碰真实用户文件。
    var categoriesProvider: @Sendable (CacheScanScope, [String]) async -> [CacheCategory]? = { scope, exclusions in
        await CacheScanner().scan(scope: scope, excludedFolderPaths: exclusions).categories
    }

    private var lastTicks: SystemSampler.CPUTicks?
    private var lastNet: SystemSampler.NetBytes?
    private var lastNetAt: Date?
    private var lastDisk: DiskIOCounters?
    private var lastDiskAt: Date?
    private var didStartMeasuring = false

    /// 每 2 秒采一次样。视图不可见时由调用方取消这个任务，避免后台空转。
    func sampleContinuously(interval: TimeInterval = 2) async {
        while !Task.isCancelled {
            sampleOnce()
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    func sampleOnce() {
        let volume = SystemSampler.volume()
        self.volume = volume
        memory = DashboardMemory.sample()
        trashBytes = SystemSampler.directoryBytes(NSHomeDirectory() + "/.Trash")
        // 卷名单**不在**这条 2 秒一跳的循环里读：一趟枚举本机 73 ms（P35a §8），
        // 而"插了块盘没重扫"这点新鲜度不值这些时间。它的两个刷新时点在 measureReclaimable 里。
        filesystemName = DashboardModel.filesystemName(ofPath: volume?.path ?? "/")

        if let ticks = SystemSampler.cpuTicks() {
            if let load = SystemSampler.load(from: lastTicks, to: ticks) {
                cpuLoad = load
            }
            lastTicks = ticks
        }

        let now = Date()
        if let net = SystemSampler.networkBytes() {
            var down: Double?
            if let previous = lastNet, let at = lastNetAt,
               let rate = SystemSampler.rate(from: previous, to: net,
                                            interval: now.timeIntervalSince(at)) {
                netRate = rate
                down = Double(rate.received)
            }
            netHistory = Self.push(netHistory, down)
            lastNet = net
            lastNetAt = now
        } else {
            netHistory = Self.push(netHistory, nil)
        }

        switch DiskIOReader.read() {
        case .success(let counters):
            var read: Double?
            if let previous = lastDisk, let at = lastDiskAt,
               let rate = DiskIODiff.rate(previous: previous, current: counters,
                                          interval: now.timeIntervalSince(at)) {
                diskRead = rate.readBytesPerSecond
                diskWrite = rate.writeBytesPerSecond
                read = rate.readBytesPerSecond
            }
            diskHistory = Self.push(diskHistory, read)
            lastDisk = counters
            lastDiskAt = now
            diskIOFailure = nil
        case .failure(let failure):
            // 量不到就整列空出来，历史槽也画成"不知道"，不然柱状图会显示成零流量。
            diskRead = nil
            diskWrite = nil
            diskIOFailure = failure.reason
            diskHistory = Self.push(diskHistory, nil)
        }

        sampledAt = now

        if !didStartMeasuring {
            didStartMeasuring = true
            Task { await measureReclaimable() }
        }
    }

    /// "可清理"这个数字和清理页用的是同一个扫描器、**同一套勾选与排除清单**，
    /// 两处不会量出两个结果。范围与排除都在调用时现读：设置页刚关掉「日志」，
    /// 点「重新测量」就该看到数字变小，而不是等重启。
    func measureReclaimable() async {
        guard reclaimState != .measuring else { return }
        reclaimState = .measuring
        // P35b B 档的刷新时点跟着这一件事走：载入时这里跑一次（`sampleOnce` 首帧起它），
        // 用户主动点「重新测量」时再跑一次。定时轮询、跟随选中项都没有。
        await refreshVolumeRoots()
        let settings = AppSettings.shared
        let scope = CacheScanScope.selected(systemCache: settings.scanSystemCache,
                                            appCache: settings.scanAppCache,
                                            logs: settings.scanLogFiles,
                                            temp: settings.scanTempFiles)
        guard !scope.isEmpty else {
            // 一个类别都没勾：不是"没扫到东西"，是"没让扫"。说成未扫描会让人一直等。
            categories = []
            reclaimState = .noCategorySelected
            return
        }
        // 排除清单也按清理页的口径合并：设置页的永久排除 + 清理页逐条排除的持久化名单。
        var exclusions = settings.excludedFolderPaths
        exclusions.append(contentsOf: CleanerExclusionStore().paths())
        let scanned = await categoriesProvider(scope, Array(Set(exclusions)).sorted())
        categories = scanned ?? []
        reclaimState = DashboardReclaim.state(from: scanned)
    }

    /// 页脚那句"N 个卷"：读的是**候选根数**（可浏览、是目录、总容量读得到的挂载点，
    /// 同一对容量数算一条），判据全在 `MMCore` 的纯函数里，这里只负责什么时候去读。
    /// 放到后台任务上：一趟 Foundation 枚举 + 逐条 `resourceValues` 本机量到 73 ms。
    private func refreshVolumeRoots() async {
        let count: Int? = await Task.detached(priority: .utility) {
            guard let rows = VolumeRootProbe.snapshot() else { return nil }
            return VolumeRoots.candidates(from: rows).count
        }.value
        volumeCount = count
    }

    /// 概览页的存储堆叠条：只由量得到的部分组成，缺哪段就不画哪段。
    var storageSegments: [StorageBreakdown.Segment] {
        guard let volume else { return [] }
        let reclaimable: UInt64?
        switch reclaimState {
        case .measured(let total, _): reclaimable = total
        default: reclaimable = nil
        }
        return StorageBreakdown.segments(total: volume.total, available: volume.available,
                                         reclaimable: reclaimable, trash: trashBytes)
    }

    var memoryParts: [MemoryComposition.Part]? { MemoryComposition.parts(memory) }

    var trashHistory: [TrashOperation] {
        Array(FileTrashService.shared.trashHistory.prefix(4))
    }

    /// 状态栏那句"上次清理"：只有真正移入过废纸篓才算，撤回掉的不算一次清理。
    var lastCleanupAt: Date? {
        FileTrashService.shared.trashHistory.first(where: { $0.isUndone == false })?.timestamp
    }

    func undo(_ operation: TrashOperation) async {
        let result = await FileTrashService.shared.undo(operationID: operation.id)
        undoFailures = result.failures
        sampleOnce()
    }

    // MARK: 内部

    /// 历史窗口长度：设计稿的迷你柱状图是 10~12 格，再多就成噪声了。
    private static let historyLength = 12

    private static func push(_ history: [Double?], _ value: Double?) -> [Double?] {
        var history = history
        history.append(value)
        if history.count > historyLength { history.removeFirst(history.count - historyLength) }
        return history
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value > 0 else { return nil }
        return Int(value)
    }

    /// 文件系统名来自 statfs 的 f_fstypename（"apfs"）。这是挂载表的原文，
    /// 不是猜的——NSFileManager 压根不暴露卷类型。
    private static func filesystemName(ofPath path: String) -> String? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        let capacity = MemoryLayout.size(ofValue: info.f_fstypename)
        let name = withUnsafePointer(to: &info.f_fstypename) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        return name.isEmpty ? nil : name.uppercased()
    }
}
