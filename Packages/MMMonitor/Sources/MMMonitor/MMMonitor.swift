import SwiftUI
import MMCore
import MMUI

public struct MonitorModule: ModuleRegistrable {
    public var moduleID: String { "monitor" }
    public var moduleName: String { "系统监控" }
    public var moduleIcon: String { "gauge" }
    public var modulePriority: Int { 4 }

    public init() {}

    public func createView() -> AnyView {
        AnyView(MonitorView())
    }
}

public struct MonitorView: View {
    @StateObject private var menuBar = MenuBarManager.shared
    @State private var processes: [MonitorProcess] = []
    @State private var processLoadFailed = false

    public init() {}

    /// 首次采样前 sampledAt 还是 `.distantPast` 哨兵，直接格式化会渲染成
    /// "上次采样 0001-01-01 08:05"——那是把"还没测过"说成一个真实时刻。
    private var headerSubtitle: String {
        guard menuBar.snapshot.hasSampled else { return "尚未完成首次采样" }
        return "上次采样 \(MMFormat.dateTime(menuBar.snapshot.sampledAt)) · 实时更新"
    }

    public var body: some View {
        VStack(spacing: 0) {
            MMPageHeader("系统监控", subtitle: headerSubtitle) {
                Toggle("菜单栏监控", isOn: Binding(
                    get: { menuBar.isEnabled },
                    set: { $0 ? menuBar.enable() : menuBar.disable() }
                ))
                .toggleStyle(.switch)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: MMGap.lg) {
                    statsRow
                    perCoreCard
                    diskCard
                    memoryCard
                    processCard
                }
                .padding(MMGap.lg)
            }
        }
        .onAppear {
            if !menuBar.isEnabled {
                menuBar.enable()
            }
            loadProcesses()
        }
    }

    // MARK: - 顶部读数

    private var statsRow: some View {
        HStack(spacing: MMGap.md) {
            MMStatItem("CPU 总占用", MenuBarManager.percentText(menuBar.snapshot.totalCPU))
            MMStatItem("内存", MenuBarManager.percentText(menuBar.snapshot.memory?.usedRatio))
            MMStatItem("磁盘 读", rateText(menuBar.snapshot.diskReadBytesPerSecond))
            MMStatItem("磁盘 写", rateText(menuBar.snapshot.diskWriteBytesPerSecond))
        }
    }

    private func rateText(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return "—" }
        return MMFormat.compactBytes(UInt64(max(0, bytesPerSecond))) + "/s"
    }

    // MARK: - 每核 CPU

    private var perCoreCard: some View {
        card(title: "每核 CPU", systemImage: "cpu") {
            if menuBar.snapshot.perCoreCPU.isEmpty {
                Text("—")
                    .font(.callout)
                    .foregroundStyle(MMColor.secondaryLabel)
            } else {
                ForEach(Array(menuBar.snapshot.perCoreCPU.enumerated()), id: \.offset) { index, usage in
                    HStack(spacing: MMGap.md) {
                        Text("核 \(index + 1)")
                            .font(.callout)
                            .foregroundStyle(MMColor.secondaryLabel)
                            .frame(width: 56, alignment: .leading)
                        CoreUsageBar(usage: usage)
                        Text(MenuBarManager.percentText(usage))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(usage != nil && usage! >= 0.85 ? MMColor.destructive : MMColor.label)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .frame(height: MMMetric.rowCompact)
                }
            }
        }
    }

    // MARK: - 磁盘 IO

    private var diskCard: some View {
        card(title: "磁盘 IO", systemImage: "internaldrive") {
            switch menuBar.snapshot.diskIOStatus {
            case .ok:
                MMKeyRow("读取", rateText(menuBar.snapshot.diskReadBytesPerSecond), monospaced: true)
                MMKeyRow("写入", rateText(menuBar.snapshot.diskWriteBytesPerSecond), monospaced: true)
            case .unavailable(let reason):
                MMKeyRow("读取", "—", monospaced: true)
                MMKeyRow("写入", "—", monospaced: true)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 内存明细

    private var memoryCard: some View {
        card(title: "内存", systemImage: "memorychip") {
            if let memory = menuBar.snapshot.memory {
                MMKeyRow("已用", "\(MMFormat.bytes(memory.usedBytes)) / \(MMFormat.bytes(memory.totalBytes))")
                MMKeyRow("活动", MMFormat.bytes(memory.activeBytes))
                MMKeyRow("联动保留(wired)", MMFormat.bytes(memory.wiredBytes))
                // 口径：compressor_page_count × 页大小 = 压缩器池的物理占用（与"已用"同口径）。
                MMKeyRow("压缩", MMFormat.bytes(memory.compressedBytes))
                MMKeyRow("Swap", memory.swapAvailable
                    ? "\(MMFormat.bytes(memory.swapUsedBytes)) / \(MMFormat.bytes(memory.swapTotalBytes))"
                    : "—")
            } else if menuBar.snapshot.hasSampled {
                Text("内存读数不可用（host_statistics64 失败），显示 —。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            } else {
                Text("尚未完成首次采样，这里还没有内存读数。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            }
        }
    }

    // MARK: - 进程

    private var processCard: some View {
        card(title: "进程 TOP 10", systemImage: "list.bullet") {
            HStack(spacing: MMGap.sm) {
                Button {
                    loadProcesses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                Spacer()
            }
            if processes.isEmpty && !processLoadFailed {
                ForEach(0..<4, id: \.self) { _ in MMSkeletonRow() }
            } else if processLoadFailed {
                // 不猜原因：proc_listallpids 返回 0 和"每个 proc_pidinfo 都失败"都会走到这里，
                // 代码没有把两者分开。说清楚下一步做什么就够了。
                MMEmptyState(systemImage: "exclamationmark.triangle", title: "进程列表读取失败",
                             detail: "枚举系统进程没有拿到任何结果。点卡片上方的刷新按钮重试。")
            } else {
                ForEach(processes.prefix(10)) { proc in
                    HStack(spacing: MMGap.md) {
                        Text(proc.name)
                            .font(.body)
                            .lineLimit(1)
                        Spacer(minLength: MMGap.sm)
                        // pti_total_user/system 是累计 CPU 秒，不是瞬时百分比；
                        // 标成 "CPU x%" 是旧实现的误读，这里改成诚实的"CPU 时间"。
                        Text("CPU 时间 \(MMFormat.duration(proc.cpuSeconds))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MMColor.secondaryLabel)
                        Text(MMFormat.bytes(proc.memoryBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MMColor.secondaryLabel)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .frame(height: MMMetric.rowCompact)
                    .padding(.horizontal, MMGap.md)
                    .background(MMColor.contentBackground, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
                }
            }
        }
    }

    /// 进程枚举是同步系统调用，放到 detached task，别压主线程（采样同约定）。
    private func loadProcesses() {
        processLoadFailed = false
        Task.detached(priority: .utility) {
            let procs = ProcessReader.topProcesses()
            await MainActor.run {
                processes = procs
                processLoadFailed = procs.isEmpty
            }
        }
    }

    // MARK: - 卡片容器（令牌唯一来源）

    private func card<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MMGap.sm) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: MMMetric.iconSmall))
                    .foregroundStyle(MMColor.secondaryLabel)
                Text(title).font(.headline)
                Spacer()
            }
            content()
        }
        .padding(MMGap.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.cardBackground, in: RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous)
                .stroke(MMColor.separator)
        )
    }
}

/// 每核占用条：nil（未采出/回绕）画空槽，不画 0。
private struct CoreUsageBar: View {
    let usage: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(MMColor.fillActive)
                if let usage {
                    Capsule()
                        .fill(usage >= 0.85 ? MMColor.destructive : MMColor.accent)
                        .frame(width: max(2, geo.size.width * min(max(usage, 0), 1)))
                }
            }
        }
        .frame(height: 6)
    }
}

public struct MonitorProcess: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let pid: Int32
    /// 累计 CPU 秒（user + system），不是瞬时百分比。
    public let cpuSeconds: Double
    public let memoryBytes: UInt64
}

/// proc_pidinfo 枚举收进独立类型，视图不再直接做系统调用。
enum ProcessReader {
    static func topProcesses(limit: Int = 10) -> [MonitorProcess] {
        var pids = [pid_t](repeating: 0, count: 2048)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }

        var procs: [MonitorProcess] = []
        for i in 0..<Int(count) {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var info = proc_taskallinfo()
            let size = MemoryLayout<proc_taskallinfo>.size
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: Int8.self, capacity: size) {
                    proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, $0, Int32(size))
                }
            }
            guard result > 0 else { continue }

            let name = withUnsafePointer(to: &info.pbsd.pbi_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }

            let cpuSeconds = Double(info.ptinfo.pti_total_user + info.ptinfo.pti_total_system) / 1_000_000
            let memoryBytes = UInt64(info.ptinfo.pti_virtual_size)

            procs.append(MonitorProcess(
                name: name.isEmpty ? "pid:\(pid)" : name,
                pid: pid,
                cpuSeconds: cpuSeconds,
                memoryBytes: memoryBytes
            ))
        }

        return Array(procs.sorted { $0.cpuSeconds > $1.cpuSeconds }.prefix(limit))
    }
}
