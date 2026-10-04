import SwiftUI
import Foundation
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
    @State private var processState: ProcessLoadState = .loading
    /// MM_MONITOR_CARDS 注入的显示过滤（nil = 全显示，生产路径）。
    @State private var visibleCards: Set<MonitorCard>?
    /// 上一帧判为"偏高"的温度键，喂给 HotBand 做进出双阈值（I11 防闪）。
    @State private var hotSensors = HotBandTrack()

    public init() {}

    private func shows(_ card: MonitorCard) -> Bool {
        guard let visibleCards else { return true }
        return visibleCards.contains(card)
    }

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
                    if shows(.stats) { statsRow }
                    if shows(.perCore) { perCoreCard }
                    if shows(.disk) { diskCard }
                    if shows(.memory) { memoryCard }
                    if shows(.process) { processCard }
                    if shows(.sensors) { sensorsCard }
                }
                .padding(MMGap.lg)
            }
        }
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            let hold = MonitorLoadHook.parse(env["MM_MONITOR_HOLD"]).holdInitialFrame
            let fixture = MonitorSnapshotFixture.parse(env["MM_MONITOR_FIXTURE"])
            if !fixture.rejected.isEmpty {
                FileHandle.standardError.write(
                    "MM_MONITOR_FIXTURE 含非法取值（\(fixture.rejected.joined(separator: ", "))），整个钩子已忽略\n"
                        .data(using: .utf8)!)
            }
            let cards = MonitorCardFilter.parse(env["MM_MONITOR_CARDS"])
            if !cards.rejected.isEmpty {
                FileHandle.standardError.write(
                    "MM_MONITOR_CARDS 含非法取值（\(cards.rejected.joined(separator: ", "))），整个钩子已忽略\n"
                        .data(using: .utf8)!)
            }
            visibleCards = cards.visible
            if hold {
                // 冻结在 .empty 首帧：不 enable（不采样）、不 loadProcesses，
                // 页面停在"测量中 + 骨架 + 内存尚未采样"的折叠线以上态，可被截图。
                menuBar.applyFixture(.empty)
            } else if let snapshot = fixture.snapshot {
                menuBar.applyFixture(snapshot)
                if let procs = fixture.processes {
                    processes = procs
                    processState = procs.isEmpty ? .empty : .loaded
                }
                // 不 enable：避免后台采样循环把夹具快照覆盖掉，保持截图稳定。
            } else {
                if !menuBar.isEnabled { menuBar.enable() }
                loadProcesses()
            }
            // `menubarOff` 档：把「菜单栏监控」开关定格在关。这一档自 #50 起就一直解析着却没人消费，
            // 所以文档里那行"关闭态已覆盖"是空的。开关读的是 `isEnabled == (statusItem != nil)`，
            // 而 `MacMasterApp` 启动即 enable，所以唯一办法是真把状态项摘掉；
            // 合成点击是禁止项，这条路径就是它存在的理由。放在 if/else 之后：
            // 单独给 `=menubarOff`（不注快照）也成立，拍的是真实数据 + 关态开关。
            if fixture.menubarOff { menuBar.disable() }
            // 夹具与冻结首帧都是在 onAppear 里同步落到 snapshot 上的，
            // onChange 不保证抓到这一次同周期变化，所以这里补一次播种。
            syncHotSensors(menuBar.snapshot.sensors.temperatures)
        }
        .onChange(of: menuBar.snapshot.sensors.temperatures) { _, temperatures in
            syncHotSensors(temperatures)
        }
    }

    /// 每帧把温度读数整体过一遍迟滞判定，热集合随之更新（见 HotBand.swift）。
    private func syncHotSensors(_ temperatures: [SensorTemperature]) {
        hotSensors.update(temperatures.map { ($0.key, $0.celsius as Double?) },
                          band: Self.hotBand)
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
                if menuBar.snapshot.diskReadBytesPerSecond == nil || menuBar.snapshot.diskWriteBytesPerSecond == nil {
                    Text("等待下一次采样计算速率")
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                }
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
                MMKeyRow("联动保留", MMFormat.bytes(memory.wiredBytes))
                // 口径：compressor_page_count × 页大小 = 压缩器池的物理占用（与"已用"同口径）。
                MMKeyRow("压缩", MMFormat.bytes(memory.compressedBytes))
                MMKeyRow("Swap", MenuBarManager.swapText(memory))
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

    // MARK: - 温度与风扇

    /// 本机 SMC 有 174 个可读温度键，整列铺开既读不完也撑爆卡片高度，
    /// 所以只按降序露最高的几个，其余用一行交代总数。
    private static let visibleTemperatureCount = 8
    /// 转红阈值是我们自定的：SMC 不告诉你"这个键算不算热"，90 °C 取的是距离
    /// Apple Silicon 节流点的经验余量，不是苹果给的官方阈值。
    /// 进 90 / 出 85（I11）：本机截图负载下实测最高 89.4 °C，离单点阈值只差 0.6 °C，
    /// 而采样每 2 秒一帧——单点判定时这一行的颜色会在 89.x↔90.x 之间闪。
    /// 改的是"什么时候复原"，不是"什么时候算热"：90 这个坎没挪。
    private static let hotBand = HotBand(enter: 90, exit: 85)

    private var sensorsCard: some View {
        card(title: "温度与风扇", systemImage: "thermometer.medium") {
            sensorsContent(menuBar.snapshot.sensors)
        }
    }

    @ViewBuilder
    private func sensorsContent(_ sensors: SensorsSnapshot) -> some View {
        switch sensors.status {
        case .unavailable(let reason):
            Text("—")
                .font(.callout)
                .foregroundStyle(MMColor.secondaryLabel)
            Text(reason)
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded:
            ForEach(sensors.temperatures.prefix(Self.visibleTemperatureCount)) { temp in
                HStack(spacing: MMGap.md) {
                    // SMC 原始键名，4 字符等宽；不给归属（苹果没公布键位对应哪个硬件）。
                    Text(temp.key)
                        .font(.callout.monospaced())
                        .foregroundStyle(MMColor.secondaryLabel)
                        .frame(width: 56, alignment: .leading)
                    Text(Self.temperatureText(temp.celsius))
                        .font(.callout.monospacedDigit())
                        // 数字是这一帧的，颜色要经过迟滞集合（从上一帧的状态起算）。
                        .foregroundStyle(hotSensors.isHot(temp.key) ? MMColor.destructive : MMColor.label)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: MMMetric.rowCompact)
            }
            if sensors.temperatures.count > Self.visibleTemperatureCount {
                Text("按键值降序显示最高的 \(Self.visibleTemperatureCount) 个，本机共 \(MMFormat.count(sensors.temperatures.count)) 个可信温度点。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            fansContent(sensors)
        }
    }

    @ViewBuilder
    private func fansContent(_ sensors: SensorsSnapshot) -> some View {
        if let fanCount = sensors.fanCount {
            if fanCount == 0 {
                MMKeyRow("风扇", "无（SMC 报告本机 0 台风扇）")
            } else {
                ForEach(sensors.fans) { fan in
                    MMKeyRow("风扇 \(fan.index + 1)", fanText(fan), monospaced: true)
                }
            }
        } else {
            // "不知道有几台"和"没有"是两句话——FNum 读不出时不画 0 台风扇。
            MMKeyRow("风扇", "—")
            Text("FNum 键没读到，风扇数量未知（未知不等于 0 台）。")
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fanText(_ fan: SensorFan) -> String {
        guard let current = fan.currentRPM else { return "—" }
        guard let minRPM = fan.minRPM, let maxRPM = fan.maxRPM else {
            return Self.rpmText(current) + " RPM"
        }
        return "\(Self.rpmText(current)) RPM（区间 \(Self.rpmText(minRPM))–\(Self.rpmText(maxRPM))）"
    }

    private static func temperatureText(_ celsius: Double) -> String {
        String(format: "%.1f °C", celsius)
    }

    private static func rpmText(_ rpm: Double) -> String {
        String(format: "%.0f", rpm)
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
            if processState == .loading {
                ForEach(0..<4, id: \.self) { _ in MMSkeletonRow() }
            } else if processState == .failed {
                MMEmptyState(systemImage: "exclamationmark.triangle", title: "进程列表读取失败",
                             detail: "无法枚举系统进程。点卡片上方的刷新按钮重试。")
            } else if processState == .empty {
                MMEmptyState(systemImage: "list.bullet", title: "没有可显示的进程",
                             detail: "枚举已完成，但没有取得可读取的进程详情。可刷新重试。")
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
        processState = .loading
        Task.detached(priority: .utility) {
            let result = ProcessReader.topProcesses()
            await MainActor.run {
                processes = result.processes
                processState = result.state
            }
        }
    }

    // MARK: - 卡片容器（令牌唯一来源）

    private func card<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        MMCard(padding: MMGap.md, style: .underPage) {
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
        }
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

public struct MonitorProcess: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let name: String
    public let pid: Int32
    /// 累计 CPU 秒（user + system），不是瞬时百分比。
    public let cpuSeconds: Double
    public let memoryBytes: UInt64
}

/// proc_pidinfo 枚举收进独立类型，视图不再直接做系统调用。
enum ProcessReader {
    static func topProcesses(limit: Int = 10) -> ProcessLoadResult {
        var pids = [pid_t](repeating: 0, count: 2048)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return ProcessLoadResult(state: .failed, processes: []) }

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

        let selected = Array(procs.sorted { $0.cpuSeconds > $1.cpuSeconds }.prefix(limit))
        return ProcessLoadResult(state: selected.isEmpty ? .empty : .loaded, processes: selected)
    }
}

enum ProcessLoadState: Equatable {
    case loading, loaded, empty, failed
}

struct ProcessLoadResult {
    let state: ProcessLoadState
    let processes: [MonitorProcess]
}
